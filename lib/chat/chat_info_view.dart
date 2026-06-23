//
//  chat_info_view.dart
//
//  Chat info / settings page for a private chat or group (reached by tapping the
//  conversation header's menu). Grouped white cards on the gray canvas: identity,
//  member grid (groups), quick rows, pin/mute toggles, destructive actions.
//  Port of the Swift `ChatInfoView` / `ChatInfoViewModel`.
//

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../components/icon_grid.dart';
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../profile/qr_code_view.dart';
import 'add_members_view.dart';
import 'chat_members_view.dart';
import 'chat_search_view.dart';
import 'shared_media_view.dart';

class ChatMember {
  ChatMember(this.id, this.name, this.photo);
  final int id;
  final String name;
  final TdFileRef? photo;
}

class ChatInfoView extends StatefulWidget {
  const ChatInfoView({super.key, required this.chatId, required this.title});
  final int chatId;
  final String title;

  @override
  State<ChatInfoView> createState() => _ChatInfoViewState();
}

class _ChatInfoViewState extends State<ChatInfoView> {
  late final ChatInfoViewModel _vm = ChatInfoViewModel(
    chatId: widget.chatId,
    title: widget.title,
  );

  @override
  void initState() {
    super.initState();
    _vm.addListener(() {
      if (mounted) setState(() {});
    });
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  void _openMembers() {
    if (!_vm.isGroup) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatMembersView(chatId: widget.chatId, title: _vm.title),
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
          NavHeader(title: '聊天信息', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              children: [
                _topCard(),
                if (_vm.isGroup) ...[
                  const SizedBox(height: 14),
                  _memberGridCard(),
                ],
                const SizedBox(height: 14),
                _rowsCard(),
                const SizedBox(height: 14),
                _togglesCard(),
                const SizedBox(height: 14),
                _destructiveCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration get _card => BoxDecoration(
    color: context.colors.card,
    borderRadius: BorderRadius.circular(12),
  );

  void _openQR() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            QRCodeView(name: _vm.title, chatId: widget.chatId, isGroup: true),
      ),
    );
  }

  /// QQ-style identity row: avatar + name/subtitle inline & left-aligned, with a
  /// QR icon + chevron on the right (groups → tap opens the 群二维码 page).
  Widget _topCard() {
    final c = context.colors;
    return Container(
      decoration: _card,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _vm.isGroup ? _openQR : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          child: Row(
            children: [
              PhotoAvatar(
                title: _vm.title,
                photo: _vm.photo,
                size: 56,
                square: _vm.isGroup,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _vm.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _subtitle(),
                  ],
                ),
              ),
              if (_vm.isGroup) ...[
                const SizedBox(width: 8),
                Icon(sfIcon('qrcode'), size: 22, color: c.textSecondary),
                const SizedBox(width: 6),
                Icon(sfIcon('chevron.right'), size: 15, color: c.textTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _subtitle() {
    final c = context.colors;
    if (!_vm.isGroup) {
      final sub = (_vm.username?.isNotEmpty ?? false) ? '@${_vm.username}' : '';
      return sub.isEmpty
          ? const SizedBox.shrink()
          : Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            );
    }
    return Row(
      children: [
        Flexible(
          child: Text(
            _vm.groupNumber.isEmpty ? '群聊' : '群号：${_vm.groupNumber}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ),
        const SizedBox(width: 8),
        if (_vm.isPublic && (_vm.username?.isNotEmpty ?? false))
          Flexible(
            child: Text(
              '@${_vm.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppTheme.brand),
            ),
          )
        else
          _lockBadge('不允许被搜索'),
      ],
    );
  }

  Widget _lockBadge(String text) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sfIcon('lock.fill'), size: 10, color: c.textTertiary),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 11, color: c.textTertiary)),
        ],
      ),
    );
  }

  Widget _memberGridCard() {
    final c = context.colors;
    // Always a 5×3 (15-cell) grid: action tiles take the last 1–2 cells.
    final actionTiles = (_vm.canInvite ? 1 : 0) + (_vm.canRemove ? 1 : 0);
    final memberSlots = (15 - actionTiles).clamp(0, 15);
    final shown = _vm.members.take(memberSlots).toList();
    return Container(
      decoration: _card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openMembers,
            child: Row(
              children: [
                Text(
                  '群成员',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
                const Spacer(),
                if (_vm.memberCount > 0)
                  Text(
                    '${_vm.memberCount}人',
                    style: TextStyle(fontSize: 14, color: c.textSecondary),
                  ),
                const SizedBox(width: 6),
                Icon(sfIcon('chevron.right'), size: 14, color: c.textTertiary),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IconGrid(
            perRow: 5,
            children: [
              for (final m in shown)
                GestureDetector(
                  onTap: _openMembers,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhotoAvatar(title: m.name, photo: m.photo, size: 48),
                      const SizedBox(height: 6),
                      Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textPrimary),
                      ),
                    ],
                  ),
                ),
              if (_vm.canInvite)
                _actionTile(
                  Icons.add,
                  '邀请',
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddMembersView(chatId: widget.chatId),
                    ),
                  ),
                ),
              if (_vm.canRemove) _actionTile(Icons.remove, '移除', _openMembers),
            ],
          ),
        ],
      ),
    );
  }

  /// Circular +/− action tile sized like a member avatar (邀请 / 移除).
  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.searchFill,
            ),
            child: Icon(icon, size: 22, color: c.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _rowsCard() {
    return Container(
      decoration: _card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _infoRow(
            'magnifyingglass',
            AppTheme.brand,
            '查找聊天记录',
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ChatSearchView(chatId: widget.chatId, title: widget.title),
              ),
            ),
          ),
          const InsetDivider(leadingInset: 52),
          _infoRow(
            _vm.isGroup ? 'photo.fill' : 'folder.fill',
            const Color(0xFF16B0A0),
            _vm.isGroup ? '群相册' : '文件',
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    SharedMediaView(chatId: widget.chatId, title: widget.title),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String icon, Color color, String title, VoidCallback onTap) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(sfIcon(icon), size: 14, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(title, style: TextStyle(fontSize: 15, color: c.textPrimary)),
              const Spacer(),
              Icon(sfIcon('chevron.right'), size: 14, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _togglesCard() {
    return Container(
      decoration: _card,
      child: Column(
        children: [
          _toggleRow('置顶聊天', _vm.isPinned, _vm.setPinned),
          const InsetDivider(leadingInset: 14),
          _toggleRow('消息免打扰', _vm.isMuted, _vm.setMuted),
        ],
      ),
    );
  }

  Widget _toggleRow(String title, bool value, ValueChanged<bool> onChanged) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Text(title, style: TextStyle(fontSize: 15, color: c.textPrimary)),
            const Spacer(),
            CupertinoSwitch(
              value: value,
              activeTrackColor: AppTheme.brand,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _destructiveCard() {
    return Container(
      decoration: _card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _destructiveRow('清空聊天记录', _vm.clearHistory),
          // Only a confirmed member can quit — hide 退出 for non-joined groups.
          if (_vm.isGroup && _vm.isMember) ...[
            const InsetDivider(leadingInset: 0),
            _destructiveRow('退出群聊', () {
              _vm.leaveChat();
              Navigator.of(context).pop();
            }),
          ],
        ],
      ),
    );
  }

  Widget _destructiveRow(String title, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Center(
          child: Text(
            title,
            style: TextStyle(fontSize: 15, color: AppTheme.tagRed),
          ),
        ),
      ),
    );
  }
}

