//
//  search_view.dart
//
//  Chat search — a pushed secondary screen. Custom header (back chevron +
//  rounded search field) on the list-header wash, with a live list of matching
//  chats below. Port of the Swift `SearchView` / `_SearchViewModel`.
//

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'chat_row_view.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _vm = _SearchViewModel();
  _SearchTab _tab = _SearchTab.chats;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _vm.addListener(() => setState(() {}));
    _vm.search('', _tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _focus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CupertinoPageScaffold(
      backgroundColor: c.groupedBackground,
      child: Column(
        children: [
          _header(),
          Expanded(child: _results()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.listHeaderTint,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: AppIcon(
                        HeroAppIcons.chevronLeft,
                        size: 22,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          AppIcon(
                            HeroAppIcons.magnifyingGlass,
                            size: 15,
                            color: c.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: CupertinoTextField(
                              controller: _controller,
                              focusNode: _focus,
                              autocorrect: false,
                              textInputAction: TextInputAction.search,
                              style: TextStyle(
                                fontSize: 15,
                                color: c.textPrimary,
                              ),
                              placeholder: AppStrings.t(
                                AppStringKeys.topicChatSearch,
                              ),
                              placeholderStyle: TextStyle(
                                fontSize: 15,
                                color: c.textTertiary,
                              ),
                              padding: EdgeInsets.zero,
                              decoration: null,
                              onChanged: (q) {
                                setState(() => _query = q);
                                _vm.search(q, _tab);
                              },
                            ),
                          ),
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                setState(() => _query = '');
                                _vm.search('', _tab);
                              },
                              child: AppIcon(
                                HeroAppIcons.xmark,
                                size: 16,
                                color: c.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _tabBar(),
        ],
      ),
    );
  }

  Widget _results() {
    final c = context.colors;
    final hits = _vm.resultsFor(_tab);
    final allowEmptyQuery = _tab != _SearchTab.chats;
    if (_query.trim().isEmpty && !allowEmptyQuery) {
      return _empty(AppStrings.t(AppStringKeys.chatsSearchPlaceholder));
    }
    if (_vm.isLoading(_tab) && hits.isEmpty) {
      return Container(
        color: c.groupedBackground,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CupertinoActivityIndicator(radius: 11),
        ),
      );
    }
    if (hits.isEmpty) {
      return _empty(AppStrings.t(AppStringKeys.chatsSearchNoResults));
    }
    return Container(
      color: c.background,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: hits.length,
        itemBuilder: (context, i) {
          final hit = hits[i];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _open(hit),
                child: hit.chat != null
                    ? ChatRowView(chat: hit.chat!)
                    : _hitRow(hit),
              ),
              const InsetDivider(leadingInset: 78),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(_SearchHit hit) async {
    if (hit.message != null && hit.chatId != null) {
      final title = hit.sourceTitle;
      await Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => ChatView(
            chatId: hit.chatId!,
            title: title.isEmpty ? hit.title : title,
            initialMessageId: hit.message!.id,
          ),
        ),
      );
      return;
    }
    final chat = hit.chat;
    if (chat != null) {
      await Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => ChatView(chatId: chat.id, title: chat.title),
        ),
      );
      return;
    }
    final userId = hit.userId;
    if (userId == null) return;
    try {
      final chat = await TdClient.shared.query({
        '@type': 'createPrivateChat',
        'user_id': userId,
        'force': false,
      });
      final summary = TDParse.chat(chat);
      if (!mounted || summary == null) return;
      await Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => ChatView(chatId: summary.id, title: summary.title),
        ),
      );
    } catch (_) {}
  }

  Widget _hitRow(_SearchHit hit) {
    final c = context.colors;
    final thumb = _hitThumb(hit);
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: c.background,
      child: Row(
        children: [
          thumb,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hit.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (hit.timeLabel.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              hit.timeLabel,
              style: TextStyle(fontSize: 13, color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hitThumb(_SearchHit hit) {
    final image = hit.thumbnail ?? hit.photo;
    if (hit.chat != null || hit.userId != null && hit.message == null) {
      return PhotoAvatar(title: hit.title, photo: hit.photo, size: 54);
    }
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 54,
          height: 54,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TDImage(photo: image),
              if (hit.message?.video != null)
                Center(
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000).withValues(alpha: 0.50),
                      shape: BoxShape.circle,
                    ),
                    child: const AppIcon(
                      HeroAppIcons.play,
                      size: 13,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hit.tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(hit.icon, size: 24, color: hit.tint),
    );
  }

  Widget _empty(String text) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      color: c.groupedBackground,
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(fontSize: 14, color: c.textTertiary)),
    );
  }

  Widget _tabBar() {
    final c = context.colors;
    return Container(
      height: 44,
      color: c.listHeaderTint,
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [for (final tab in _SearchTab.values) _tabButton(tab)],
        ),
      ),
    );
  }

  Widget _tabButton(_SearchTab tab) {
    final c = context.colors;
    final selected = _tab == tab;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_tab == tab) return;
        setState(() => _tab = tab);
        _vm.search(_query, tab);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.brand : c.textSecondary,
                ),
                child: Text(tab.label, maxLines: 1),
              ),
              Positioned(
                bottom: 4,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: selected ? 18 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SearchTab {
  chats,
  posts,
  media,
  links,
  files,
  music,
  voice;

  String get label => switch (this) {
    _SearchTab.chats => AppStrings.t(AppStringKeys.audioSearchChatTab),
    _SearchTab.posts => telegramText(
      AppStringKeys.chatSearchMessageResultLabel,
    ).replaceAll('[', '').replaceAll(']', ''),
    _SearchTab.media => telegramText(AppStringKeys.sharedMediaPhotosAndVideos),
    _SearchTab.links => telegramText(AppStringKeys.sharedMediaLinks),
    _SearchTab.files => telegramText(AppStringKeys.topicPostContentFile),
    _SearchTab.music => AppStrings.t(AppStringKeys.profileDetailMusic),
    _SearchTab.voice => telegramText(AppStringKeys.sharedMediaVoice),
  };

  String? get filter => switch (this) {
    _SearchTab.chats => null,
    _SearchTab.posts => 'searchMessagesFilterEmpty',
    _SearchTab.media => 'searchMessagesFilterPhotoAndVideo',
    _SearchTab.links => 'searchMessagesFilterUrl',
    _SearchTab.files => 'searchMessagesFilterDocument',
    _SearchTab.music => 'searchMessagesFilterAudio',
    _SearchTab.voice => 'searchMessagesFilterVoiceNote',
  };
}

class _SearchViewModel extends ChangeNotifier {
  final Map<_SearchTab, List<_SearchHit>> _results = {
    for (final tab in _SearchTab.values) tab: <_SearchHit>[],
  };
  final Set<_SearchTab> _loading = {};
  String _currentQuery = '';
  int _runId = 0;

  List<_SearchHit> resultsFor(_SearchTab tab) => _results[tab] ?? const [];
  bool isLoading(_SearchTab tab) => _loading.contains(tab);

  void search(String q, _SearchTab tab) {
    final trimmed = q.trim();
    _currentQuery = trimmed;
    if (trimmed.isEmpty && tab == _SearchTab.chats) {
      _results[tab] = [];
      notifyListeners();
      return;
    }
    final runId = ++_runId;
    _loading.add(tab);
    notifyListeners();
    if (tab == _SearchTab.chats) {
      _runChats(trimmed, tab, runId);
    } else {
      _runMessages(trimmed, tab, runId);
    }
  }

  Future<void> _runChats(String trimmed, _SearchTab tab, int runId) async {
    try {
      final out = <_SearchHit>[];
      final seenChats = <int>{};
      final seenUsers = <int>{};

      Future<void> addChat(int id, {String? subtitle}) async {
        if (!seenChats.add(id)) return;
        try {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': id,
          });
          final s = TDParse.chat(chat);
          if (s == null) return;
          out.add(_SearchHit.chat(s, subtitle: subtitle));
          final uid = s.peerUserId;
          if (uid != null) seenUsers.add(uid);
        } catch (_) {}
      }

      final local = await TdClient.shared.query({
        '@type': 'searchChats',
        'query': trimmed,
        'limit': 50,
      });
      for (final id in (local.int64Array('chat_ids') ?? const <int>[]).take(
        50,
      )) {
        await addChat(id);
      }

      try {
        final contacts = await TdClient.shared.query({
          '@type': 'searchContacts',
          'query': trimmed,
          'limit': 50,
        });
        for (final id in contacts.int64Array('user_ids') ?? const <int>[]) {
          if (!seenUsers.add(id)) continue;
          try {
            final user = await TdClient.shared.query({
              '@type': 'getUser',
              'user_id': id,
            });
            out.add(_SearchHit.user(id, user));
          } catch (_) {}
        }
      } catch (_) {}

      try {
        final public = await TdClient.shared.query({
          '@type': 'searchPublicChats',
          'query': trimmed,
        });
        for (final id in (public.int64Array('chat_ids') ?? const <int>[]).take(
          30,
        )) {
          await addChat(
            id,
            subtitle: AppStrings.t(
              AppStringKeys.chatsSearchPublicGroupsAndChannels,
            ),
          );
        }
      } catch (_) {}

      final handle = _usernameOf(trimmed);
      if (handle != null) {
        try {
          final chat = await TdClient.shared.query({
            '@type': 'searchPublicChat',
            'username': handle,
          });
          final id = chat.int64('id');
          if (id != null) await addChat(id, subtitle: '@$handle');
        } catch (_) {}
      }

      _finish(tab, runId, trimmed, out);
    } catch (_) {
      _finish(tab, runId, trimmed, const []);
    }
  }

  Future<void> _runMessages(String trimmed, _SearchTab tab, int runId) async {
    final filter = tab.filter;
    if (filter == null) return;
    try {
      final raw = <Map<String, dynamic>>[
        ...await _searchMessagesInList(
          query: trimmed,
          filter: filter,
          chatList: {'@type': 'chatListMain'},
        ),
        ...await _searchMessagesInList(
          query: trimmed,
          filter: filter,
          chatList: {'@type': 'chatListArchive'},
        ),
      ];
      final seen = <String>{};
      final out = <_SearchHit>[];
      for (final object in raw) {
        final chatId = object.int64('chat_id');
        final message = TDParse.message(object);
        if (chatId == null || message == null) continue;
        final key = '$chatId:${message.id}';
        if (!seen.add(key)) continue;
        final source = await _sourceFor(chatId);
        out.add(_SearchHit.message(message, chatId: chatId, source: source));
      }
      out.sort((a, b) => b.date.compareTo(a.date));
      _finish(tab, runId, trimmed, out);
    } catch (_) {
      _finish(tab, runId, trimmed, const []);
    }
  }

  Future<List<Map<String, dynamic>>> _searchMessagesInList({
    required String query,
    required String filter,
    required Map<String, dynamic> chatList,
  }) async {
    try {
      final res = await TdClient.shared.query({
        '@type': 'searchMessages',
        'chat_list': chatList,
        'query': query,
        'offset_date': 0,
        'offset_chat_id': 0,
        'offset_message_id': 0,
        'limit': 60,
        'filter': {'@type': filter},
        'min_date': 0,
        'max_date': 0,
      });
      return res.objects('messages') ?? const <Map<String, dynamic>>[];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<_SearchSource> _sourceFor(int chatId) async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      return _SearchSource(
        title: chat.str('title') ?? '',
        photo: TDParse.smallPhoto(chat.obj('photo')),
      );
    } catch (_) {
      return const _SearchSource(title: '', photo: null);
    }
  }

  void _finish(_SearchTab tab, int runId, String query, List<_SearchHit> out) {
    if (runId != _runId || query != _currentQuery) return;
    _results[tab] = out;
    _loading.remove(tab);
    notifyListeners();
  }

  String? _usernameOf(String q) {
    var s = q.trim();
    final link = RegExp(
      r'(?:https?://)?(?:t\.me|telegram\.me)/(@?[A-Za-z0-9_]+)',
      caseSensitive: false,
    ).firstMatch(s);
    if (link != null) s = link.group(1)!;
    if (s.startsWith('@')) s = s.substring(1);
    return RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(s) ? s : null;
  }
}

