//
//  chat_members_view.dart
//
//  群成员 — full member list for a group/channel, reached from Chat Info. Loads
//  members via TDLib (getSupergroupMembers / getBasicGroupFullInfo), resolves
//  each user's name/photo/role, and lists them with role tags + online dots.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'chat_administrator_edit_view.dart';

enum ChatMembersMode { members, administrators }

class GroupMember {
  GroupMember({
    required this.id,
    required this.name,
    this.photo,
    this.role,
    this.title,
    this.status = '',
    this.isOnline = false,
    this.rawStatus,
  });
  final int id;
  final String name;
  final TdFileRef? photo;
  final MemberRole? role;
  final String? title;
  final String status;
  final bool isOnline;
  final Map<String, dynamic>? rawStatus;

  GroupMember copyWith({
    String? title,
    bool clearTitle = false,
    MemberRole? role,
    Map<String, dynamic>? rawStatus,
  }) => GroupMember(
    id: id,
    name: name,
    photo: photo,
    role: role ?? this.role,
    title: clearTitle ? null : title ?? this.title,
    status: status,
    isOnline: isOnline,
    rawStatus: rawStatus ?? this.rawStatus,
  );
}

class ChatMembersView extends StatefulWidget {
  const ChatMembersView({
    super.key,
    required this.chatId,
    required this.title,
    this.mode = ChatMembersMode.members,
  });
  final int chatId;
  final String title;
  final ChatMembersMode mode;

  @override
  State<ChatMembersView> createState() => _ChatMembersViewState();
}

