import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../media/app_asset_picker.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'channel_direct_messages_service.dart';
import 'message_bubble.dart';
import 'outgoing_attachment.dart';

class ChannelDirectMessagesView extends StatefulWidget {
  const ChannelDirectMessagesView({
    super.key,
    required this.chatId,
    required this.title,
  });

  final int chatId;
  final String title;

  @override
  State<ChannelDirectMessagesView> createState() =>
      _ChannelDirectMessagesViewState();
}

class _ChannelDirectMessagesViewState extends State<ChannelDirectMessagesView> {
  late final ChannelDirectMessagesService _service =
      ChannelDirectMessagesService(chatId: widget.chatId);
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    unawaited(_service.start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.channelDirectMessages,
            onBack: () => Navigator.of(context).pop(),
            trailing: _refreshAction(),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final topics = _service.topics;
    if (topics.isEmpty && _service.loading) {
      return const Center(child: AppActivityIndicator(size: 24));
    }
    if (topics.isEmpty) {
      return _empty();
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: topics.length + (_service.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const InsetDivider(),
      itemBuilder: (context, index) {
        if (index == topics.length) {
          return _LoadMoreTopicsRow(
            loading: _service.loading,
            onTap: _service.loadMore,
          );
        }
        final topic = topics[index];
        return _DirectMessagesTopicRow(
          topic: topic,
          onTap: () => _openTopic(topic),
          onLongPress: () => _openTopicSettings(topic),
        );
      },
    );
  }

  Future<void> _refreshTopics() async {
    if (_refreshing || _service.loading) return;
    setState(() => _refreshing = true);
    try {
      final topics = _service.topics;
      if (topics.isEmpty) {
        await _service.loadMore();
      } else {
        await Future.wait(
          topics.map((topic) => _service.refreshTopic(topic.id)),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _refreshAction() {
    final loading = _service.loading || _refreshing;
    return Semantics(
      button: true,
      label: 'Refresh direct messages',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: loading ? null : () => unawaited(_refreshTopics()),
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

  Widget _empty() {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(HeroAppIcons.inbox, size: 44, color: colors.textTertiary),
            const SizedBox(height: 13),
            Text(
              AppStrings.t(AppStringKeys.channelDirectMessagesEmpty),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_service.error != null) ...[
              const SizedBox(height: 7),
              Text(
                _service.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            _TextAction(
              label: AppStringKeys.channelDirectMessagesReload,
              icon: HeroAppIcons.arrowsRotate,
              onTap: _service.loadMore,
            ),
          ],
        ),
      ),
    );
  }

  void _openTopic(DirectMessagesTopic topic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelDirectMessageTopicView(
          service: _service,
          topic: topic,
          channelTitle: widget.title,
        ),
      ),
    );
  }

  void _openTopicSettings(DirectMessagesTopic topic) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _DirectMessagesTopicSettingsSheet(service: _service, topic: topic),
    );
  }
}

class _DirectMessagesTopicRow extends StatelessWidget {
  const _DirectMessagesTopicRow({
    required this.topic,
    required this.onTap,
    required this.onLongPress,
  });

