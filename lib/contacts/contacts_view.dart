//
//  contacts_view.dart
//
//  The 联系人 tab: a custom root header (avatar → drawer, title, add icon) over a
//  search pill and indicator-text tabs. 好友 lists contacts; 群聊 / 频道 list chats;
//  机器人 lists bot users. Port of the Swift `ContactsView` / `ContactsViewModel`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_view.dart';
import '../components/drawer_controller.dart' as dc;
import 'add_people_view.dart';
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../profile/profile_detail_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class ContactsView extends StatefulWidget {
  const ContactsView({super.key});

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  final _vm = ContactsViewModel();
  String _meName = '我';
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
                  0 => _contactList(_vm.contacts),
                  1 => _chatList(_vm.groups),
                  2 => _chatList(_vm.channels),
                  _ => _contactList(_vm.bots),
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
              '联系人',
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
              child: Icon(
                sfIcon('person.badge.plus'),
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
            Icon(sfIcon('magnifyingglass'), size: 16, color: c.textTertiary),
            const SizedBox(width: 6),
            Text('搜索', style: TextStyle(fontSize: 14, color: c.textTertiary)),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    final c = context.colors;
    const labels = ['好友', '群聊', '频道', '机器人'];
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
                        labels[i],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: _tab == i
                              ? FontWeight.w700
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
        decoration: BoxDecoration(
          color: c.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  Widget _contactList(List<Contact> contacts) {
    final c = context.colors;
    return _card([
      for (final contact in contacts) ...[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ProfileDetailView(userId: contact.id, name: contact.name),
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
                            contact.statusText,
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

  Widget _chatList(List<ChatSummary> chats) {
    final c = context.colors;
    final circleGroups = context.watch<ThemeController>().circularGroupAvatars;
    return _card([
      for (final group in chats) ...[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatView(chatId: group.id, title: group.title),
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
}

class ContactsViewModel extends ChangeNotifier {
  List<Contact> contacts = [];
  List<Contact> bots = [];
  List<ChatSummary> groups = [];
  List<ChatSummary> channels = [];

  bool _started = false;
  final Map<int, ChatSummary> _groupIndex = {};
  final Map<int, ChatSummary> _channelIndex = {};
  final Map<int, Contact> _botIndex = {};
  final Set<int> _resolvingBots = {};
  final Set<String> _loadingChatLists = {};
  final Set<String> _exhaustedChatLists = {};
  static const _pageSize = 100;

  void onAppear() {
    if (_started) return;
    _started = true;
    _loadContacts();
    _subscribe();
    _prefetchMainChats();
  }

  Future<void> _loadContacts() async {
    try {
      final result = await TdClient.shared.query({'@type': 'getContacts'});
      final ids = result.int64Array('user_ids') ?? const <int>[];
      final loaded = <Contact>[];
      for (final id in ids.take(300)) {
        try {
          final user = await TdClient.shared.query({
            '@type': 'getUser',
            'user_id': id,
          });
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
      notifyListeners();
    } catch (_) {}
  }

  Contact _contactFromUser(int id, Map<String, dynamic> user) => Contact(
    id: id,
    name: TDParse.userName(user),
    username: user.obj('usernames')?.str('editable_username'),
    statusText: _isBotUser(user) ? '机器人' : TDParse.userStatus(user),
    photo: TDParse.smallPhoto(user.obj('profile_photo')),
    isOnline: TDParse.isUserOnline(user),
  );

  bool _isBotUser(Map<String, dynamic> user) =>
      user.obj('type')?.type == 'userTypeBot' ||
      user.obj('type')?.type == 'userTypeRegularBot' ||
      user.boolean('is_bot') == true;

  Future<bool> _loadChatList(Map<String, dynamic> list, int limit) async {
    final key = list.type ?? list['@type'] as String? ?? 'main';
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

  void _prefetchMainChats() {
    Future<void>(() async {
      while (!_exhaustedChatLists.contains('chatListMain')) {
        final loaded = await _loadChatList({
          '@type': 'chatListMain',
        }, _pageSize);
        if (!loaded && !_loadingChatLists.contains('chatListMain')) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  void _subscribe() {
    TdClient.shared.subscribe().listen((update) {
      switch (update.type) {
        case 'updateNewChat':
          final chat = update.obj('chat');
          if (chat != null) _ingestChat(chat);
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

  void _ingestChat(Map<String, dynamic> chat) {
    final summary = TDParse.chat(chat);
    if (summary == null) return;
    final type = chat.obj('type');
    if (summary.kind == ChatKind.privateChat) {
      final userId = type?.int64('user_id');
      if (userId != null) _resolveBot(userId);
      return;
    }
    _ingest(summary);
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
    groups = _groupIndex.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    channels = _channelIndex.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    notifyListeners();
  }

  void _resolveBot(int userId) {
    if (_botIndex.containsKey(userId) || _resolvingBots.contains(userId)) {
      return;
    }
    _resolvingBots.add(userId);
    TdClient.shared
        .query({'@type': 'getUser', 'user_id': userId})
        .then((user) {
          _resolvingBots.remove(userId);
          if (!_isBotUser(user)) return;
          _botIndex[userId] = _contactFromUser(userId, user);
          _sortBots();
          notifyListeners();
        })
        .catchError((_) {
          _resolvingBots.remove(userId);
        });
  }

  void _sortBots() {
    bots = _botIndex.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
