import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../app/app_navigator.dart';
import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'chat_view.dart';
import 'custom_emoji.dart';
import 'message_bubble.dart';
import 'saved_messages_service.dart';

enum _SavedMessagesTab { messages, sources }

class SavedMessagesView extends StatefulWidget {
  const SavedMessagesView({super.key, this.service});

  final SavedMessagesService? service;

  @override
  State<SavedMessagesView> createState() => _SavedMessagesViewState();
}

class _SavedMessagesViewState extends State<SavedMessagesView> {
  late final SavedMessagesService _service =
      widget.service ?? SavedMessagesService();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final Map<int, SavedMessagesTopicRecord> _topics = {};
  final Map<int, String> _chatTitles = {};
  final List<SavedMessageRecord> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _updates;
  Timer? _searchDebounce;
  _SavedMessagesTab _tab = _SavedMessagesTab.messages;
  SavedMessagesTopicRecord? _selectedTopic;
  SavedMessagesTagRecord? _selectedTag;
  List<SavedMessagesTagRecord> _tags = const [];
  bool _loadingMessages = false;
  bool _hasMoreMessages = true;
  bool _messagesFailed = false;
  int _nextMessageId = 0;
  int _messageGeneration = 0;
  bool _loadingTopics = false;
  bool _topicsExhausted = false;
  String _meName = '';
  TdFileRef? _mePhoto;
  int? _meId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.service == null) {
      _updates = TdClient.shared.subscribe().listen(_handleUpdate);
    }
    unawaited(_loadMe());
    unawaited(_loadTags());
    unawaited(_resetMessages());
    unawaited(_loadMoreTopics());
  }

  @override
  void dispose() {
    _updates?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _handleUpdate(Map<String, dynamic> update) {
    switch (update.type) {
      case 'updateSavedMessagesTopic':
        final raw = update.obj('topic');
        if (raw == null) return;
        final topic = SavedMessagesTopicRecord.fromUpdate(raw);
        if (!mounted || topic.id == 0) return;
        setState(() {
          if (topic.order == 0) {
            _topics.remove(topic.id);
          } else {
            _topics[topic.id] = topic;
          }
          if (_selectedTopic?.id == topic.id) _selectedTopic = topic;
        });
        final sourceChatId = topic.sourceChatId;
        if (sourceChatId != null) unawaited(_resolveChatTitle(sourceChatId));
      case 'updateSavedMessagesTags':
        final topicId = update.int64('saved_messages_topic_id') ?? 0;
        if (topicId == (_selectedTopic?.id ?? 0)) unawaited(_loadTags());
      case 'updateNewMessage':
        final message = update.obj('message');
        if (message == null) return;
        unawaited(_refreshIfSavedMessage(message));
      case 'updateUser':
        unawaited(_loadMe());
    }
  }

  Future<void> _loadMe() async {
    try {
      final me = await _service.currentUser();
      if (!mounted) return;
      setState(() {
        _meId = me.int64('id');
        _meName = TDParse.userName(me);
        _mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      });
    } catch (_) {}
  }

  Future<void> _refreshIfSavedMessage(Map<String, dynamic> message) async {
    try {
      final savedChatId = await _service.savedChatId();
      if (!mounted || message.int64('chat_id') != savedChatId) return;
      await _resetMessages();
    } catch (_) {}
  }

  void _onScroll() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 500) return;
    if (_tab == _SavedMessagesTab.messages) {
      unawaited(_loadMoreMessages());
    } else {
      unawaited(_loadMoreTopics());
    }
  }

  List<SavedMessagesTopicRecord> get _sortedTopics {
    final topics = _topics.values.where((topic) => topic.order != 0).toList();
    topics.sort((a, b) => b.order.compareTo(a.order));
    return topics;
  }

  Future<void> _loadMoreTopics() async {
    if (_loadingTopics || _topicsExhausted) return;
    _loadingTopics = true;
    try {
      await _service.loadTopics();
    } catch (error) {
      if ('$error'.contains('404')) _topicsExhausted = true;
    } finally {
      _loadingTopics = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await _service.tags(topicId: _selectedTopic?.id ?? 0);
      if (!mounted) return;
      setState(() {
        _tags = tags;
        final selected = _selectedTag;
        if (selected != null) {
          _selectedTag = tags
              .where((tag) => tag.key == selected.key)
              .firstOrNull;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _tags = const []);
    }
  }

  Future<void> _resetMessages() async {
    final generation = ++_messageGeneration;
    setState(() {
      _messages.clear();
      _nextMessageId = 0;
      _hasMoreMessages = true;
      _messagesFailed = false;
      _loadingMessages = false;
    });
    await _loadMoreMessages(generation: generation);
  }

  Future<void> _loadMoreMessages({int? generation}) async {
    final expectedGeneration = generation ?? _messageGeneration;
    if (_loadingMessages || !_hasMoreMessages) return;
    setState(() {
      _loadingMessages = true;
      _messagesFailed = false;
    });
    try {
      final page = await _service.messages(
        topicId: _selectedTopic?.id ?? 0,
        query: _search.text,
        tag: _selectedTag,
        fromMessageId: _nextMessageId,
      );
      if (!mounted || expectedGeneration != _messageGeneration) return;
      final seen = _messages.map((message) => message.id).toSet();
      final fresh = page.messages.where((message) => seen.add(message.id));
      setState(() {
        _messages.addAll(fresh);
        _nextMessageId = page.nextFromMessageId;
        _hasMoreMessages = page.hasMore && page.nextFromMessageId != 0;
      });
      unawaited(_resolveMessageSources(page.messages));
    } catch (_) {
      if (!mounted || expectedGeneration != _messageGeneration) return;
      setState(() {
        _messagesFailed = true;
        _hasMoreMessages = false;
      });
    } finally {
      if (mounted && expectedGeneration == _messageGeneration) {
        setState(() => _loadingMessages = false);
      }
    }
  }

  Future<void> _resolveMessageSources(List<SavedMessageRecord> records) async {
    final ids = <int>{
      for (final record in records)
        if (record.originalChatId case final int id) id,
    };
    for (final id in ids) {
      await _resolveChatTitle(id);
    }
  }

  Future<void> _resolveChatTitle(int chatId) async {
    if (_chatTitles.containsKey(chatId)) return;
    try {
      final chat = await _service.getChat(chatId);
      if (!mounted) return;
      setState(() => _chatTitles[chatId] = chat.str('title') ?? 'Chat $chatId');
    } catch (_) {
      if (mounted) setState(() => _chatTitles[chatId] = 'Chat $chatId');
    }
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 320),
      () => unawaited(_resetMessages()),
    );
  }

  Future<void> _selectTopic(SavedMessagesTopicRecord topic) async {
    setState(() {
      _selectedTopic = topic;
      _selectedTag = null;
      _tab = _SavedMessagesTab.messages;
      _search.clear();
    });
    await _loadTags();
    await _resetMessages();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _clearTopic() async {
    setState(() {
      _selectedTopic = null;
      _selectedTag = null;
    });
    await _loadTags();
    await _resetMessages();
  }

  Future<void> _selectTag(SavedMessagesTagRecord? tag) async {
    setState(() => _selectedTag = tag);
    await _resetMessages();
  }

  Future<void> _renameTag(SavedMessagesTagRecord tag) async {
    final label = await showAppTextEntryDialog(
      context,
      title: 'Tag label',
      hint: 'Optional label',
      initial: tag.label,
      maxLength: 12,
      cancelLabel: AppStringKeys.countryPickerCancel.l10n(context),
      actionLabel: AppStringKeys.accentColorPickerSave.l10n(context),
    );
    if (label == null) return;
    try {
      await _service.setTagLabel(tag, label);
      await _loadTags();
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t rename tag: $error');
    }
  }

  Future<void> _toggleTopicPinned(SavedMessagesTopicRecord topic) async {
    try {
      await _service.setTopicPinned(topic.id, !topic.isPinned);
    } catch (error) {
      if (mounted) showToast(context, 'Couldn’t change pinned topic: $error');
    }
  }

  Future<void> _openOriginal(SavedMessageRecord record) async {
    final chatId = record.originalChatId;
    final messageId = record.originalMessageId;
    if (chatId == null || messageId == null) return;
    var title = _chatTitles[chatId] ?? '';
    if (title.isEmpty) {
      try {
        final chat = await _service.getChat(chatId);
        title = chat.str('title') ?? '';
      } catch (_) {}
    }
    if (!mounted) return;
    final nav = appNavigatorKey.currentState ?? Navigator.of(context);
    unawaited(
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChatView(
            chatId: chatId,
            title: title,
            initialMessageId: messageId,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.savedMessages,
            onBack: () => Navigator.of(context).pop(),
            trailing: _refreshAction(),
          ),
          _tabSwitcher(),
          if (_tab == _SavedMessagesTab.messages) ...[
            _searchField(),
            if (_selectedTopic != null) _topicFilterHeader(),
            if (_tags.isNotEmpty) _tagStrip(),
          ],
          Expanded(
            child: _tab == _SavedMessagesTab.messages
                ? _messageList()
                : _topicList(),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshCurrent() async {
    if (_tab == _SavedMessagesTab.messages) {
      await _resetMessages();
      return;
    }
    _topicsExhausted = false;
    await _loadMoreTopics();
  }

  Widget _refreshAction() {
    final loading = _tab == _SavedMessagesTab.messages
        ? _loadingMessages
        : _loadingTopics;
    return Semantics(
      button: true,
      label: 'Refresh saved messages',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: loading ? null : () => unawaited(_refreshCurrent()),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: AppIcon(
            HeroAppIcons.arrowsRotate,
            size: 19,
            color: loading
                ? context.colors.textTertiary
                : context.colors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _tabSwitcher() {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _tabButton(_SavedMessagesTab.messages, 'Messages'),
          _tabButton(_SavedMessagesTab.sources, 'Chats'),
        ],
      ),
    );
  }

  Widget _tabButton(_SavedMessagesTab tab, String label) {
    final c = context.colors;
    final selected = _tab == tab;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _tab = tab);
          if (tab == _SavedMessagesTab.sources) unawaited(_loadMoreTopics());
          if (_scroll.hasClients) _scroll.jumpTo(0);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 5,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: AppTextStyle.body(
              selected ? c.textPrimary : c.textSecondary,
              weight: selected ? AppTextWeight.semibold : AppTextWeight.regular,
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    final c = context.colors;
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          AppIcon(
            HeroAppIcons.magnifyingGlass,
            size: 18,
            color: c.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              style: AppTextStyle.body(c.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Search saved messages',
                isDense: true,
              ),
            ),
          ),
          if (_search.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _search.clear();
                setState(() {});
                unawaited(_resetMessages());
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AppIcon(
                  HeroAppIcons.circleXmark,
                  size: 18,
                  color: c.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topicFilterHeader() {
    final topic = _selectedTopic!;
    final c = context.colors;
    return Container(
      height: 42,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          AppIcon(HeroAppIcons.folder, size: 18, color: AppTheme.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _topicTitle(topic),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.body(
                c.textPrimary,
                weight: AppTextWeight.semibold,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _clearTopic,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: AppIcon(
                HeroAppIcons.xmark,
                size: 17,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagStrip() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _tagChip(null),
          for (final tag in _tags) ...[const SizedBox(width: 7), _tagChip(tag)],
        ],
      ),
    );
  }

  Widget _tagChip(SavedMessagesTagRecord? tag) {
    final c = context.colors;
    final selected = tag == null
        ? _selectedTag == null
        : tag.key == _selectedTag?.key;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectTag(tag),
      onLongPress: tag == null ? null : () => _renameTag(tag),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand : c.card,
          border: Border.all(color: selected ? AppTheme.brand : c.divider),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tag == null)
              Text(
                'All',
                style: AppTextStyle.footnote(
                  selected ? Colors.white : c.textPrimary,
                ),
              )
            else ...[
              if (tag.type.type == 'reactionTypeCustomEmoji')
                CustomEmojiView(
                  id: tag.type.int64('custom_emoji_id') ?? 0,
                  size: 18,
                  color: selected ? Colors.white : c.textPrimary,
                )
              else
                Text(
                  tag.type.str('emoji') ?? '',
                  style: const TextStyle(fontSize: 16),
                ),
              if (tag.label.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  tag.label,
                  style: AppTextStyle.footnote(
                    selected ? Colors.white : c.textPrimary,
                  ),
                ),
              ],
              if (tag.count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '${tag.count}',
                  style: AppTextStyle.footnote(
                    selected ? Colors.white70 : c.textTertiary,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _messageList() {
    if (_loadingMessages && _messages.isEmpty) {
      return const Center(child: AppActivityIndicator(size: 24));
    }
    if (_messagesFailed && _messages.isEmpty) {
      return _emptyState(
        HeroAppIcons.triangleExclamation,
        'Saved messages couldn’t be loaded',
        action: _resetMessages,
      );
    }
    if (_messages.isEmpty) {
      return _emptyState(HeroAppIcons.thumbtack, 'No saved messages found');
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
      itemCount: _messages.length + (_loadingMessages ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: AppActivityIndicator(size: 22)),
          );
        }
        return _savedMessage(_messages[index]);
      },
    );
  }

  Widget _savedMessage(SavedMessageRecord record) {
    final message = record.message;
    if (message == null) return const SizedBox.shrink();
    final c = context.colors;
    final originalChatId = record.originalChatId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (record.originalMessageId != null && originalChatId != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openOriginal(record),
              child: Container(
                height: 36,
                margin: const EdgeInsets.symmetric(horizontal: 9),
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                  border: Border.all(color: c.divider, width: 0.5),
                ),
                child: Row(
                  children: [
                    AppIcon(
                      HeroAppIcons.arrowTopRight,
                      size: 16,
                      color: c.linkBlue,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Open original in ${_chatTitles[originalChatId] ?? 'source chat'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.footnote(c.linkBlue),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          MessageBubble(
            message: message,
            peerTitle: _meName.isEmpty ? AppStringKeys.savedMessages : _meName,
            peerPhoto: _mePhoto,
            isGroup: false,
            meName: _meName.isEmpty ? AppStringKeys.chatMeLabel : _meName,
            mePhoto: _mePhoto,
            meId: _meId,
            forceShowTimestamp: true,
          ),
        ],
      ),
    );
  }

  Widget _topicList() {
    final topics = _sortedTopics;
    if (topics.isEmpty && _loadingTopics) {
      return const Center(child: AppActivityIndicator(size: 24));
    }
    if (topics.isEmpty) {
      return _emptyState(HeroAppIcons.folder, 'No Saved Messages chats yet');
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      itemCount: topics.length + (_loadingTopics ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        if (index == topics.length) {
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: AppActivityIndicator(size: 22)),
          );
        }
        return _topicRow(topics[index]);
      },
    );
  }

  Widget _topicRow(SavedMessagesTopicRecord topic) {
    final c = context.colors;
    final last = topic.lastMessage;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectTopic(topic),
      child: Container(
        height: 72,
        padding: const EdgeInsets.fromLTRB(13, 9, 8, 9),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AppIcon(
                topic.type == 'savedMessagesTopicTypeMyNotes'
                    ? HeroAppIcons.penToSquare
                    : HeroAppIcons.folder,
                size: 22,
                color: AppTheme.brand,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _topicTitle(topic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.bodyLarge(
                            c.textPrimary,
                            weight: AppTextWeight.semibold,
                          ),
                        ),
                      ),
                      if (last != null)
                        Text(
                          DateText.listLabel(last.date),
                          style: AppTextStyle.footnote(c.textTertiary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    last?.text.trim().isNotEmpty == true
                        ? last!.text
                        : 'Saved messages',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.body(c.textSecondary),
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleTopicPinned(topic),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: AppIcon(
                  topic.isPinned ? HeroAppIcons.solidStar : HeroAppIcons.star,
                  size: 18,
                  color: topic.isPinned ? AppTheme.brand : c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _topicTitle(SavedMessagesTopicRecord topic) => switch (topic.type) {
    'savedMessagesTopicTypeMyNotes' => 'My Notes',
    'savedMessagesTopicTypeAuthorHidden' => 'Hidden Author',
    'savedMessagesTopicTypeSavedFromChat' =>
      _chatTitles[topic.sourceChatId] ?? 'Chat ${topic.sourceChatId ?? ''}',
    _ => 'Saved Messages',
  };

  Widget _emptyState(
    AppIconData icon,
    String text, {
    Future<void> Function()? action,
  }) {
    final c = context.colors;
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 34, color: c.textTertiary),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: AppTextStyle.body(c.textSecondary),
              ),
              if (action != null) ...[
                const SizedBox(height: 8),
                Text('Tap to retry', style: AppTextStyle.body(c.linkBlue)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