class _ChatMembersViewState extends State<ChatMembersView> {
  List<GroupMember> _members = [];
  int _total = 0;
  bool _loading = true;
  bool _canRemove = false;
  bool _canPromote = false;
  bool _canManageTags = false;
  bool _isCreator = false;
  int? _openRowId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': widget.chatId,
      });
      final type = chat.obj('type');
      await _loadSelfPermissions();
      List<Map<String, dynamic>> raw = [];
      if (type?.type == 'chatTypeBasicGroup') {
        final gid = type?.int64('basic_group_id');
        if (gid != null) {
          final full = await TdClient.shared.query({
            '@type': 'getBasicGroupFullInfo',
            'basic_group_id': gid,
          });
          raw = full.objects('members') ?? const <Map<String, dynamic>>[];
          if (widget.mode == ChatMembersMode.administrators) {
            raw = raw.where(_isAdministratorEntry).toList();
          }
          _total = raw.length;
        }
      } else if (type?.type == 'chatTypeSupergroup') {
        final sgid = type?.int64('supergroup_id');
        if (sgid != null) {
          // getSupergroupFullInfo has the accurate member_count;
          // getSupergroupMembers only returns an approximate count.
          int? fullCount;
          try {
            final fullInfo = await TdClient.shared.query({
              '@type': 'getSupergroupFullInfo',
              'supergroup_id': sgid,
            });
            fullCount = fullInfo.integer('member_count');
          } catch (_) {}
          final res = await TdClient.shared.query({
            '@type': 'getSupergroupMembers',
            'supergroup_id': sgid,
            'filter': {
              '@type': widget.mode == ChatMembersMode.administrators
                  ? 'supergroupMembersFilterAdministrators'
                  : 'supergroupMembersFilterRecent',
            },
            'offset': 0,
            'limit': 200,
          });
          raw = res.objects('members') ?? const <Map<String, dynamic>>[];
          _total = widget.mode == ChatMembersMode.administrators
              ? raw.length
              : fullCount ?? res.integer('member_count') ?? raw.length;
        }
      }
      await _resolve(raw);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool _isAdministratorEntry(Map<String, dynamic> entry) {
    final type = entry.obj('status')?.type;
    return type == 'chatMemberStatusCreator' ||
        type == 'chatMemberStatusAdministrator';
  }

  Future<void> _loadSelfPermissions() async {
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      final uid = me.int64('id');
      if (uid == null) return;
      final member = await TdClient.shared.query({
        '@type': 'getChatMember',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': uid},
      });
      final status = member.obj('status');
      if (status?.type == 'chatMemberStatusCreator') {
        _isCreator = true;
        _canRemove = true;
        _canPromote = true;
        _canManageTags = true;
      } else if (status?.type == 'chatMemberStatusAdministrator') {
        final rights = status?.obj('rights');
        _canRemove = rights?.boolean('can_restrict_members') ?? false;
        _canPromote = rights?.boolean('can_promote_members') ?? false;
        _canManageTags = rights?.boolean('can_manage_tags') ?? false;
      }
    } catch (_) {}
  }

  Future<void> _resolve(List<Map<String, dynamic>> raw) async {
    final result = <GroupMember>[];
    for (final entry in raw) {
      final mid = entry.obj('member_id');
      if (mid?.type != 'messageSenderUser') continue;
      final uid = mid?.int64('user_id');
      if (uid == null) continue;
      final status = entry.obj('status');
      var role = _memberRole(status);
      final title = _memberTitle(entry, status);
      role ??= MemberRole.member;
      try {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': uid,
        });
        result.add(
          GroupMember(
            id: uid,
            name: TDParse.userName(user),
            photo: TDParse.smallPhoto(user.obj('profile_photo')),
            role: role,
            title: title,
            status: TDParse.userStatus(user),
            isOnline: TDParse.isUserOnline(user),
            rawStatus: status,
          ),
        );
      } catch (_) {}
      // Stream partial results so the list fills in progressively.
      if (mounted && result.length % 12 == 0) {
        setState(() => _members = List.of(result));
      }
    }
    // Owners/admins first, then by name.
    result.sort((a, b) {
      int rank(MemberRole? r) => r == MemberRole.owner
          ? 0
          : r == MemberRole.admin
          ? 1
          : 2;
      final byRole = rank(a.role).compareTo(rank(b.role));
      return byRole != 0
          ? byRole
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (mounted) setState(() => _members = result);
  }

  Future<void> _confirmRemove(GroupMember m) async {
    if (!_canRemove || m.role == MemberRole.owner) return;
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.chatMembersRemoveMemberTitle),
      message: AppStrings.t(AppStringKeys.chatMembersRemoveMemberConfirmation, {
        'value1': m.name,
      }),
      confirmText: AppStrings.t(AppStringKeys.chatInfoRemove),
      destructive: true,
    );
    if (!ok) return;
    try {
      await TdClient.shared.query({
        '@type': 'setChatMemberStatus',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': m.id},
        'status': {'@type': 'chatMemberStatusBanned', 'banned_until_date': 0},
      });
      if (!mounted) return;
      setState(() {
        _members.removeWhere((x) => x.id == m.id);
        if (_total > 0) _total--;
      });
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatMembersRemoveFailedPermission),
        );
      }
    }
  }

  Future<void> _openAdministratorEditor(GroupMember member) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatAdministratorEditView(
          chatId: widget.chatId,
          userId: member.id,
          name: member.name,
          status: member.rawStatus,
          canEdit: _canPromote && member.role != MemberRole.owner,
          canTransferOwnership: _isCreator && member.role != MemberRole.owner,
        ),
      ),
    );
    if (changed == true && mounted) await _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _members = [];
      _openRowId = null;
    });
    await _load();
  }

  Future<void> _editTitle(GroupMember member) async {
    if (!_canManageTags) return;
    if (member.role != MemberRole.admin) {
      showToast(context, AppStringKeys.chatMembersPromoteFirst);
      return;
    }
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStringKeys.chatMembersSetTitle,
          initial: member.title ?? '',
          maxLength: 16,
        ),
      ),
    );
    if (!mounted || value == null) return;
    try {
      await TdClient.shared.query({
        '@type': 'setChatMemberTag',
        'chat_id': widget.chatId,
        'user_id': member.id,
        'tag': value.trim(),
      });
      setState(() {
        final index = _members.indexWhere((item) => item.id == member.id);
        if (index >= 0) {
          final title = value.trim();
          _members[index] = member.copyWith(
            title: title,
            clearTitle: title.isEmpty,
          );
        }
      });
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.chatMembersUpdateFailed);
    }
  }

  Future<void> _editMemberTag(GroupMember member) async {
    if (!_canManageTags || member.role != MemberRole.member) return;
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: 'Member tag',
          initial: member.title ?? '',
          maxLength: 16,
        ),
      ),
    );
    if (!mounted || value == null) return;
    final tag = value.trim();
    try {
      await TdClient.shared.query({
        '@type': 'setChatMemberTag',
        'chat_id': widget.chatId,
        'user_id': member.id,
        'tag': tag,
      });
      if (!mounted) return;
      setState(() {
        final index = _members.indexWhere((item) => item.id == member.id);
        if (index >= 0) {
          _members[index] = member.copyWith(
            title: tag,
            clearTitle: tag.isEmpty,
          );
        }
      });
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.chatMembersUpdateFailed);
    }
  }

  Future<void> _confirmDemote(GroupMember member) async {
    if (!_canPromote || member.role != MemberRole.admin) return;
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.chatMembersDemote),
      message: AppStrings.t(AppStringKeys.chatMembersDemoteConfirmation, {
        'value1': member.name,
      }),
      confirmText: AppStrings.t(AppStringKeys.chatMembersDemote),
      destructive: true,
    );
    if (!ok) return;
    try {
      await TdClient.shared.query({
        '@type': 'setChatMemberStatus',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': member.id},
        'status': {'@type': 'chatMemberStatusMember'},
      });
      if (mounted) await _reload();
    } catch (_) {
      if (mounted) showToast(context, AppStringKeys.chatMembersUpdateFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: widget.mode == ChatMembersMode.administrators
                ? AppStrings.t(AppStringKeys.chatMembersAdministratorsTitle)
                : _total > 0
                ? AppStrings.t(AppStringKeys.chatMembersTitleWithCount, {
                    'value1': _total,
                  })
                : telegramText(AppStringKeys.chatInfoGroupMembers),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading && _members.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _members.length,
                    itemBuilder: (context, i) {
                      final m = _members[i];
                      final leadingActions = <_MemberSwipeAction>[
                        if (_canPromote && m.role == MemberRole.member)
                          _MemberSwipeAction(
                            title: AppStringKeys.chatMembersPromote,
                            color: AppTheme.brand,
                            onTap: () => _openAdministratorEditor(m),
                          ),
                        if (_canManageTags && m.role == MemberRole.admin)
                          _MemberSwipeAction(
                            title: AppStringKeys.chatMembersSetTitle,
                            color: const Color(0xFF16A085),
                            onTap: () => _editTitle(m),
                          ),
                        if (_canManageTags && m.role == MemberRole.member)
                          _MemberSwipeAction(
                            title: 'Member tag',
                            color: const Color(0xFF16A085),
                            onTap: () => _editMemberTag(m),
                          ),
                      ];
                      final trailingActions = <_MemberSwipeAction>[
                        if (widget.mode == ChatMembersMode.administrators &&
                            _canPromote &&
                            m.role == MemberRole.admin)
                          _MemberSwipeAction(
                            title: AppStringKeys.chatMembersDemote,
                            color: AppTheme.tagRed,
                            onTap: () => _confirmDemote(m),
                          )
                        else if (_canRemove && m.role != MemberRole.owner)
                          _MemberSwipeAction(
                            title: AppStringKeys.chatInfoRemove,
                            color: AppTheme.tagRed,
                            onTap: () => _confirmRemove(m),
                          ),
                      ];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MemberSwipeRow(
                            rowId: m.id,
                            openRowId: _openRowId,
                            onOpenChanged: (id) =>
                                setState(() => _openRowId = id),
                            leadingActions: leadingActions,
                            trailingActions: trailingActions,
                            onTap: widget.mode == ChatMembersMode.administrators
                                ? () => _openAdministratorEditor(m)
                                : null,
                            child: _memberRow(m),
                          ),
                          const InsetDivider(leadingInset: 70),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(GroupMember m) {
    final c = context.colors;
    final showMemberTags = context.watch<ThemeController>().showMemberTags;
    final showPlainMemberRoleTags = context
        .watch<ThemeController>()
        .showPlainMemberRoleTags;
    final showRole = switch (m.role) {
      null => false,
      MemberRole.member =>
        showPlainMemberRoleTags ||
            (showMemberTags && (m.title?.trim().isNotEmpty ?? false)),
      _ => true,
    };
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            PhotoAvatar(
              title: m.name,
              photo: m.photo,
              size: 44,
              showOnlineDot: m.isOnline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, color: c.textPrimary),
                        ),
                      ),
                      if (showRole) ...[
                        const SizedBox(width: 6),
                        RoleTag(
                          role: m.role!,
                          title: showMemberTags ? m.title : null,
                        ),
                      ],
                    ],
                  ),
                  if (m.status.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      m.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _memberTitle(
    Map<String, dynamic> member,
    Map<String, dynamic>? status,
  ) {
    final raw =
        status?.str('custom_title') ??
        member.str('custom_title') ??
        member.str('tag') ??
        status?.str('title') ??
        member.str('title');
    final title = raw?.trim();
    return title == null || title.isEmpty ? null : title;
  }

  MemberRole? _memberRole(Map<String, dynamic>? status) {
    switch (status?.type) {
      case 'chatMemberStatusCreator':
        return MemberRole.owner;
      case 'chatMemberStatusAdministrator':
        return MemberRole.admin;
      default:
        return null;
    }
  }
}