class _SearchHit {
  _SearchHit({
    required this.title,
    required this.subtitle,
    this.timeLabel = '',
    this.date = 0,
    this.sourceTitle = '',
    this.thumbnail,
    IconData? icon,
    this.tint = const Color(0xFF12B7F5),
    this.photo,
    this.chat,
    this.userId,
    this.chatId,
    this.message,
  }) : icon = icon ?? HeroAppIcons.message.data;

  factory _SearchHit.chat(ChatSummary chat, {String? subtitle}) => _SearchHit(
    title: chat.title,
    subtitle: subtitle ?? _chatSubtitle(chat),
    photo: chat.photo,
    chat: chat,
    userId: chat.peerUserId,
  );

  factory _SearchHit.user(int id, Map<String, dynamic> user) {
    final username = user.obj('usernames')?.str('editable_username');
    return _SearchHit(
      title: TDParse.userName(user),
      subtitle: username != null && username.isNotEmpty
          ? '@$username'
          : TDParse.userStatus(user),
      photo: TDParse.smallPhoto(user.obj('profile_photo')),
      userId: id,
    );
  }

  factory _SearchHit.message(
    ChatMessage message, {
    required int chatId,
    required _SearchSource source,
  }) {
    final document = message.document;
    final music = message.music;
    final title = document?.fileName ?? music?.title ?? _messageTitle(message);
    final subtitle = _messageSubtitle(message, source.title);
    return _SearchHit(
      title: title,
      subtitle: subtitle,
      timeLabel: DateText.listLabel(message.date),
      date: message.date,
      sourceTitle: source.title,
      photo: source.photo,
      thumbnail: message.image ?? music?.cover,
      chatId: chatId,
      message: message,
      icon: _messageIcon(message),
      tint: _messageTint(message),
    );
  }