class ChatInfoViewModel extends ChangeNotifier {
  ChatInfoViewModel({required this.chatId, required this.title});

  final int chatId;
  String title;
  TdFileRef? photo;
  bool isGroup = false;
  int memberCount = 0;
  String groupNumber = ''; // supergroup / basic-group id, shown as 群号
  String? username; // public @username (supergroups only)
  bool isPublic = false; // has a public username → searchable
  bool isPinned = false;
  bool isMuted = false;
  List<ChatMember> members = [];
  bool canInvite = false;
  bool canRemove = false;
  bool isMember = false; // confirmed member → may quit; false hides 退出
  bool _loaded = false;

  void load() {
    if (_loaded) return;
    _loaded = true;
    _loadAsync();
  }

  Future<void> _loadAsync() async {
    Map<String, dynamic> chat;
    try {
      chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': chatId,
      });
    } catch (_) {
      _loaded = false;
      return;
    }
    final t = chat.str('title');
    if (t != null && t.isNotEmpty) title = t;
    photo = TDParse.smallPhoto(chat.obj('photo'));
    final kind = TDParse.chatKind(chat);
    isGroup = kind == ChatKind.group || kind == ChatKind.channel;
    isMuted = (chat.obj('notification_settings')?.integer('mute_for') ?? 0) > 0;
    final type = chat.obj('type');
    if (type?.type == 'chatTypeSupergroup') {
      groupNumber = type?.int64('supergroup_id')?.toString() ?? '';
    } else if (type?.type == 'chatTypeBasicGroup') {
      groupNumber = type?.int64('basic_group_id')?.toString() ?? '';
    }
    for (final pos
        in chat.objects('positions') ?? const <Map<String, dynamic>>[]) {
      if (pos.obj('list')?.type == 'chatListMain') {
        isPinned = pos.boolean('is_pinned') ?? false;
      }
    }
    notifyListeners();
    if (isGroup) {
      await _loadGroupMeta(chat);
      await _loadSelfPermissions(chat);
    }
    await _loadMembers(chat);
  }

  /// Public @username (supergroups) → determines searchability + the 群号 line's
  /// trailing chip (@handle when public, 不允许被搜索 lock when private).
  Future<void> _loadGroupMeta(Map<String, dynamic> chat) async {
    final type = chat.obj('type');
    try {
      if (type?.type == 'chatTypeSupergroup') {
        final sgid = type?.int64('supergroup_id');
        final sg = await TdClient.shared.query({
          '@type': 'getSupergroup',
          'supergroup_id': sgid,
        });
        final uname = sg.obj('usernames')?.str('editable_username') ?? '';
        username = uname.isEmpty ? null : uname;
        isPublic = uname.isNotEmpty;
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Whether the current user can invite / remove members — gates the 邀请/移除
  /// action tiles. Creator = both; admin = per rights; member = default invite.
  Future<void> _loadSelfPermissions(Map<String, dynamic> chat) async {
    final defaultInvite =
        chat.obj('permissions')?.boolean('can_invite_users') ?? false;
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      final uid = me.int64('id');
      final member = await TdClient.shared.query({
        '@type': 'getChatMember',
        'chat_id': chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': uid},
      });
      final status = member.obj('status');
      final st = status?.type;
      isMember =
          st == 'chatMemberStatusCreator' ||
          st == 'chatMemberStatusAdministrator' ||
          st == 'chatMemberStatusMember' ||
          (st == 'chatMemberStatusRestricted' &&
              (status?.boolean('is_member') ?? false));
      switch (st) {
        case 'chatMemberStatusCreator':
          canInvite = true;
          canRemove = true;
        case 'chatMemberStatusAdministrator':
          final rights = status?.obj('rights');
          canInvite = rights?.boolean('can_invite_users') ?? false;
          canRemove = rights?.boolean('can_restrict_members') ?? false;
        default:
          canInvite = defaultInvite;
          canRemove = false;
      }
    } catch (_) {
      canInvite = defaultInvite;
      canRemove = false;
      isMember = false;
    }
    notifyListeners();
  }

  Future<void> _loadMembers(Map<String, dynamic> chat) async {
    final type = chat.obj('type');
    try {
      if (type?.type == 'chatTypeBasicGroup') {
        final gid = type?.int64('basic_group_id');
        if (gid == null) return;
        final full = await TdClient.shared.query({
          '@type': 'getBasicGroupFullInfo',
          'basic_group_id': gid,
        });
        final raw = full.objects('members') ?? const <Map<String, dynamic>>[];
        memberCount = raw.length;
        await _resolveMembers(raw);
      } else if (type?.type == 'chatTypeSupergroup') {
        final sgid = type?.int64('supergroup_id');
        if (sgid == null) return;
        final result = await TdClient.shared.query({
          '@type': 'getSupergroupMembers',
          'supergroup_id': sgid,
          'filter': {'@type': 'supergroupMembersFilterRecent'},
          'offset': 0,
          'limit': 30,
        });
        final raw = result.objects('members') ?? const <Map<String, dynamic>>[];
        memberCount =
            result.integer('member_count') ??
            result.integer('total_count') ??
            raw.length;
        await _resolveMembers(raw);
      }
    } catch (_) {}
  }

  Future<void> _resolveMembers(List<Map<String, dynamic>> raw) async {
    final result = <ChatMember>[];
    for (final entry in raw.take(20)) {
      final memberId = entry.obj('member_id');
      if (memberId?.type != 'messageSenderUser') continue;
      final uid = memberId?.int64('user_id');
      if (uid == null) continue;
      try {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': uid,
        });
        result.add(
          ChatMember(
            uid,
            TDParse.userName(user),
            TDParse.smallPhoto(user.obj('profile_photo')),
          ),
        );
        // Stream after each resolve so the grid fills progressively and a slow
        // or failing lookup can't keep the whole list empty.
        members = List.of(result);
        notifyListeners();
      } catch (_) {}
    }
  }

  void setPinned(bool value) {
    isPinned = value;
    notifyListeners();
    TdClient.shared.send({
      '@type': 'toggleChatIsPinned',
      'chat_list': {'@type': 'chatListMain'},
      'chat_id': chatId,
      'is_pinned': value,
    });
  }

  void setMuted(bool value) {
    isMuted = value;
    notifyListeners();
    TdClient.shared.send({
      '@type': 'setChatNotificationSettings',
      'chat_id': chatId,
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_mute_for': false,
        'mute_for': value ? 2147483647 : 0,
      },
    });
  }

  void clearHistory() {
    TdClient.shared.send({
      '@type': 'deleteChatHistory',
      'chat_id': chatId,
      'remove_from_chat_list': false,
      'revoke': false,
    });
  }

  void leaveChat() {
    TdClient.shared.send({'@type': 'leaveChat', 'chat_id': chatId});
  }
}