class _MemberSwipeAction {
  const _MemberSwipeAction({
    required this.title,
    required this.color,
    required this.onTap,
  });

  final String title;
  final Color color;
  final VoidCallback onTap;
}

class _MemberSwipeRow extends StatefulWidget {
  const _MemberSwipeRow({
    required this.rowId,
    required this.openRowId,
    required this.onOpenChanged,
    required this.leadingActions,
    required this.trailingActions,
    required this.child,
    this.onTap,
  });

  final int rowId;
  final int? openRowId;
  final ValueChanged<int?> onOpenChanged;
  final List<_MemberSwipeAction> leadingActions;
  final List<_MemberSwipeAction> trailingActions;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_MemberSwipeRow> createState() => _MemberSwipeRowState();
}

class _MemberSwipeRowState extends State<_MemberSwipeRow> {
  static const _actionWidth = 76.0;
  double _offset = 0;

  double get _leadingWidth => widget.leadingActions.length * _actionWidth;
  double get _trailingWidth => widget.trailingActions.length * _actionWidth;

  @override
  void didUpdateWidget(covariant _MemberSwipeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openRowId != widget.rowId && _offset != 0) _offset = 0;
  }

  void _close() {
    setState(() => _offset = 0);
    widget.onOpenChanged(null);
  }

  Widget _actions(List<_MemberSwipeAction> actions) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final action in actions)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _close();
            action.onTap();
          },
          child: Container(
            width: _actionWidth,
            color: action.color,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              AppStrings.t(action.title),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      children: [
        if (widget.leadingActions.isNotEmpty)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _actions(widget.leadingActions),
            ),
          ),
        if (widget.trailingActions.isNotEmpty)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: _actions(widget.trailingActions),
            ),
          ),
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _offset == 0 ? widget.onTap : _close,
            onHorizontalDragUpdate: (details) {
              final next = _offset + details.delta.dx;
              setState(() {
                if (next > 0 && _leadingWidth > 0) {
                  _offset = next.clamp(0, _leadingWidth + 20);
                } else if (next < 0 && _trailingWidth > 0) {
                  _offset = next.clamp(-_trailingWidth - 20, 0);
                }
              });
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              setState(() {
                if (_offset > 0 &&
                    (_offset > _leadingWidth * 0.35 || velocity > 450)) {
                  _offset = _leadingWidth;
                  widget.onOpenChanged(widget.rowId);
                } else if (_offset < 0 &&
                    (-_offset > _trailingWidth * 0.35 || velocity < -450)) {
                  _offset = -_trailingWidth;
                  widget.onOpenChanged(widget.rowId);
                } else {
                  _offset = 0;
                  widget.onOpenChanged(null);
                }
              });
            },
            child: ColoredBox(
              color: context.colors.background,
              child: widget.child,
            ),
          ),
        ),
      ],
    ),
  );
}
