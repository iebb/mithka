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
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class GroupMember {
  GroupMember({
    required this.id,
    required this.name,
    this.photo,
    this.role,
    this.title,
    this.status = '',
    this.isOnline = false,
  });
  final int id;
  final String name;
  final TdFileRef? photo;
  final MemberRole? role;
  final String? title;
  final String status;
  final bool isOnline;
}

class ChatMembersView extends StatefulWidget {
  const ChatMembersView({super.key, required this.chatId, required this.title});
  final int chatId;
  final String title;

  @override
  State<ChatMembersView> createState() => _ChatMembersViewState();
}

class _ChatMembersViewState extends State<ChatMembersView> {
  List<GroupMember> _members = [];
  int _total = 0;
  bool _loading = true;

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
      List<Map<String, dynamic>> raw = [];
      if (type?.type == 'chatTypeBasicGroup') {
        final gid = type?.int64('basic_group_id');
        if (gid != null) {
          final full = await TdClient.shared.query({
            '@type': 'getBasicGroupFullInfo',
            'basic_group_id': gid,
          });
          raw = full.objects('members') ?? const <Map<String, dynamic>>[];
          _total = raw.length;
        }
      } else if (type?.type == 'chatTypeSupergroup') {
        final sgid = type?.int64('supergroup_id');
        if (sgid != null) {
          final res = await TdClient.shared.query({
            '@type': 'getSupergroupMembers',
            'supergroup_id': sgid,
            'filter': {'@type': 'supergroupMembersFilterRecent'},
            'offset': 0,
            'limit': 200,
          });
          raw = res.objects('members') ?? const <Map<String, dynamic>>[];
          _total = res.integer('member_count') ?? raw.length;
        }
      }
      await _resolve(raw);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
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
    if (m.role == MemberRole.owner) return; // can't remove the creator
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: _total > 0
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
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: () => _confirmRemove(m),
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
                      if (m.role != null) ...[
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