  final DirectMessagesTopic topic;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unread = topic.unreadCount > 0 || topic.isMarkedAsUnread;
    final title = topic.senderTitle.isEmpty
        ? AppStrings.t(AppStringKeys.channelDirectMessagesUnknownSender)
        : topic.senderTitle;
    final preview = topic.draftText.isNotEmpty
        ? AppStrings.t(AppStringKeys.channelDirectMessagesDraft, {
            'value1': topic.draftText,
          })
        : topic.lastMessage?.text ?? '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: colors.card,
        padding: const EdgeInsets.fromLTRB(14, 10, 13, 10),
        child: Row(
          children: [
            PhotoAvatar(title: title, photo: topic.senderPhoto),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (topic.lastMessage != null)
                        Text(
                          DateText.listLabel(topic.lastMessage!.date),
                          style: TextStyle(
                            color: unread
                                ? AppTheme.brand
                                : colors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (topic.canSendUnpaidMessages) ...[
                        AppIcon(
                          HeroAppIcons.solidStar,
                          size: 13,
                          color: AppTheme.brand,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          preview.isEmpty
                              ? AppStrings.t(
                                  AppStringKeys.channelDirectMessagesNoMessages,
                                )
                              : preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (topic.unreadReactionCount > 0) ...[
                        const SizedBox(width: 7),
                        AppIcon(
                          HeroAppIcons.heart,
                          size: 14,
                          color: AppTheme.tagRed,
                        ),
                      ],
                      if (unread) ...[
                        const SizedBox(width: 7),
                        Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.brand,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            topic.unreadCount > 0 ? '${topic.unreadCount}' : '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreTopicsRow extends StatelessWidget {
  const _LoadMoreTopicsRow({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: loading ? null : onTap,
    child: SizedBox(
      height: 52,
      child: Center(
        child: loading
            ? const AppActivityIndicator(size: 20)
            : Text(
                AppStrings.t(AppStringKeys.channelDirectMessagesLoadMore),
                style: TextStyle(color: AppTheme.brand, fontSize: 14),
              ),
      ),
    ),
  );
}

class ChannelDirectMessageTopicView extends StatefulWidget {
  const ChannelDirectMessageTopicView({
    super.key,
    required this.service,
    required this.topic,
    required this.channelTitle,
  });

  final ChannelDirectMessagesService service;
  final DirectMessagesTopic topic;
  final String channelTitle;

  @override
  State<ChannelDirectMessageTopicView> createState() =>
      _ChannelDirectMessageTopicViewState();
}

class _ChannelDirectMessageTopicViewState
    extends State<ChannelDirectMessageTopicView> {
  late final ChannelDirectMessageTopicController _controller =
      ChannelDirectMessageTopicController(
        chatId: widget.topic.chatId,
        topicId: widget.topic.id,
      );
  late final TextEditingController _text;
  final ScrollController _scroll = ScrollController();
  ChatMessage? _replyTo;
  Timer? _draftTimer;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.topic.draftText)
      ..addListener(_draftChanged);
    _controller.addListener(_changed);
    unawaited(_controller.start());
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_controller.messages.length > _lastMessageCount) {
      _lastMessageCount = _controller.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _draftChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_controller.saveDraft(_text.text));
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _draftTimer?.cancel();
    unawaited(_controller.saveDraft(_text.text));
    _controller.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _title => widget.topic.senderTitle.isEmpty
      ? AppStrings.t(AppStringKeys.channelDirectMessagesUnknownSender)
      : widget.topic.senderTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          NavHeader(
            title: _title,
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openSettings,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AppIcon(
                  HeroAppIcons.ellipsis,
                  size: 22,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(child: _transcript()),
          _composer(),
        ],
      ),
    );
  }

  Widget _transcript() {
    final messages = _controller.messages;
    if (messages.isEmpty && _controller.loading) {
      return const Center(child: AppActivityIndicator(size: 24));
    }
    if (messages.isEmpty) {
      return Center(
        child: Text(
          AppStrings.t(AppStringKeys.channelDirectMessagesStartConversation),
          style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length + (_controller.hasOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (_controller.hasOlder && index == 0) {
          return _LoadOlderMessagesRow(
            loading: _controller.loading,
            onTap: () => _controller.loadHistory(older: true),
          );
        }
        final messageIndex = index - (_controller.hasOlder ? 1 : 0);
        final message = messages[messageIndex];
        return Column(
          key: ValueKey('direct-message-${message.id}'),
          crossAxisAlignment: message.isOutgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            MessageBubble(
              message: message,
              peerTitle: _title,
              peerPhoto: widget.topic.senderPhoto,
              isGroup: true,
              meName: _controller.meName,
              mePhoto: _controller.mePhoto,
              meId: _controller.meId,
              forceShowTimestamp: true,
              onReply: (target) => setState(() => _replyTo = target),
            ),
            if (message.suggestedPostInfo != null ||
                (_controller.capabilities[message.id]?.hasActions ?? false))
              _SuggestedPostActions(
                message: message,
                capabilities:
                    _controller.capabilities[message.id] ??
                    const SuggestedPostCapabilities(),
                onApprove: () => _approve(message),
                onDecline: () => _decline(message),
                onEditOffer: () => _editOffer(message),
                onSuggestChanges: () => _suggestChanges(message),
                onEditText: message.isPlainText
                    ? () => _editText(message)
                    : null,
              ),
          ],
        );
      },
    );
  }

  Widget _composer() {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 9, 8),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null) ...[
              Row(
                children: [
                  Container(width: 3, height: 31, color: AppTheme.brand),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.t(
                            AppStringKeys.channelDirectMessagesReplying,
                          ),
                          style: TextStyle(
                            color: AppTheme.brand,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _replyTo!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _replyTo = null),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AppIcon(
                        HeroAppIcons.xmark,
                        size: 18,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  key: const ValueKey('suggestedPostComposerButton'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _composeSuggestedPost,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: AppIcon(
                      HeroAppIcons.penToSquare,
                      size: 23,
                      color: AppTheme.brand,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: 38,
                      maxHeight: 128,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colors.searchFill,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 5,
                      style: TextStyle(color: colors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: AppStrings.t(
                          AppStringKeys.channelDirectMessagesReplyHint,
                        ),
                        hintStyle: TextStyle(color: colors.textTertiary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _controller.sending ? null : _send,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.brand,
                      shape: BoxShape.circle,
                    ),
                    child: _controller.sending
                        ? const AppActivityIndicator(
                            size: 16,
                            color: Colors.white,
                          )
                        : const AppIcon(
                            HeroAppIcons.solidPaperPlane,
                            size: 18,
                            color: Colors.white,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final value = _text.text;
    if (value.trim().isEmpty) return;
    _text.clear();
    final replyToMessageId = _replyTo?.id ?? 0;
    setState(() => _replyTo = null);
    try {
      await _controller.sendText(value, replyToMessageId: replyToMessageId);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _composeSuggestedPost() async {
    final limits = await _controller.loadLimits();
    if (!mounted) return;
    final draft = await showModalBottomSheet<SuggestedPostDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SuggestedPostComposerSheet(limits: limits),
    );
    if (draft == null || !mounted) return;
    try {
      final attachment = draft.attachment;
      if (attachment == null) {
        await _controller.sendText(
          draft.text,
          price: draft.price,
          sendDate: draft.sendDate,
          asSuggestedPost: true,
        );
      } else {
        await _controller.sendAttachment(
          attachment,
          caption: draft.text,
          price: draft.price,
          sendDate: draft.sendDate,
          asSuggestedPost: true,
        );
      }
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _approve(ChatMessage message) async {
    final info = message.suggestedPostInfo;
    var sendDate = 0;
    if (info?.sendDate == 0) {
      final selected = await _pickSchedule(context);
      if (selected == null || !mounted) return;
      sendDate = selected;
    }
    try {
      await _controller.approve(message.id, sendDate: sendDate);
      if (mounted) showToast(context, AppStringKeys.suggestedPostApproved);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _decline(ChatMessage message) async {
    final comment = await _textDialog(
      title: AppStringKeys.suggestedPostDeclineTitle,
      hint: AppStringKeys.suggestedPostDeclineComment,
      maxLength: 128,
    );
    if (comment == null || !mounted) return;
    try {
      await _controller.decline(message.id, comment: comment);
      if (mounted) showToast(context, AppStringKeys.suggestedPostDeclined);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _editOffer(ChatMessage message) async {
    final limits = await _controller.loadLimits();
    if (!mounted) return;
    final draft = await showModalBottomSheet<SuggestedPostDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SuggestedPostComposerSheet(
        limits: limits,
        offerOnly: true,
        initialInfo: message.suggestedPostInfo,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await _controller.addOffer(
        message.id,
        price: draft.price,
        sendDate: draft.sendDate,
      );
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _suggestChanges(ChatMessage message) async {
    final limits = await _controller.loadLimits();
    if (!mounted) return;
    final draft = await showModalBottomSheet<SuggestedPostDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SuggestedPostComposerSheet(limits: limits),
    );
    if (draft == null || !mounted) return;
    try {
      final attachment = draft.attachment;
      if (attachment == null) {
        await _controller.sendText(
          draft.text,
          price: draft.price,
          sendDate: draft.sendDate,
          replyToMessageId: message.id,
          asSuggestedPost: true,
        );
      } else {
        await _controller.sendAttachment(
          attachment,
          caption: draft.text,
          price: draft.price,
          sendDate: draft.sendDate,
          replyToMessageId: message.id,
          asSuggestedPost: true,
        );
      }
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _editText(ChatMessage message) async {
    final value = await _textDialog(
      title: AppStringKeys.suggestedPostEditText,
      initialValue: message.text,
      hint: AppStringKeys.suggestedPostTextHint,
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    try {
      await _controller.editText(message.id, value);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<String?> _textDialog({
    required String title,
    required String hint,
    String initialValue = '',
    int? maxLength,
  }) => showAppTextEntryDialog(
    context,
    title: AppStrings.t(title),
    hint: AppStrings.t(hint),
    initial: initialValue,
    maxLength: maxLength,
    minLines: 2,
    maxLines: 4,
    cancelLabel: AppStrings.t(AppStringKeys.confirmCancel),
    actionLabel: AppStrings.t(AppStringKeys.addMembersDone),
  );

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DirectMessagesTopicSettingsSheet(
        service: widget.service,
        topic: widget.topic,
      ),
    );
  }
}

class _LoadOlderMessagesRow extends StatelessWidget {
  const _LoadOlderMessagesRow({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: loading
          ? const AppActivityIndicator(size: 18)
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  AppStrings.t(AppStringKeys.channelDirectMessagesOlder),
                  style: TextStyle(color: AppTheme.brand, fontSize: 13),
                ),
              ),
            ),
    ),
  );
}

class _SuggestedPostActions extends StatelessWidget {
  const _SuggestedPostActions({
    required this.message,
    required this.capabilities,
    required this.onApprove,
    required this.onDecline,
    required this.onEditOffer,
    required this.onSuggestChanges,
    this.onEditText,
  });

  final ChatMessage message;
  final SuggestedPostCapabilities capabilities;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  final VoidCallback onEditOffer;
  final VoidCallback onSuggestChanges;
  final VoidCallback? onEditText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final info = message.suggestedPostInfo;
    final status = switch (info?.state) {
      SuggestedPostState.pending => AppStringKeys.suggestedPostPending,
      SuggestedPostState.approved => AppStringKeys.suggestedPostApproved,
      SuggestedPostState.declined => AppStringKeys.suggestedPostDeclined,
      _ => AppStringKeys.suggestedPostOffer,
    };
    final details = <String>[
      if (info?.price != null) TDParse.suggestedPostPriceLabel(info!.price!),
      if ((info?.sendDate ?? 0) > 0)
        DateText.messageDetailLabel(info!.sendDate),
    ];
    return Container(
      margin: EdgeInsets.only(
        left: message.isOutgoing ? 74 : 58,
        right: message.isOutgoing ? 58 : 74,
        bottom: 7,
      ),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(
                HeroAppIcons.penToSquare,
                size: 16,
                color: AppTheme.brand,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  AppStrings.t(status),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (details.isNotEmpty)
                Text(
                  details.join(' · '),
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
            ],
          ),
          if (capabilities.hasActions) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: [
                if (capabilities.canBeApproved)
                  _CompactAction(
                    label: AppStringKeys.suggestedPostSuggestChanges,
                    icon: HeroAppIcons.arrowsRightLeft,
                    onTap: onSuggestChanges,
                  ),
                if (capabilities.canBeApproved)
                  _CompactAction(
                    label: AppStringKeys.suggestedPostApprove,
                    icon: HeroAppIcons.check,
                    onTap: onApprove,
                  ),
                if (capabilities.canBeDeclined)
                  _CompactAction(
                    label: AppStringKeys.suggestedPostDecline,
                    icon: HeroAppIcons.xmark,
                    onTap: onDecline,
                    destructive: true,
                  ),
                if (capabilities.canAddOffer ||
                    capabilities.canEditSuggestedPostInfo)
                  _CompactAction(
                    label: AppStringKeys.suggestedPostEditOffer,
                    icon: HeroAppIcons.star,
                    onTap: onEditOffer,
                  ),
                if (capabilities.canBeEdited && onEditText != null)
                  _CompactAction(
                    label: AppStringKeys.suggestedPostEditText,
                    icon: HeroAppIcons.pen,
                    onTap: onEditText!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppTheme.tagRed : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              AppStrings.t(label),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SuggestedPostDraft {
  const SuggestedPostDraft({
    required this.text,
    required this.price,
    required this.sendDate,
    this.attachment,
  });

  final String text;
  final SuggestedPostPrice? price;
  final int sendDate;
  final OutgoingAttachment? attachment;
}

class SuggestedPostComposerSheet extends StatefulWidget {
  const SuggestedPostComposerSheet({
    super.key,
    required this.limits,
    this.offerOnly = false,
    this.initialInfo,
  });

  final SuggestedPostLimits limits;
  final bool offerOnly;
  final MessageSuggestedPostInfo? initialInfo;

  @override
  State<SuggestedPostComposerSheet> createState() =>
      _SuggestedPostComposerSheetState();
}

class _SuggestedPostComposerSheetState
    extends State<SuggestedPostComposerSheet> {
  late final TextEditingController _text = TextEditingController();
  late final TextEditingController _amount = TextEditingController(
    text: _initialAmount(),
  );
  SuggestedPostPriceKind? _priceKind;
  int _sendDate = 0;
  OutgoingAttachment? _attachment;
  String? _error;

  @override
  void initState() {
    super.initState();
    _priceKind = widget.initialInfo?.price?.kind;
    _sendDate = widget.initialInfo?.sendDate ?? 0;
  }

  String _initialAmount() {
    final price = widget.initialInfo?.price;
    if (price == null) return '';
    return price.kind == SuggestedPostPriceKind.stars
        ? '${price.amount}'
        : (price.amount / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _text.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                AppStrings.t(
                  widget.offerOnly
                      ? AppStringKeys.suggestedPostEditOffer
                      : AppStringKeys.suggestedPostComposerTitle,
                ),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!widget.offerOnly) ...[
                const SizedBox(height: 12),
                _mediaPicker(),
                const SizedBox(height: 10),
                TextField(
                  controller: _text,
                  minLines: 3,
                  maxLines: 8,
                  autofocus: true,
                  style: TextStyle(color: colors.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: AppStrings.t(AppStringKeys.suggestedPostTextHint),
                    filled: true,
                    fillColor: colors.searchFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                AppStrings.t(AppStringKeys.suggestedPostPrice),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                children: [
                  _choice(null, AppStringKeys.suggestedPostFree),
                  _choice(
                    SuggestedPostPriceKind.stars,
                    AppStringKeys.suggestedPostStars,
                  ),
                  _choice(
                    SuggestedPostPriceKind.ton,
                    AppStringKeys.suggestedPostTon,
                  ),
                ],
              ),
              if (_priceKind != null) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: TextStyle(color: colors.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    labelText: AppStrings.t(
                      _priceKind == SuggestedPostPriceKind.stars
                          ? AppStringKeys.suggestedPostStarAmount
                          : AppStringKeys.suggestedPostTonAmount,
                    ),
                    filled: true,
                    fillColor: colors.searchFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _chooseSchedule,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: colors.searchFill,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        HeroAppIcons.clock,
                        size: 19,
                        color: AppTheme.brand,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _sendDate == 0
                              ? AppStrings.t(AppStringKeys.suggestedPostAnyTime)
                              : DateText.messageDetailLabel(_sendDate),
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (_sendDate != 0)
                        GestureDetector(
                          onTap: () => setState(() => _sendDate = 0),
                          child: AppIcon(
                            HeroAppIcons.xmark,
                            size: 18,
                            color: colors.textTertiary,
                          ),
                        )
                      else
                        AppIcon(
                          HeroAppIcons.chevronRight,
                          size: 16,
                          color: colors.textTertiary,
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 9),
                Text(
                  _error!,
                  style: TextStyle(color: AppTheme.tagRed, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _submit,
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    AppStrings.t(
                      widget.offerOnly
                          ? AppStringKeys.suggestedPostSubmitOffer
                          : AppStringKeys.suggestedPostSubmit,
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice(SuggestedPostPriceKind? kind, String label) {
    final selected = _priceKind == kind;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _priceKind = kind;
        _error = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.brand.withValues(alpha: 0.14)
              : context.colors.searchFill,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? AppTheme.brand : Colors.transparent,
          ),
        ),
        child: Text(
          AppStrings.t(label),
          style: TextStyle(
            color: selected ? AppTheme.brand : context.colors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _mediaPicker() {
    final colors = context.colors;
    final attachment = _attachment;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickMedia,
      child: Container(
        height: attachment == null ? 52 : 128,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.searchFill,
          borderRadius: BorderRadius.circular(11),
        ),
        child: attachment == null
            ? Row(
                children: [
                  const SizedBox(width: 12),
                  AppIcon(HeroAppIcons.image, size: 20, color: AppTheme.brand),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      AppStrings.t(AppStringKeys.suggestedPostAddMedia),
                      style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    ),
                  ),
                  AppIcon(
                    HeroAppIcons.chevronRight,
                    size: 16,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: 12),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (attachment.previewBytes != null)
                    Image.memory(attachment.previewBytes!, fit: BoxFit.cover)
                  else if (attachment.kind == OutgoingAttachmentKind.photo ||
                      attachment.kind == OutgoingAttachmentKind.animation)
                    Image.file(File(attachment.path), fit: BoxFit.cover)
                  else
                    ColoredBox(
                      color: colors.searchFill,
                      child: Center(
                        child: AppIcon(
                          HeroAppIcons.video,
                          size: 34,
                          color: AppTheme.brand,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 7,
                    right: 7,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _attachment = null),
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const AppIcon(
                          HeroAppIcons.xmark,
                          size: 17,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _pickMedia() async {
    final selection = await AppAssetPicker.pickDetailed(
      context,
      type: AppAssetPickerType.imageAndVideo,
      maxAssets: 1,
      photoMaxDimension: 2560,
    );
    if (!mounted || selection.assets.isEmpty) return;
    final asset = selection.assets.first;
    final file = asset.file;
    setState(() {
      _attachment = OutgoingAttachment(
        path: file.path,
        kind: galleryAttachmentKind(
          sendAsFile: false,
          isVideo: isPickedAssetVideo(file),
          isAnimation: isPickedAssetGif(file),
        ),
        fileName: file.name,
        previewBytes: asset.thumbnailBytes,
        width: asset.width,
        height: asset.height,
      );
    });
  }

  Future<void> _chooseSchedule() async {
    final value = await _pickSchedule(context);
    if (value != null && mounted) setState(() => _sendDate = value);
  }

  void _submit() {
    if (!widget.offerOnly && _text.text.trim().isEmpty && _attachment == null) {
      setState(
        () => _error = AppStrings.t(AppStringKeys.suggestedPostTextRequired),
      );
      return;
    }
    SuggestedPostPrice? price;
    if (_priceKind != null) {
      final raw = double.tryParse(_amount.text.trim());
      if (raw == null || raw <= 0) {
        setState(
          () => _error = AppStrings.t(AppStringKeys.suggestedPostInvalidAmount),
        );
        return;
      }
      final amount = _priceKind == SuggestedPostPriceKind.stars
          ? raw.round()
          : (raw * 100).round();
      final minimum = _priceKind == SuggestedPostPriceKind.stars
          ? widget.limits.minimumStars
          : widget.limits.minimumTonHundredths;
      final maximum = _priceKind == SuggestedPostPriceKind.stars
          ? widget.limits.maximumStars
          : widget.limits.maximumTonHundredths;
      if ((minimum > 0 && amount < minimum) ||
          (maximum > 0 && amount > maximum)) {
        setState(
          () => _error = AppStrings.t(AppStringKeys.suggestedPostAmountRange, {
            'value1': _priceKind == SuggestedPostPriceKind.stars
                ? '$minimum'
                : (minimum / 100).toStringAsFixed(2),
            'value2': _priceKind == SuggestedPostPriceKind.stars
                ? '$maximum'
                : (maximum / 100).toStringAsFixed(2),
          }),
        );
        return;
      }
      price = SuggestedPostPrice(kind: _priceKind!, amount: amount);
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final delay = _sendDate == 0 ? 0 : _sendDate - now;
    if (_sendDate != 0 &&
        ((widget.limits.minimumSendDelay > 0 &&
                delay < widget.limits.minimumSendDelay) ||
            (widget.limits.maximumSendDelay > 0 &&
                delay > widget.limits.maximumSendDelay))) {
      setState(
        () => _error = AppStrings.t(AppStringKeys.suggestedPostScheduleRange),
      );
      return;
    }
    Navigator.of(context).pop(
      SuggestedPostDraft(
        text: _text.text.trim(),
        price: price,
        sendDate: _sendDate,
        attachment: _attachment,
      ),
    );
  }
}

Future<int?> _pickSchedule(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now.add(const Duration(days: 1)),
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
  );
  if (time == null) return null;
  final selected = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (!selected.isAfter(now)) return null;
  return selected.millisecondsSinceEpoch ~/ 1000;
}

class _DirectMessagesTopicSettingsSheet extends StatefulWidget {
  const _DirectMessagesTopicSettingsSheet({
    required this.service,
    required this.topic,
  });

  final ChannelDirectMessagesService service;
  final DirectMessagesTopic topic;

  @override
  State<_DirectMessagesTopicSettingsSheet> createState() =>
      _DirectMessagesTopicSettingsSheetState();
}

class _DirectMessagesTopicSettingsSheetState
    extends State<_DirectMessagesTopicSettingsSheet> {
  int? _revenue;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRevenue());
  }

  Future<void> _loadRevenue() async {
    try {
      final value = await widget.service.revenue(widget.topic.id);
      if (mounted) setState(() => _revenue = value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                PhotoAvatar(
                  title: widget.topic.senderTitle,
                  photo: widget.topic.senderPhoto,
                  size: 44,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.topic.senderTitle,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _revenue == null
                            ? AppStrings.t(
                                AppStringKeys
                                    .channelDirectMessagesRevenueLoading,
                              )
                            : AppStrings.t(
                                AppStringKeys.channelDirectMessagesRevenue,
                                {'value1': _revenue},
                              ),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _sheetRow(
              label: widget.topic.canSendUnpaidMessages
                  ? AppStringKeys.channelDirectMessagesRequirePayment
                  : AppStringKeys.channelDirectMessagesAllowFree,
              icon: HeroAppIcons.solidStar,
              onTap: _toggleFreeMessages,
            ),
            _sheetRow(
              label: widget.topic.isMarkedAsUnread
                  ? AppStringKeys.channelDirectMessagesMarkRead
                  : AppStringKeys.channelDirectMessagesMarkUnread,
              icon: HeroAppIcons.eye,
              onTap: _markUnread,
            ),
            if (widget.topic.unreadReactionCount > 0)
              _sheetRow(
                label: AppStringKeys.channelDirectMessagesReadReactions,
                icon: HeroAppIcons.heart,
                onTap: _readReactions,
              ),
            _sheetRow(
              label: AppStringKeys.channelDirectMessagesUnpinAll,
              icon: HeroAppIcons.thumbtack,
              onTap: _unpinAll,
            ),
            _sheetRow(
              label: AppStringKeys.channelDirectMessagesClearRange,
              icon: HeroAppIcons.clock,
              destructive: true,
              onTap: _clearRange,
            ),
            _sheetRow(
              label: AppStringKeys.channelDirectMessagesClear,
              icon: HeroAppIcons.trash,
              destructive: true,
              onTap: _clear,
            ),
            if (_working)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Center(child: AppActivityIndicator(size: 18)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sheetRow({
    required String label,
    required AppIconData icon,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? AppTheme.tagRed : context.colors.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _working ? null : onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            AppIcon(icon, size: 20, color: color),
            const SizedBox(width: 11),
            Text(
              AppStrings.t(label),
              style: TextStyle(color: color, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFreeMessages() async {
    final enabling = !widget.topic.canSendUnpaidMessages;
    var refund = false;
    if (enabling) {
      final cancelLabel = AppStrings.t(AppStringKeys.confirmCancel);
      final choice = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: cancelLabel,
        barrierColor: Colors.black.withValues(alpha: 0.52),
        transitionDuration: const Duration(milliseconds: 160),
        transitionBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        ),
        pageBuilder: (dialogContext, _, _) => AppDialogSurface(
          title: AppStrings.t(AppStringKeys.channelDirectMessagesRefundTitle),
          content: Text(
            AppStrings.t(AppStringKeys.channelDirectMessagesRefundMessage),
            textAlign: TextAlign.center,
            style: AppTextStyle.body(dialogContext.colors.textSecondary),
          ),
          actions: [
            AppDialogAction(
              label: cancelLabel,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
            AppDialogAction(
              label: AppStrings.t(AppStringKeys.channelDirectMessagesAllowOnly),
              onTap: () => Navigator.of(dialogContext).pop(false),
            ),
            AppDialogAction(
              label: AppStrings.t(
                AppStringKeys.channelDirectMessagesAllowAndRefund,
              ),
              primary: true,
              onTap: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      refund = choice;
    }
    await _run(
      () => widget.service.setCanSendUnpaidMessages(
        widget.topic.id,
        canSendUnpaidMessages: enabling,
        refundPayments: refund,
      ),
    );
  }

  Future<void> _markUnread() => _run(
    () => widget.service.markUnread(
      widget.topic.id,
      !widget.topic.isMarkedAsUnread,
    ),
  );

  Future<void> _readReactions() =>
      _run(() => widget.service.readAllReactions(widget.topic.id));

  Future<void> _unpinAll() =>
      _run(() => widget.service.unpinAll(widget.topic.id));

  Future<void> _clearRange() async {
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 7)),
      firstDate: DateTime(2013),
      lastDate: now,
      helpText: AppStrings.t(AppStringKeys.channelDirectMessagesRangeStart),
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: start,
      lastDate: now,
      helpText: AppStrings.t(AppStringKeys.channelDirectMessagesRangeEnd),
    );
    if (end == null || !mounted) return;
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.channelDirectMessagesClearRange,
      message: AppStrings.t(
        AppStringKeys.channelDirectMessagesClearRangeConfirm,
      ),
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final minDate =
        DateTime(start.year, start.month, start.day).millisecondsSinceEpoch ~/
        1000;
    final maxDate =
        DateTime(
          end.year,
          end.month,
          end.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch ~/
        1000;
    await _run(
      () => widget.service.clearHistoryByDate(
        widget.topic.id,
        minDate: minDate,
        maxDate: maxDate,
      ),
    );
  }

  Future<void> _clear() async {
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.channelDirectMessagesClear,
      message: AppStrings.t(AppStringKeys.channelDirectMessagesClearConfirm),
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(() => widget.service.clearHistory(widget.topic.id));
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() => _working = true);
    try {
      await operation();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _working = false);
        showToast(context, error.toString());
      }
    }
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 16, color: AppTheme.brand),
          const SizedBox(width: 6),
          Text(
            AppStrings.t(label),
            style: TextStyle(
              color: AppTheme.brand,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
