//
//  group_management_view.dart
//
//  Telegram-style group/channel management for admins/owners. This intentionally
//  maps to real TDLib capabilities instead of showing non-Telegram automation
//  controls that Telegram groups cannot perform natively.
//

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chats/chat_delete_dialog.dart';
import '../chats/chat_delete_policy.dart';
import '../chats/chat_removal_actions.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../profile/qr_code_view.dart';
import '../settings/edit_field_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'chat_members_view.dart';
import 'group_administration_service.dart';
import 'group_administration_view.dart';
import 'group_appearance_view.dart';
import 'group_management_log_view.dart';

class GroupManagementView extends StatefulWidget {
  const GroupManagementView({
    super.key,
    required this.chatId,
    required this.title,
    this.isChannel = false,
  });

  final int chatId;
  final String title;
  final bool isChannel;

  @override
  State<GroupManagementView> createState() => _GroupManagementViewState();
}

class _GroupManagementViewState extends State<GroupManagementView> {
  final TdClient _client = TdClient.shared;
  final GroupAdministrationService _administration =
      GroupAdministrationService();

  String _title = '';
  String _username = '';
  int? _supergroupId;
  bool _isChannel = false;
  bool _isForum = false;
  bool _canGetStatistics = false;
  bool _joinToSend = false;
  bool _joinByRequest = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _canChangeInfo = false;
  bool _canRestrictMembers = false;
  bool _canPromoteMembers = false;
  bool _canDeleteForAllMembers = false;
  bool _deleting = false;

  /// Lifecycle of the getSupergroup-backed values. The page renders from the
  /// local database immediately, but the public username and the join
  /// toggles are only known once getSupergroup lands; their controls stay
  /// disabled until then so a save can never submit an unloaded blank
  /// (which TDLib would treat as "clear the username") and a toggle can
  /// never flip an unknown state.
  int _metaEpoch = 0;
  bool _metaLoading = true;
  bool _metaFailed = false;

  bool get _metaKnown => !_metaLoading && !_metaFailed;

  Map<String, bool> _permissions = _defaultPermissions;

  static const _permissionLabels = <String, String>{
    'can_send_basic_messages':
        AppStringKeys.groupManagementPermissionSendMessages,
    'can_send_photos': AppStringKeys.groupManagementPermissionSendPhotos,
    'can_send_videos': AppStringKeys.groupManagementPermissionSendVideos,
    'can_send_documents': AppStringKeys.groupManagementPermissionSendFiles,
    'can_send_voice_notes': AppStringKeys.groupManagementPermissionSendVoice,
    'can_send_video_notes':
        AppStringKeys.groupManagementPermissionSendVideoMessages,
    'can_send_audios': AppStringKeys.groupManagementPermissionSendMusic,
    'can_send_polls': AppStringKeys.groupManagementPermissionSendPolls,
    'can_send_other_messages':
        AppStringKeys.groupManagementPermissionSendStickersAndGifs,
    'can_add_link_previews':
        AppStringKeys.groupManagementPermissionLinkPreviews,
    'can_react_to_messages':
        AppStringKeys.groupManagementPermissionSendReactions,
    'can_edit_tag': AppStringKeys.groupManagementPermissionEditOwnTag,
    'can_invite_users': AppStringKeys.addMembersInviteMembersTitle,
    'can_pin_messages': AppStringKeys.groupManagementPermissionPinMessages,
    'can_change_info': AppStringKeys.groupManagementPermissionEditGroupInfo,
    'can_create_topics': AppStringKeys.groupManagementPermissionCreateTopics,
  };

