//
//  contacts_view.dart
//
//  The 联系人 tab: a custom root header (avatar → drawer, title, add icon) over a
//  search pill and indicator-text tabs. 好友 lists contacts; 群聊 / 频道 list chats;
//  机器人 lists bot users. Port of the Swift `ContactsView` / `ContactsViewModel`.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../profile/profile_detail_view.dart';
import '../tdlib/chat_membership.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'add_people_view.dart';

class ContactsView extends StatefulWidget {
  const ContactsView({super.key, this.onOpenDetail});

  final ValueChanged<Widget>? onOpenDetail;

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  final _vm = ContactsViewModel();
  String _meName = AppStringKeys.chatMeLabel;
  TdFileRef? _mePhoto;
  int _tab = 0; // 0 好友, 1 群聊, 2 频道, 3 机器人

  @override
  void initState() {
    super.initState();
    _vm.addListener(() {
      if (mounted) setState(() {});
    });
    _vm.onAppear();
    _loadMe();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  void _showAddMenu() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddPeopleView()));
  }

  void _openDetail(Widget detail) {
    if (widget.onOpenDetail != null) {
      widget.onOpenDetail!(detail);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => detail));
  }

  Future<void> _loadMe() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      if (!mounted) return;
      setState(() {
        final name = TDParse.userName(me);
        if (name.isNotEmpty) _meName = name;
        _mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.groupedBackground,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _searchPill(),
                _tabs(),
                switch (_tab) {
                  0 => _contactList(_vm.contacts, loading: _vm.contactsLoading),
                  1 => _chatList(_vm.groups, loading: _vm.chatsLoading),
                  2 => _chatList(_vm.channels, loading: _vm.chatsLoading),
                  _ => _contactList(_vm.bots, loading: _vm.contactsLoading),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      color: c.listHeaderTint,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.read<dc.DrawerController>().open(),
              child: PhotoAvatar(title: _meName, photo: _mePhoto, size: 34),
            ),
            const SizedBox(width: 12),
            Text(
              AppStringKeys.tabContacts.l10n(context),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showAddMenu,
              child: AppIcon(
                HeroAppIcons.userPlus,
                size: 22,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchPill() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            AppIcon(
              HeroAppIcons.magnifyingGlass,
              size: 16,
              color: c.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              AppStringKeys.topicChatSearch.l10n(context),
              style: TextStyle(fontSize: 14, color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    final c = context.colors;
    const labels = [
      AppStringKeys.contactsFriends,
      AppStringKeys.chatInfoGroupChat,
      AppStringKeys.tabChannels,
      AppStringKeys.chatsSearchBots,
    ];
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = i),
                child: SizedBox(
                  height: 50,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        labels[i].l10n(context),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: _tab == i
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: _tab == i ? 44 : 0,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.brand,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      child: Container(
        decoration: BoxDecoration(color: c.card),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  Widget _contactList(List<Contact> contacts, {required bool loading}) {
    final c = context.colors;
    if (contacts.isEmpty) {
      return _stateCard(
        loading: loading,
        emptyText: _tab == 3
            ? AppStringKeys.contactsNoBots
            : AppStringKeys.contactsNoContacts,
      );
    }
    return _card([
      for (final contact in contacts) ...[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetail(
            ProfileDetailView(
              userId: contact.id,
              name: contact.name,
              showBackButton: widget.onOpenDetail == null,
            ),
          ),
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  PhotoAvatar(
                    title: contact.name,
                    photo: contact.photo,
                    size: 44,
                    showOnlineDot: contact.isOnline,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, color: c.textPrimary),
                        ),
                        if (contact.statusText.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            contact.statusText.l10n(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (contact != contacts.last) const InsetDivider(leadingInset: 70),
      ],
    ]);
  }

  Widget _chatList(List<ChatSummary> chats, {required bool loading}) {
    final c = context.colors;
    final circleGroups = context.watch<ThemeController>().circularGroupAvatars;
    if (chats.isEmpty) {
      return _stateCard(
        loading: loading,
        emptyText: _tab == 2
            ? AppStringKeys.contactsNoChannels
            : AppStringKeys.contactsNoGroupChats,
      );
    }
    return _card([
      for (final group in chats) ...[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetail(
            ChatView(
              chatId: group.id,
              title: group.title,
              showBackButton: widget.onOpenDetail == null,
              showHeaderDivider: widget.onOpenDetail == null,
            ),
          ),
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  PhotoAvatar(
                    title: group.title,
                    photo: group.photo,
                    size: 44,
                    square: !circleGroups,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      group.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (group != chats.last) const InsetDivider(leadingInset: 70),
      ],
    ]);
  }

  Widget _stateCard({required bool loading, required String emptyText}) {
    final c = context.colors;
    return _card([
      SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else
                AppIcon(HeroAppIcons.users, size: 30, color: c.textTertiary),
              const SizedBox(height: 12),
              Text(
                (loading ? AppStringKeys.contactsLoading : emptyText).l10n(
                  context,
                ),
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class ContactsViewModel extends ChangeNotifier {
  List<Contact> contacts = [];
  List<Contact> bots = [];
  List<ChatSummary> groups = [];
  List<ChatSummary> channels = [];
  bool contactsLoading = true;
  bool chatsLoading = true;

  bool _started = false;
  final Map<int, ChatSummary> _groupIndex = {};
  final Map<int, ChatSummary> _channelIndex = {};
  final Map<int, Contact> _botIndex = {};
  final Set<int> _resolvingBots = {};
  final Set<String> _loadingChatLists = {};
  final Set<String> _exhaustedChatLists = {};
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _disposed = false;
  static const _pageSize = 100;
  static const _prefetchPasses = 8;

  void onAppear() {
    if (_started) return;
    _started = true;
    _loadContacts();
    _subscribe();
    _prefetchChats();
  }

  Future<void> _loadContacts() async {
    contactsLoading = true;
    _safeNotify();
    try {
      final result = await TdClient.shared.query({'@type': 'getContacts'});
      if (_disposed) return;
      final ids = result.int64Array('user_ids') ?? const <int>[];
      final loaded = <Contact>[];
      for (final id in ids.take(300)) {
        if (_disposed) return;
        try {
          final user = await TdClient.shared.query({
            '@type': 'getUser',
            'user_id': id,
          });
          if (_disposed) return;
          final contact = _contactFromUser(id, user);
          if (_isBotUser(user)) {
            _botIndex[id] = contact;
          } else {
            loaded.add(contact);
          }
        } catch (_) {}
      }
      loaded.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      contacts = loaded;
      _sortBots();
    } catch (_) {
    } finally {
      contactsLoading = false;
      _safeNotify();
    }
  }

  Contact _contactFromUser(int id, Map<String, dynamic> user) => Contact(
    id: id,
    name: TDParse.userName(user),
    username: user.obj('usernames')?.str('editable_username'),
    statusText: _isBotUser(user)
        ? AppStringKeys.chatsSearchBots
        : TDParse.userStatus(user),
    photo: TDParse.smallPhoto(user.obj('profile_photo')),
    isOnline: TDParse.isUserOnline(user),
  );

  bool _isBotUser(Map<String, dynamic> user) =>
      user.obj('type')?.type == 'userTypeBot' ||
      user.obj('type')?.type == 'userTypeRegularBot' ||
      user.boolean('is_bot') == true;

  String _chatListKey(Map<String, dynamic> list) =>
      switch (list.type ?? list['@type']) {
        'chatListArchive' => 'archive',
        'chatListFolder' => 'folder:${list.integer('chat_folder_id') ?? 0}',
        _ => 'main',
      };

  Future<bool> _loadChatList(Map<String, dynamic> list, int limit) async {
    final key = _chatListKey(list);
    if (_loadingChatLists.contains(key) || _exhaustedChatLists.contains(key)) {
      return false;
    }
    _loadingChatLists.add(key);
    try {
      await TdClient.shared.query({
        '@type': 'loadChats',
        'chat_list': list,
        'limit': limit,
      });
      return true;
    } catch (error) {
      if (error is TdError && error.code == 404) {
        _exhaustedChatLists.add(key);
      }
      return false;
    } finally {
      _loadingChatLists.remove(key);
    }
  }

  Future<void> _hydrateChatList(Map<String, dynamic> list, int limit) async {
    try {
      final res = await TdClient.shared.query({
        '@type': 'getChats',
        'chat_list': list,
        'limit': limit,
      });
      final ids = res.int64Array('chat_ids') ?? const <int>[];
      for (final id in ids) {
        if (_disposed) return;
        try {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': id,
          });
          if (_disposed) return;
          await _ingestChat(chat);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _prefetchChats() {
    Future<void>(() async {
      chatsLoading = true;
      _safeNotify();
      const lists = [
        {'@type': 'chatListMain'},
        {'@type': 'chatListArchive'},
      ];
      for (final list in lists) {
        await _prefetchChatList(list);
      }
      chatsLoading = false;
      _safeNotify();
    });
  }

  Future<void> _prefetchChatList(Map<String, dynamic> list) async {
    final key = _chatListKey(list);
    await _hydrateChatList(list, _pageSize);
    var passes = 0;
    while (!_disposed &&
        !_exhaustedChatLists.contains(key) &&
        passes < _prefetchPasses) {
      passes += 1;
      final loaded = await _loadChatList(list, _pageSize);
      await _hydrateChatList(list, _pageSize);
      if (_disposed || !loaded) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  void _subscribe() {
    _subscription = TdClient.shared.subscribe().listen((update) {
      if (_disposed) return;
      switch (update.type) {
        case 'updateNewChat':
          final chat = update.obj('chat');
          if (chat != null) unawaited(_ingestChat(chat));
        case 'updateChatAddedToList':
          final id = update.int64('chat_id');
          if (id != null) _ensureChatLoaded(id);
        case 'updateChatPosition':
          final id = update.int64('chat_id');
          if (id != null) _ensureChatLoaded(id);
        case 'updateChatRemovedFromList':
          final id = update.int64('chat_id');
          if (id != null) _ensureChatLoaded(id);
        case 'updateChatTitle':
          final id = update.int64('chat_id');
          final existing = id != null ? _chatById(id) : null;
          if (existing != null) {
            existing.title = update.str('title') ?? existing.title;
            _ingest(existing);
          }
        case 'updateChatPhoto':
          final id = update.int64('chat_id');
          final existing = id != null ? _chatById(id) : null;
          if (existing != null) {
            existing.photo = TDParse.smallPhoto(update.obj('photo'));
            _ingest(existing);
          }
      }
    });
  }

  ChatSummary? _chatById(int id) => _groupIndex[id] ?? _channelIndex[id];

  void _ensureChatLoaded(int id) {
    TdClient.shared
        .query({'@type': 'getChat', 'chat_id': id})
        .then((chat) {
          if (!_disposed) unawaited(_ingestChat(chat));
        })
        .catchError((_) {});
  }

  Future<void> _ingestChat(Map<String, dynamic> chat) async {
    final summary = TDParse.chat(chat);
    if (summary == null) return;
    final type = chat.obj('type');
    if (summary.kind == ChatKind.privateChat) {
      final userId = type?.int64('user_id');
      if (userId != null) _resolveBot(userId);
      return;
    }
    if (!await isJoinedGroupOrChannelChat(summary.id, chat: chat)) {
      _removeChat(summary.id);
      return;
    }
    _ingest(summary);
  }

  void _removeChat(int id) {
    var changed = false;
    changed = _groupIndex.remove(id) != null || changed;
    changed = _channelIndex.remove(id) != null || changed;
    if (!changed) return;
    _refreshChatLists();
    _safeNotify();
  }

  void _ingest(ChatSummary summary) {
    switch (summary.kind) {
      case ChatKind.group:
        _groupIndex[summary.id] = summary;
      case ChatKind.channel:
        _channelIndex[summary.id] = summary;
      default:
        return;
    }
    _refreshChatLists();
    _safeNotify();
  }

  void _refreshChatLists() {
    groups = _groupIndex.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    channels = _channelIndex.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  void _resolveBot(int userId) {
    if (_disposed) return;
    if (_botIndex.containsKey(userId) || _resolvingBots.contains(userId)) {
      return;
    }
    _resolvingBots.add(userId);
    TdClient.shared
        .query({'@type': 'getUser', 'user_id': userId})
        .then((user) {
          if (_disposed) return;
          _resolvingBots.remove(userId);
          if (!_isBotUser(user)) return;
          _botIndex[userId] = _contactFromUser(userId, user);
          _sortBots();
          _safeNotify();
        })
        .catchError((_) {
          if (_disposed) return;
          _resolvingBots.remove(userId);
        });
  }

  void _sortBots() {
    bots = _botIndex.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
