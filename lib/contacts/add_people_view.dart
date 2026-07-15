//
//  add_people_view.dart
//
//  添加 — custom "add" page reached from the 联系人 top-right +. A 找人 / 找群
//  segmented toggle drives a single search field (people: searchContacts +
//  searchPublicChat; groups: searchPublicChats), and an options grid (扫一扫 /
//  创建群聊 / 创建频道) shows when the query is empty.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/icon_grid.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../profile/profile_detail_view.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'create_group_view.dart';

class _ChatHit {
  _ChatHit(this.id, this.title, this.photo, this.subtitle, this.square);
  final int id;
  final String title;
  final TdFileRef? photo;
  final String subtitle;
  final bool square;
}

class AddPeopleView extends StatefulWidget {
  const AddPeopleView({super.key});

  @override
  State<AddPeopleView> createState() => _AddPeopleViewState();
}

class _AddPeopleViewState extends State<AddPeopleView> {
  final TdClient _client = TdClient.shared;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _mode = 0; // 0 找人, 1 找群
  String _query = '';
  bool _loading = false;
  List<Contact> _people = [];
  List<_ChatHit> _groups = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setMode(int m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _people = [];
      _groups = [];
    });
    if (_query.trim().isNotEmpty) _run(_query.trim());
  }

  void _onChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _people = [];
        _groups = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    if (_mode == 0) {
      await _searchPeople(q);
    } else {
      await _searchGroups(q);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _searchPeople(String q) async {
    final byId = <int, Contact>{};
    try {
      final res = await _client.query({
        '@type': 'searchContacts',
        'query': q,
        'limit': 30,
      });
      for (final id in res.int64Array('user_ids') ?? const <int>[]) {
        final c = await _contact(id);
        if (c != null) byId[id] = c;
      }
    } catch (_) {}
    // searchContacts only covers saved contacts; if the input is an exact public
    // username (or t.me link), resolve it so any user shows up as a candidate.
    final handle = _usernameOf(q);
    if (handle != null) {
      try {
        final chat = await _client.query({
          '@type': 'searchPublicChat',
          'username': handle,
        });
        final uid = chat.obj('type')?.int64('user_id');
        if (uid != null && !byId.containsKey(uid)) {
          final c = await _contact(uid);
          if (c != null) byId[uid] = c;
        }
      } catch (_) {}
    }
    if (q != _query.trim() || _mode != 0) return;
    _people = byId.values.toList();
  }

  Future<void> _searchGroups(String q) async {
    final hits = <_ChatHit>[];
    try {
      final res = await _client.query({
        '@type': 'searchPublicChats',
        'query': q,
      });
      for (final id in (res.int64Array('chat_ids') ?? const <int>[]).take(30)) {
        try {
          final chat = await _client.query({'@type': 'getChat', 'chat_id': id});
          final kind = TDParse.chatKind(chat);
          if (kind != ChatKind.group && kind != ChatKind.channel) continue;
          hits.add(
            _ChatHit(
              id,
              chat.str('title') ?? '—',
              TDParse.smallPhoto(chat.obj('photo')),
              kind == ChatKind.channel
                  ? AppStrings.t(AppStringKeys.tabChannels)
                  : AppStrings.t(AppStringKeys.linkHandlerGroupLabel),
              true,
            ),
          );
        } catch (_) {}
      }
    } catch (_) {}
    // searchPublicChats won't always surface an exact, lesser-known channel; if
    // the input is a valid public username/link, resolve it directly.
    final handle = _usernameOf(q);
    if (handle != null) {
      try {
        final chat = await _client.query({
          '@type': 'searchPublicChat',
          'username': handle,
        });
        final id = chat.int64('id');
        final kind = TDParse.chatKind(chat);
        if (id != null &&
            (kind == ChatKind.group || kind == ChatKind.channel) &&
            !hits.any((h) => h.id == id)) {
          hits.add(
            _ChatHit(
              id,
              chat.str('title') ?? '—',
              TDParse.smallPhoto(chat.obj('photo')),
              kind == ChatKind.channel
                  ? AppStrings.t(AppStringKeys.tabChannels)
                  : AppStrings.t(AppStringKeys.linkHandlerGroupLabel),
              true,
            ),
          );
        }
      } catch (_) {}
    }
    if (q != _query.trim() || _mode != 1) return;
    _groups = hits;
  }

  /// Extracts a Telegram public username from raw input — bare handle, `@handle`,
  /// or a t.me / telegram.me link — or null if it isn't a valid username shape.
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

  Future<Contact?> _contact(int id) async {
    try {
      final user = await _client.query({'@type': 'getUser', 'user_id': id});
      return Contact(
        id: id,
        name: TDParse.userName(user),
        username: user.obj('usernames')?.str('editable_username'),
        statusText: TDParse.userStatus(user),
        photo: TDParse.smallPhoto(user.obj('profile_photo')),
      );
    } catch (_) {
      return null;
    }
  }

  // MARK: - Actions

  void _openUser(Contact u) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProfileDetailView(userId: u.id, name: u.name),
    ),
  );

  void _openChat(_ChatHit h) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatView(chatId: h.id, title: h.title),
    ),
  );

  void _createGroup() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const CreateGroupView()));

  Future<void> _createChannel() async {
    final title = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStrings.t(AppStringKeys.chatListCreateChannel),
          initial: '',
          hint: AppStrings.t(AppStringKeys.chatListChannelName),
        ),
      ),
    );
    if (title == null || title.isEmpty) return;
    try {
      final chat = await _client.query({
        '@type': 'createNewSupergroupChat',
        'title': title,
        'is_channel': true,
        'description': '',
      });
      final id = chat.int64('id') ?? chat.int64('chat_id');
      if (!mounted || id == null) return;
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatView(chatId: id, title: title),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatListCreateChannelFailed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _header(),
          _searchBar(),
          Expanded(child: _query.trim().isEmpty ? _optionsGrid() : _results()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: AppIcon(
                    HeroAppIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            _segmented(),
          ],
        ),
      ),
    );
  }

  Widget _segmented() {
    final c = context.colors;
    Widget seg(String label, int m) {
      final on = _mode == m;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setMode(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: on ? c.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: on ? c.card : c.textSecondary,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(AppStrings.t(AppStringKeys.addPeopleFindPeople), 0),
          seg(AppStrings.t(AppStringKeys.addPeopleFindGroups), 1),
        ],
      ),
    );
  }

  Widget _searchBar() {
    final c = context.colors;
    return Container(
      color: c.navBar,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
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
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 15, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: _mode == 0
                      ? AppStrings.t(
                          AppStringKeys.addPeopleUsernameOrPhonePlaceholder,
                        )
                      : AppStrings.t(
                          AppStringKeys.addPeopleGroupNameOrLinkPlaceholder,
                        ),
                  hintStyle: TextStyle(color: c.textTertiary),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                onChanged: _onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionsGrid() {
    final options = <(IconData, String, VoidCallback)>[
      (
        HeroAppIcons.users.data,
        AppStrings.t(AppStringKeys.chatListCreateGroup),
        _createGroup,
      ),
      (
        HeroAppIcons.towerBroadcast.data,
        AppStrings.t(AppStringKeys.chatListCreateChannel),
        _createChannel,
      ),
    ];
    final c = context.colors;
    return SingleChildScrollView(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 14, 12, 0),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: IconGrid(
          perRow: 4,
          runSpacing: 16,
          children: [
            for (final o in options)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: o.$3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.brand.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(o.$1, size: 22, color: AppTheme.brand),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      o.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: c.textPrimary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    final c = context.colors;
    if (_loading && _people.isEmpty && _groups.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    final rows = _mode == 0
        ? _people.map(_personRow).toList()
        : _groups.map(_groupRow).toList();
    if (rows.isEmpty) {
      return Center(
        child: Text(
          _mode == 0
              ? AppStrings.t(AppStringKeys.addPeopleNoUsersFound)
              : AppStrings.t(AppStringKeys.addPeopleNoGroupsOrChannelsFound),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return ListView(padding: EdgeInsets.zero, children: rows);
  }

  Widget _personRow(Contact u) {
    return _row(
      u.name,
      (u.username ?? '').isNotEmpty ? '@${u.username}' : u.statusText,
      PhotoAvatar(title: u.name, photo: u.photo, size: 44),
      () => _openUser(u),
    );
  }

  Widget _groupRow(_ChatHit h) {
    final circleGroups = context.watch<ThemeController>().circularGroupAvatars;
    return _row(
      h.title,
      h.subtitle,
      PhotoAvatar(
        title: h.title,
        photo: h.photo,
        size: 44,
        square: h.square && !circleGroups,
      ),
      () => _openChat(h),
    );
  }

  Widget _row(
    String title,
    String subtitle,
    Widget avatar,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.background,
          border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            AppIcon(HeroAppIcons.chevronRight, size: 14, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
