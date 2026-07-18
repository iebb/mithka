import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

class ChatAdministratorEditView extends StatefulWidget {
  const ChatAdministratorEditView({
    super.key,
    required this.chatId,
    required this.userId,
    required this.name,
    required this.status,
    required this.canEdit,
    this.canTransferOwnership = false,
  });

  final int chatId;
  final int userId;
  final String name;
  final Map<String, dynamic>? status;
  final bool canEdit;
  final bool canTransferOwnership;

  @override
  State<ChatAdministratorEditView> createState() =>
      _ChatAdministratorEditViewState();
}

class _ChatAdministratorEditViewState extends State<ChatAdministratorEditView> {
  static const _allRightKeys = <String>[
    'can_manage_chat',
    'can_change_info',
    'can_post_messages',
    'can_edit_messages',
    'can_delete_messages',
    'can_invite_users',
    'can_restrict_members',
    'can_pin_messages',
    'can_manage_topics',
    'can_promote_members',
    'can_manage_video_chats',
    'can_post_stories',
    'can_edit_stories',
    'can_delete_stories',
    'can_manage_direct_messages',
    'can_manage_tags',
    'is_anonymous',
  ];
  static const _labels = <String, String>{
    'can_manage_chat': AppStringKeys.chatAdminManageChat,
    'can_change_info': AppStringKeys.groupManagementPermissionEditGroupInfo,
    'can_post_messages': 'Post messages',
    'can_edit_messages': 'Edit messages',
    'can_delete_messages': AppStringKeys.chatAdminDeleteMessages,
    'can_invite_users': AppStringKeys.addMembersInviteMembersTitle,
    'can_restrict_members': AppStringKeys.chatAdminRestrictMembers,
    'can_pin_messages': AppStringKeys.groupManagementPermissionPinMessages,
    'can_manage_topics': AppStringKeys.groupManagementPermissionCreateTopics,
    'can_manage_video_chats': AppStringKeys.chatAdminManageVideoChats,
    'can_promote_members': AppStringKeys.chatAdminPromoteMembers,
    'can_post_stories': 'Post stories',
    'can_edit_stories': 'Edit stories',
    'can_delete_stories': 'Delete stories',
    'can_manage_direct_messages': 'Manage direct messages',
    'can_manage_tags': 'Manage member tags',
    'is_anonymous': AppStringKeys.chatAdminAnonymous,
  };

  late final Map<String, bool> _rights;
  late String _customTitle;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.status?.obj('rights');
    final isAdmin = widget.status?.type == 'chatMemberStatusAdministrator';
    _rights = {
      for (final key in _allRightKeys)
        key: existing?.boolean(key) ?? (isAdmin ? false : _defaultRight(key)),
    };
    _customTitle = widget.status?.str('custom_title')?.trim() ?? '';
  }

  bool _defaultRight(String key) => switch (key) {
    'can_manage_chat' ||
    'can_change_info' ||
    'can_delete_messages' ||
    'can_invite_users' ||
    'can_restrict_members' ||
    'can_pin_messages' ||
    'can_manage_topics' ||
    'can_manage_video_chats' ||
    'can_manage_tags' => true,
    'can_post_messages' ||
    'can_edit_messages' ||
    'can_post_stories' ||
    'can_edit_stories' ||
    'can_delete_stories' ||
    'can_manage_direct_messages' => true,
    _ => false,
  };

  Future<void> _editTitle() async {
    if (!widget.canEdit) return;
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStringKeys.chatMembersSetTitle,
          initial: _customTitle,
          maxLength: 16,
        ),
      ),
    );
    if (mounted && value != null) setState(() => _customTitle = value.trim());
  }

  Future<void> _save() async {
    if (!widget.canEdit || _saving) return;
    setState(() => _saving = true);
    try {
      await TdClient.shared.query({
        '@type': 'setChatMemberStatus',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': widget.userId},
        'status': {
          '@type': 'chatMemberStatusAdministrator',
          'custom_title': _customTitle,
          'can_be_edited': true,
          'rights': {'@type': 'chatAdministratorRights', ..._rights},
        },
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, AppStringKeys.chatMembersUpdateFailed);
      }
    }
  }

  Future<String?> _requestOwnershipPassword() async {
    final password = await showAppTextEntryDialog(
      context,
      title: 'Transfer ownership',
      description:
          '${widget.name} will become the owner. Enter your two-step verification password to continue.',
      label: 'Password',
      actionLabel: 'Transfer',
      obscureText: true,
      allowEmpty: false,
    );
    return password?.isEmpty == true ? null : password;
  }

  Future<void> _transferOwnership() async {
    if (!widget.canTransferOwnership || _saving) return;
    try {
      final availability = await TdClient.shared.query({
        '@type': 'canTransferOwnership',
      });
      if (!mounted) return;
      if (availability.type != 'canTransferOwnershipResultOk') {
        final retryAfter = availability.integer('retry_after');
        final reason = switch (availability.type) {
          'canTransferOwnershipResultPasswordNeeded' =>
            'Set up two-step verification before transferring ownership.',
          'canTransferOwnershipResultPasswordTooFresh' =>
            'Your two-step verification password is too new.${retryAfter == null ? '' : ' Try again in $retryAfter seconds.'}',
          'canTransferOwnershipResultSessionTooFresh' =>
            'This session is too new.${retryAfter == null ? '' : ' Try again in $retryAfter seconds.'}',
          _ => 'Ownership can’t be transferred from this session.',
        };
        showToast(context, reason);
        return;
      }
      final password = await _requestOwnershipPassword();
      if (!mounted || password == null) return;
      setState(() => _saving = true);
      await TdClient.shared.query({
        '@type': 'transferChatOwnership',
        'chat_id': widget.chatId,
        'user_id': widget.userId,
        'password': password,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, 'Couldn’t transfer ownership. Check the password.');
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
          NavHeader(
            title: widget.name,
            onBack: () => Navigator.of(context).pop(),
            trailing: widget.canEdit
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        AppStrings.t(AppStringKeys.chatMembersAdminSave),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _saving ? c.textTertiary : AppTheme.brand,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
              children: [
                _section([
                  SettingsRow(
                    title: AppStringKeys.chatMembersSetTitle,
                    value: _customTitle.isEmpty
                        ? AppStringKeys.groupManagementNotSet
                        : _customTitle,
                    showChevron: widget.canEdit,
                    onTap: widget.canEdit ? _editTitle : null,
                  ),
                ]),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Text(
                    AppStrings.t(AppStringKeys.chatMembersAdminPermissions),
                    style: TextStyle(fontSize: 13, color: c.textTertiary),
                  ),
                ),
                _section([
                  for (final entry in _labels.entries) ...[
                    if (entry.key != _labels.keys.first)
                      const InsetDivider(leadingInset: 14),
                    SettingsSwitchRow(
                      title: entry.value,
                      value: _rights[entry.key] ?? false,
                      onChanged: widget.canEdit
                          ? (value) =>
                                setState(() => _rights[entry.key] = value)
                          : (_) {},
                    ),
                  ],
                ]),
                if (widget.canTransferOwnership) ...[
                  const SizedBox(height: 22),
                  _section([
                    SettingsRow(
                      title: 'Transfer ownership',
                      value: widget.name,
                      onTap: _transferOwnership,
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(10),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}