  static const _defaultPermissions = <String, bool>{
    'can_send_basic_messages': true,
    'can_send_photos': true,
    'can_send_videos': true,
    'can_send_documents': true,
    'can_send_voice_notes': true,
    'can_send_video_notes': true,
    'can_send_audios': true,
    'can_send_polls': true,
    'can_send_other_messages': true,
    'can_add_link_previews': true,
    'can_react_to_messages': true,
    'can_edit_tag': true,
    'can_invite_users': true,
    'can_pin_messages': false,
    'can_change_info': false,
    'can_create_topics': true,
  };

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _isChannel = widget.isChannel;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    Map<String, dynamic>? chat;
    try {
      chat = await _client.query({
        '@type': 'getChat',
        'chat_id': widget.chatId,
      });
    } catch (_) {
      chat = null;
    }
    if (!mounted) return;
    if (chat == null) {
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      return;
    }
    _title = chat.str('title') ?? _title;
    final type = chat.obj('type');
    _isChannel = type?.boolean('is_channel') ?? _isChannel;
    _canDeleteForAllMembers = chatDeleteCapabilities(chat).canDeleteForAllUsers;
    _permissions = _readPermissions(chat.obj('permissions'));
    _supergroupId = type?.type == 'chatTypeSupergroup'
        ? type?.int64('supergroup_id')
        : null;
    // getChat reads the local database, so the page renders as soon as it
    // lands. Everything after it is cache-backed but can stall: Telegram
    // flood-limits channels.getFullChannel hard, TDLib silently queues
    // flood-waited queries for 30 seconds or more, and a page-wide await on
    // getSupergroupFullInfo keeps the management screen on the spinner the
    // whole time. Rights, supergroup metadata and the optional statistics
    // probe fill in progressively instead of gating the page.
    setState(() => _loading = false);
    unawaited(_loadSelfRights());
    unawaited(_loadSupergroupMeta());
    unawaited(_loadFullInfo());
  }

  Future<void> _loadSelfRights() async {
    try {
      final me = await _client.query({'@type': 'getMe'});
      final uid = me.int64('id');
      if (uid == null) return;
      final member = await _client.query({
        '@type': 'getChatMember',
        'chat_id': widget.chatId,
        'member_id': {'@type': 'messageSenderUser', 'user_id': uid},
      });
      final status = member.obj('status');
      switch (status?.type) {
        case 'chatMemberStatusCreator':
          _canChangeInfo = true;
          _canRestrictMembers = true;
          _canPromoteMembers = true;
        case 'chatMemberStatusAdministrator':
          final rights = status?.obj('rights');
          _canChangeInfo = rights?.boolean('can_change_info') ?? false;
          _canRestrictMembers =
              rights?.boolean('can_restrict_members') ?? false;
          _canPromoteMembers = rights?.boolean('can_promote_members') ?? false;
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadSupergroupMeta() async {
    final supergroupId = _supergroupId;
    if (supergroupId == null) return;
    final epoch = ++_metaEpoch;
    setState(() {
      _metaLoading = true;
      _metaFailed = false;
    });
    try {
      final sg = await _client.query({
        '@type': 'getSupergroup',
        'supergroup_id': supergroupId,
      });
      if (!mounted || epoch != _metaEpoch) return;
      setState(() {
        _username =
            sg.obj('usernames')?.str('editable_username') ??
            sg.str('username') ??
            '';
        _joinToSend = sg.boolean('join_to_send_messages') ?? false;
        _joinByRequest = sg.boolean('join_by_request') ?? false;
        _isForum = sg.boolean('is_forum') ?? false;
        _metaLoading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _metaEpoch) return;
      // The metadata-backed controls stay disabled and a retry card is
      // offered; everything else on the page keeps working.
      setState(() => _metaFailed = true);
    }
  }

  Future<void> _retrySupergroupMeta() => _loadSupergroupMeta();

  Future<void> _loadFullInfo() async {
    final supergroupId = _supergroupId;
    if (supergroupId == null) return;
    try {
      final full = await _client.query({
        '@type': 'getSupergroupFullInfo',
        'supergroup_id': supergroupId,
      }, timeout: const Duration(seconds: 15));
      if (!mounted) return;
      setState(
        () => _canGetStatistics = full.boolean('can_get_statistics') ?? false,
      );
    } catch (_) {
      // Statistics stays hidden when the probe fails or is flood-limited; the
      // rest of the page works regardless.
    }
  }

  Map<String, bool> _readPermissions(Map<String, dynamic>? raw) {
    final values = Map<String, bool>.of(_defaultPermissions);
    if (raw == null) return values;
    for (final key in values.keys) {
      values[key] = raw.boolean(key) ?? values[key] ?? false;
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStrings.t(
              _isChannel
                  ? AppStringKeys.chatInfoManageChannel
                  : AppStringKeys.chatInfoManageGroup,
            ),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: _GroupManagementSpinner())
                : _loadFailed
                ? _GroupManagementLoadError(onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                    children: [
                      _section(
                        AppStrings.t(AppStringKeys.groupManagementBasicSection),
                        [
                          _navRow(
                            AppStrings.t(
                              _isChannel
                                  ? AppStringKeys.groupManagementChannelName
                                  : AppStringKeys.groupManagementGroupName,
                            ),
                            value: _title,
                            onTap: _editTitle,
                          ),
                          if (_supergroupId != null)
                            _navRow(
                              AppStrings.t(
                                AppStringKeys.groupManagementPublicUsername,
                              ),
                              value: _username.isEmpty
                                  ? AppStrings.t(
                                      AppStringKeys.groupManagementNotSet,
                                    )
                                  : '@$_username',
                              // Gated on metadata, not just rights: opening
                              // the editor before getSupergroup lands would
                              // pre-fill a blank, and saving that blank
                              // clears the username server-side.
                              onTap: (_canChangeInfo && _metaKnown)
                                  ? _editUsername
                                  : null,
                            ),
                          _navRow(
                            AppStrings.t(
                              AppStringKeys.groupManagementInviteLinkQr,
                            ),
                            onTap: () => Navigator.of(context).push(
                              _pageRoute(
                                QRCodeView(
                                  name: _title,
                                  chatId: widget.chatId,
                                  isGroup: true,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_supergroupId != null) ...[
                        _gap(),
                        _section(
                          AppStrings.t(AppStringKeys.groupAppearanceTitle),
                          [
                            _navRow(
                              AppStrings.t(AppStringKeys.groupAppearanceTitle),
                              value: AppStrings.t(
                                AppStringKeys.groupAppearanceDescription,
                              ),
                              onTap: _openAppearance,
                            ),
                          ],
                        ),
                      ],
                      if (_supergroupId != null) ...[
                        _gap(),
                        _section(
                          AppStrings.t(
                            AppStringKeys.groupManagementJoinSection,
                          ),
                          [
                            _switchRow(
                              AppStrings.t(
                                AppStringKeys.groupManagementJoinBeforePosting,
                              ),
                              _joinToSend,
                              _canChangeInfo && _metaKnown,
                              _setJoinToSend,
                            ),
                            _divider(),
                            _switchRow(
                              AppStrings.t(
                                AppStringKeys
                                    .groupManagementAdminApprovalRequired,
                              ),
                              _joinByRequest,
                              _canChangeInfo && _metaKnown,
                              _setJoinByRequest,
                            ),
                          ],
                        ),
                      ],
                      if (_supergroupId != null && _metaFailed) ...[
                        _gap(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  AppStrings.t(
                                    AppStringKeys.groupManagementLoadFailed,
                                  ),
                                  style: AppTextStyle.footnote(
                                    context.colors.textSecondary,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                key: const ValueKey(
                                  'group-management-meta-retry',
                                ),
                                behavior: HitTestBehavior.opaque,
                                onTap: _retrySupergroupMeta,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    AppStrings.t(
                                      AppStringKeys.groupManagementRetry,
                                    ),
                                    style: AppTextStyle.footnote(
                                      AppTheme.brand,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      _gap(),
                      _section(
                        AppStrings.t(
                          AppStringKeys.groupManagementAdministrationSection,
                        ),
                        [
                          _navRow(
                            AppStrings.t(
                              AppStringKeys.groupManagementInviteLinks,
                            ),
                            onTap: () => Navigator.of(context).push(
                              _pageRoute(
                                ChatInviteLinksAdministrationView(
                                  chatId: widget.chatId,
                                ),
                              ),
                            ),
                          ),
                          _divider(),
                          _navRow(
                            AppStrings.t(
                              AppStringKeys.groupManagementJoinRequests,
                            ),
                            onTap: () => Navigator.of(context).push(
                              _pageRoute(
                                ChatJoinRequestsAdministrationView(
                                  chatId: widget.chatId,
                                ),
                              ),
                            ),
                          ),
                          if (_supergroupId != null) ...[
                            _divider(),
                            _navRow(
                              AppStrings.t(
                                AppStringKeys.groupManagementAdvancedControls,
                              ),
                              onTap: () => Navigator.of(context).push(
                                _pageRoute(
                                  GroupAdvancedAdministrationView(
                                    chatId: widget.chatId,
                                    supergroupId: _supergroupId!,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (_isForum) ...[
                            _divider(),
                            _navRow(
                              AppStrings.t(
                                AppStringKeys.groupManagementForumTopics,
                              ),
                              onTap: () => Navigator.of(context).push(
                                _pageRoute(
                                  ForumTopicsAdministrationView(
                                    chatId: widget.chatId,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (_canGetStatistics) ...[
                            _divider(),
                            _navRow(
                              AppStrings.t(
                                AppStringKeys.groupManagementStatistics,
                              ),
                              onTap: () => Navigator.of(context).push(
                                _pageRoute(
                                  ChatStatisticsAdministrationView(
                                    chatId: widget.chatId,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (_supergroupId != null) ...[
                            _divider(),
                            _navRow(
                              AppStrings.t(
                                AppStringKeys.groupManagementBoostsAndGiveaways,
                              ),
                              onTap: () => Navigator.of(context).push(
                                _pageRoute(
                                  ChatBoostsAdministrationView(
                                    chatId: widget.chatId,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      _gap(),
                      _section(
                        AppStrings.t(
                          AppStringKeys.groupManagementMembersSection,
                        ),
                        [
                          _navRow(
                            AppStrings.t(
                              _isChannel
                                  ? AppStringKeys
                                        .groupManagementChannelSubscribers
                                  : AppStringKeys.groupManagementMembers,
                            ),
                            onTap: _openMembers,
                          ),
                          _divider(),
                          _navRow(
                            AppStrings.t(AppStringKeys.groupManagementLogAdmin),
                            value: _canPromoteMembers
                                ? AppStrings.t(
                                    AppStringKeys.groupManagementEditable,
                                  )
                                : AppStrings.t(
                                    AppStringKeys.groupManagementReadOnly,
                                  ),
                            onTap: _openAdministrators,
                          ),
                          if (_supergroupId != null && _canRestrictMembers) ...[
                            _divider(),
                            _navRow(
                              AppStrings.t(
                                AppStringKeys.groupManagementRemovedUsers,
                              ),
                              onTap: _openRemovedUsers,
                            ),
                          ],
                          // The admin log only exists for supergroups and
                          // channels; basic groups have no event log to show.
                          if (_supergroupId != null) ...[
                            _divider(),
                            _navRow(
                              AppStrings.t(
                                AppStringKeys.groupManagementLogTitle,
                              ),
                              onTap: () => Navigator.of(context).push(
                                _pageRoute(
                                  GroupManagementLogView(
                                    chatId: widget.chatId,
                                    title: _title,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (!_isChannel) ...[
                        _gap(),
                        _section(
                          AppStrings.t(
                            AppStringKeys.groupManagementPostingPermissions,
                          ),
                          [
                            // can_create_topics is a member right only in
                            // forum supergroups; hide it everywhere else.
                            for (final entry in _permissionLabels.entries.where(
                              (e) => e.key != 'can_create_topics' || _isForum,
                            )) ...[
                              if (entry.key != _permissionLabels.keys.first)
                                _divider(),
                              _switchRow(
                                entry.value.l10n(context),
                                _permissions[entry.key] ?? false,
                                _canRestrictMembers,
                                (value) => _setPermission(entry.key, value),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (_canDeleteForAllMembers) ...[
                        _gap(),
                        _deleteChatCard(),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _gap() => const SizedBox(height: 22);

  Widget _section(String title, List<Widget> children) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Text(
            title,
            style: TextStyle(fontSize: 13, color: c.textTertiary),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _divider() => const InsetDivider(leadingInset: 14);

  Widget _deleteChatCard() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        key: const ValueKey('group-management-delete-chat'),
        behavior: HitTestBehavior.opaque,
        onTap: _deleting ? null : _deleteChat,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              _deleteChatLabel,
              style: TextStyle(
                fontSize: 15,
                color: _deleting ? c.textTertiary : AppTheme.tagRed,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _deleteChatLabel => AppStrings.t(
    _isChannel
        ? AppStringKeys.groupManagementDeleteChannel
        : AppStringKeys.groupManagementDeleteGroup,
  );

  Future<void> _deleteChat() async {
    final impact = AppStrings.t(AppStringKeys.chatDeleteAllMembersDescription);
    final confirmed = await showTwoStepDestructiveConfirmation(
      context,
      firstTitle: _deleteChatLabel,
      firstMessage: impact,
      firstConfirmText: AppStringKeys.confirmContinue,
      finalTitle: AppStrings.t(AppStringKeys.chatDeleteFinalQuestion, {
        'value1': _title,
      }),
      finalMessage:
          '$impact\n\n${AppStrings.t(AppStringKeys.chatDeleteFinalWarning)}',
      finalConfirmText: AppStringKeys.chatDeleteForAllMembers,
    );
    if (!mounted || !confirmed) return;
    setState(() => _deleting = true);
    try {
      await deleteChatForAllMembers(
        chatId: widget.chatId,
        query: _client.query,
        onDeleted: () =>
            _client.emitLocalUpdate(chatLeftLocalUpdate(widget.chatId)),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        if (error is ChatRemovalUnavailable) _canDeleteForAllMembers = false;
      });
      showToast(
        context,
        error is ChatRemovalUnavailable
            ? AppStringKeys.chatDeleteUnavailable
            : AppStrings.t(AppStringKeys.chatDeleteActionsFailed, {
                'value1': error is TdError ? error.message : '$error',
              }),
      );
    }
  }

  Widget _navRow(String title, {String? value, VoidCallback? onTap}) {
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
              Text(title, style: TextStyle(fontSize: 15, color: c.textPrimary)),
              const SizedBox(width: 12),
              if (value != null)
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.textTertiary),
                  ),
                )
              else
                const Spacer(),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 14,
                  color: c.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow(
    String title,
    bool value,
    bool enabled,
    ValueChanged<bool> onChanged,
  ) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: enabled ? c.textPrimary : c.textTertiary,
                ),
              ),
            ),
            _GroupManagementSwitch(
              value: value,
              activeColor: AppTheme.brand,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTitle() async {
    if (!_canChangeInfo) {
      showToast(context, AppStringKeys.groupManagementNoEditInfoPermission);
      return;
    }
    final value = await Navigator.of(context).push<String>(
      _pageRoute(
        EditFieldView(
          title: _isChannel
              ? AppStringKeys.groupManagementChannelName
              : AppStringKeys.groupManagementGroupName,
          initial: _title,
          maxLength: 128,
        ),
      ),
    );
    if (!mounted || value == null || value.isEmpty || value == _title) return;
    try {
      await _client.query({
        '@type': 'setChatTitle',
        'chat_id': widget.chatId,
        'title': value,
      });
      setState(() => _title = value);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.groupManagementEditFailed);
      }
    }
  }

  Future<void> _editUsername() async {
    if (_supergroupId == null) return;
    final value = await Navigator.of(context).push<String>(
      _pageRoute(
        EditFieldView(
          title: AppStringKeys.groupManagementPublicUsername,
          initial: _username,
          prefix: '@',
          maxLength: 32,
        ),
      ),
    );
    // An empty value is valid: TDLib documents it as "remove the username".
    if (!mounted || value == null || value == _username) return;
    try {
      await _client.query({
        '@type': 'setSupergroupUsername',
        'supergroup_id': _supergroupId,
        'username': value,
      });
      setState(() => _username = value);
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStringKeys.groupManagementUsernameUnavailableOrForbidden,
        );
      }
    }
  }

  Future<void> _setJoinToSend(bool value) async {
    final id = _supergroupId;
    if (id == null) return;
    setState(() => _joinToSend = value);
    try {
      await _client.query({
        '@type': 'toggleSupergroupJoinToSendMessages',
        'supergroup_id': id,
        'join_to_send_messages': value,
      });
    } catch (_) {
      if (mounted) {
        setState(() => _joinToSend = !value);
        showToast(context, AppStringKeys.groupManagementSetFailed);
      }
    }
  }

  Future<void> _setJoinByRequest(bool value) async {
    final id = _supergroupId;
    if (id == null) return;
    setState(() => _joinByRequest = value);
    try {
      await _administration.setJoinByRequest(id, value);
    } catch (_) {
      if (mounted) {
        setState(() => _joinByRequest = !value);
        showToast(context, AppStringKeys.groupManagementSetFailed);
      }
    }
  }

  Future<void> _setPermission(String key, bool value) async {
    final next = Map<String, bool>.of(_permissions)..[key] = value;
    setState(() => _permissions = next);
    try {
      await _client.query({
        '@type': 'setChatPermissions',
        'chat_id': widget.chatId,
        'permissions': {'@type': 'chatPermissions', ...next},
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _permissions = Map<String, bool>.of(_permissions)..[key] = !value,
        );
        showToast(context, AppStringKeys.groupManagementPermissionSetFailed);
      }
    }
  }

  void _openMembers() {
    Navigator.of(
      context,
    ).push(_pageRoute(ChatMembersView(chatId: widget.chatId, title: _title)));
  }

  void _openAdministrators() {
    Navigator.of(context).push(
      _pageRoute(
        ChatMembersView(
          chatId: widget.chatId,
          title: _title,
          mode: ChatMembersMode.administrators,
        ),
      ),
    );
  }

  void _openRemovedUsers() {
    Navigator.of(context).push(
      _pageRoute(
        ChatMembersView(
          chatId: widget.chatId,
          title: _title,
          mode: ChatMembersMode.banned,
        ),
      ),
    );
  }

  void _openAppearance() {
    final supergroupId = _supergroupId;
    if (supergroupId == null) return;
    Navigator.of(context).push(
      _pageRoute(
        GroupAppearanceView(
          chatId: widget.chatId,
          supergroupId: supergroupId,
          title: _title,
          isChannel: _isChannel,
          canChangeInfo: _canChangeInfo,
        ),
      ),
    );
  }

  PageRoute<T> _pageRoute<T>(Widget child) =>
      AppFadePageRoute<T>(pageBuilder: (_, _, _) => child);
}

class _GroupManagementSwitch extends StatelessWidget {
  const _GroupManagementSwitch({
    required this.value,
    required this.activeColor,
    this.onChanged,
  });

  final bool value;
  final Color activeColor;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? activeColor : c.divider,
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: onChanged == null
                  ? c.textTertiary
                  : const Color(0xFFFFFFFF),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupManagementLoadError extends StatelessWidget {
  const _GroupManagementLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                HeroAppIcons.triangleExclamation,
                size: 24,
                color: AppTheme.tagRed,
              ),
              const SizedBox(height: 10),
              Text(
                AppStrings.t(AppStringKeys.groupManagementLoadFailed),
                style: TextStyle(fontSize: 15, color: c.textSecondary),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                key: const ValueKey('group-management-load-retry'),
                behavior: HitTestBehavior.opaque,
                onTap: onRetry,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  child: Text(
                    AppStrings.t(AppStringKeys.groupManagementRetry),
                    style: TextStyle(fontSize: 15, color: AppTheme.brand),
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

class _GroupManagementSpinner extends StatefulWidget {
  const _GroupManagementSpinner();

  @override
  State<_GroupManagementSpinner> createState() =>
      _GroupManagementSpinnerState();
}

class _GroupManagementSpinnerState extends State<_GroupManagementSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: AppIcon(
      HeroAppIcons.rotate,
      size: 24,
      color: context.colors.textTertiary,
    ),
  );
}