  final String title;
  final String subtitle;
  final String timeLabel;
  final int date;
  final String sourceTitle;
  final TdFileRef? photo;
  final TdFileRef? thumbnail;
  final ChatSummary? chat;
  final int? userId;
  final int? chatId;
  final ChatMessage? message;
  final IconData icon;
  final Color tint;

  static String _chatSubtitle(ChatSummary chat) {
    if (chat.kind == ChatKind.group) {
      return AppStrings.t(AppStringKeys.linkHandlerGroupLabel);
    }
    if (chat.kind == ChatKind.channel) {
      return AppStrings.t(AppStringKeys.tabChannels);
    }
    if (chat.kind == ChatKind.bot) {
      return AppStrings.t(AppStringKeys.chatsSearchBots);
    }
    return chat.lastMessage.isEmpty
        ? AppStrings.t(AppStringKeys.audioSearchChatTab)
        : chat.lastMessage;
  }

  static String _messageTitle(ChatMessage message) {
    if (message.music != null) return message.music!.title;
    if (message.voice != null) {
      return telegramText(AppStringKeys.sharedMediaVoiceMessages);
    }
    if (message.video != null) {
      final text = message.text.trim();
      return text.isEmpty ||
              text == telegramText(AppStringKeys.chatVideoPlaceholder)
          ? telegramText(AppStringKeys.chatVideoPlaceholder)
          : text;
    }
    if (message.image != null) {
      final text = message.text.trim();
      return text.isEmpty ||
              text == telegramText(AppStringKeys.composerImagePreview)
          ? telegramText(AppStringKeys.composerImagePreview)
          : text;
    }
    return message.text.trim().isEmpty
        ? telegramText(AppStringKeys.chatSearchMessageResultLabel)
        : message.text.trim();
  }

  static String _messageSubtitle(ChatMessage message, String sourceTitle) {
    final pieces = <String>[];
    final document = message.document;
    if (document != null && document.size > 0) {
      pieces.add(_fileSize(document.size));
    }
    final music = message.music;
    if (music?.performer?.isNotEmpty == true) pieces.add(music!.performer!);
    if (message.voice != null && message.voice!.duration > 0) {
      pieces.add(_duration(message.voice!.duration));
    }
    if (sourceTitle.isNotEmpty) pieces.add(sourceTitle);
    final text = message.text.trim();
    if (text.isNotEmpty &&
        document == null &&
        music == null &&
        message.voice == null &&
        text != telegramText(AppStringKeys.composerImagePreview) &&
        text != telegramText(AppStringKeys.chatVideoPlaceholder)) {
      pieces.add(text.replaceAll('\n', ' '));
    }
    return pieces.join(' · ');
  }

  static IconData _messageIcon(ChatMessage message) {
    if (message.document != null) return HeroAppIcons.solidFile.data;
    if (message.music != null) return HeroAppIcons.music.data;
    if (message.voice != null) return HeroAppIcons.microphone.data;
    if (message.linkPreview != null) return HeroAppIcons.link.data;
    if (message.video != null) return HeroAppIcons.video.data;
    if (message.image != null) return HeroAppIcons.solidImage.data;
    return HeroAppIcons.message.data;
  }

  static Color _messageTint(ChatMessage message) {
    if (message.document != null) return const Color(0xFF4AA3F0);
    if (message.music != null) return const Color(0xFFFF8A2A);
    if (message.voice != null) return const Color(0xFF28A878);
    if (message.linkPreview != null) return const Color(0xFF8E7BFF);
    if (message.video != null) return const Color(0xFF7B61FF);
    if (message.image != null) return const Color(0xFF15A7F7);
    return AppTheme.brand;
  }

  static String _fileSize(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static String _duration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _SearchSource {
  const _SearchSource({required this.title, required this.photo});
  final String title;
  final TdFileRef? photo;
}
