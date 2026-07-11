//
//  chat_info_view.dart
//
//  Chat info / settings page for a private chat or group (reached by tapping the
//  conversation header's menu). Grouped white cards on the gray canvas: identity,
//  member grid (groups), quick rows, pin/mute toggles, destructive actions.
//  Port of the Swift `ChatInfoView` / `ChatInfoViewModel`.
//

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/icon_grid.dart';
import '../components/photo_avatar.dart';
import 'package:mithka/notifications/scope_notification_settings.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../profile/qr_code_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'add_members_view.dart';
import 'chat_members_view.dart';
import 'chat_search_view.dart';
import 'group_management_view.dart';
import 'pinned_messages_view.dart';
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
      final notice = _vm.takeNotice();
      if (notice != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showToast(context, notice);
        });
      }
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

  void _openChatFolders() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatFolderMembershipView(chatId: widget.chatId, title: _vm.title),
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
          NavHeader(
            title: AppStrings.t(AppStringKeys.chatInfoTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
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
                if (_vm.isGroup) ...[
                  const SizedBox(height: 14),
                  _groupAppsCard(),
                ],
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

  /// custom identity row: avatar + name/subtitle inline & left-aligned, with a
  /// QR icon + chevron on the right (groups → tap opens the 群二维码 page).
  Widget _topCard() {
    final c = context.colors;
    final circleGroups = context.watch<ThemeController>().circularGroupAvatars;
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
                square: _vm.isGroup && !circleGroups,
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
                AppIcon(HeroAppIcons.qrcode, size: 22, color: c.textSecondary),
                const SizedBox(width: 6),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 15,
                  color: c.textTertiary,
                ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _vm.groupNumber.isEmpty
              ? AppStrings.t(AppStringKeys.chatInfoGroupChat)
              : AppStrings.t(AppStringKeys.chatInfoGroupId, {
                  'value1': _vm.groupNumber,
                }),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        const SizedBox(height: 4),
        if (_vm.isPublic && (_vm.username?.isNotEmpty ?? false))
          Text(
            '@${_vm.username}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: AppTheme.brand),
          )
        else
          _lockBadge(AppStrings.t(AppStringKeys.chatInfoNotSearchable)),
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
          AppIcon(HeroAppIcons.lock, size: 10, color: c.textTertiary),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 11, color: c.textTertiary)),
        ],
      ),
    );
  }

  Widget _memberGridCard() {
    final c = context.colors;
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
                  telegramText(AppStringKeys.chatInfoGroupMembers),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
                const Spacer(),
                if (_vm.memberCount > 0)
                  Text(
                    AppStrings.t(AppStringKeys.topicChatMemberCount, {
                      'value1': _vm.memberCount,
                    }),
                    style: TextStyle(fontSize: 14, color: c.textSecondary),
                  ),
                const SizedBox(width: 6),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 14,
                  color: c.textTertiary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final perRow = _gridColumnsForWidth(constraints.maxWidth);
              final actionTiles =
                  (_vm.canInvite ? 1 : 0) + (_vm.canRemove ? 1 : 0);
              final maxTiles = perRow * 3;
              final memberSlots = (maxTiles - actionTiles).clamp(0, maxTiles);
              final shown = _vm.members.take(memberSlots).toList();
              return IconGrid(
                perRow: perRow,
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
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_vm.canInvite)
                    _actionTile(
                      HeroAppIcons.plus.data,
                      AppStrings.t(AppStringKeys.topicChatInvite),
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AddMembersView(chatId: widget.chatId),
                        ),
                      ),
                    ),
                  if (_vm.canRemove)
                    _actionTile(
                      HeroAppIcons.minus.data,
                      AppStrings.t(AppStringKeys.chatInfoRemove),
                      _openMembers,
                    ),
                ],
              );
            },
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
            AppStrings.t(AppStringKeys.chatInfoSearchHistory),
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ChatSearchView(chatId: widget.chatId, title: widget.title),
              ),
            ),
          ),
          const InsetDivider(leadingInset: 14),
          _infoRow(
            AppStrings.t(AppStringKeys.chatInfoChatFolders),
            _openChatFolders,
          ),
          if (!_vm.isGroup) ...[
            const InsetDivider(leadingInset: 14),
            _infoRow(
              telegramText(AppStringKeys.topicPostContentFile),
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SharedMediaView(
                    chatId: widget.chatId,
                    title: widget.title,
                    initialTab: 1,
                    displayTitle: AppStringKeys.topicPostContentFile,
                    lockedTab: true,
                  ),
                ),
              ),
            ),
            const InsetDivider(leadingInset: 14),
            _infoRow(
              AppStrings.t(AppStringKeys.chatInfoGroupVideos),
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SharedMediaView(
                    chatId: widget.chatId,
                    title: widget.title,
                    initialTab: 4,
                    displayTitle: AppStringKeys.chatInfoGroupVideos,
                    lockedTab: true,
                  ),
                ),
              ),
            ),
          ],
          if (_vm.isGroup && _vm.canManageGroup) ...[
            const InsetDivider(leadingInset: 14),
            _infoRow(
              AppStrings.t(AppStringKeys.chatInfoManageGroup),
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupManagementView(
                    chatId: widget.chatId,
                    title: _vm.title,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String title, VoidCallback onTap) {
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
              const Spacer(),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 14,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupAppsCard() {
    final c = context.colors;
    return Container(
      decoration: _card,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppStrings.t(AppStringKeys.chatInfoGroupApps),
                  style: TextStyle(fontSize: 15, color: c.textPrimary),
                ),
                const Spacer(),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 14,
                  color: c.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => IconGrid(
                perRow: _gridColumnsForWidth(constraints.maxWidth),
                children: [
                  _groupAppItem(
                    icon: HeroAppIcons.solidFolder.data,
                    color: const Color(0xFFFFB300),
                    label: telegramText(AppStringKeys.topicPostContentFile),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SharedMediaView(
                          chatId: widget.chatId,
                          title: widget.title,
                          initialTab: 1,
                          displayTitle: AppStringKeys.chatInfoGroupFiles,
                          lockedTab: true,
                        ),
                      ),
                    ),
                  ),
                  _groupAppItem(
                    icon: HeroAppIcons.solidImage.data,
                    color: const Color(0xFF15A7F7),
                    label: AppStrings.t(AppStringKeys.chatInfoAlbum),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SharedMediaView(
                          chatId: widget.chatId,
                          title: widget.title,
                          displayTitle: AppStringKeys.chatInfoGroupAlbum,
                          lockedTab: true,
                        ),
                      ),
                    ),
                  ),
                  _groupAppItem(
                    icon: HeroAppIcons.video.data,
                    color: const Color(0xFF7B61FF),
                    label: AppStrings.t(AppStringKeys.chatInfoGroupVideos),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SharedMediaView(
                          chatId: widget.chatId,
                          title: widget.title,
                          initialTab: 4,
                          displayTitle: AppStringKeys.chatInfoGroupVideos,
                          lockedTab: true,
                        ),
                      ),
                    ),
                  ),
                  _groupAppItem(
                    icon: HeroAppIcons.solidStar.data,
                    color: const Color(0xFF18C26E),
                    label: telegramText(AppStringKeys.chatInfoPinnedHighlights),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PinnedMessagesView(
                          chatId: widget.chatId,
                          title: widget.title,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupAppItem({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  int _gridColumnsForWidth(double width) =>
      (width / 70).floor().clamp(5, 12).toInt();

  Widget _togglesCard() {
    final showGroupAssistant = _vm.isMuted || _vm.isArchived;
    return SettingsCard(
      children: [
        SettingsSwitchRow(
          title: AppStrings.t(AppStringKeys.chatInfoPinChat),
          value: _vm.isPinned,
          onChanged: _vm.setPinned,
          height: 52,
          leadingInset: 14,
        ),
        const InsetDivider(leadingInset: 14),
        SettingsSwitchRow(
          title: AppStrings.t(AppStringKeys.topicChatMuteMessagesToggle),
          value: _vm.isMuted,
          onChanged: _vm.setMuted,
          height: 52,
          leadingInset: 14,
        ),
        if (showGroupAssistant) ...[
          const InsetDivider(leadingInset: 14),
          SettingsSwitchRow(
            title: AppStrings.t(AppStringKeys.chatInfoMoveToGroupAssistant),
            value: _vm.isArchived,
            onChanged: _vm.setArchived,
            height: 52,
            leadingInset: 14,
          ),
        ],
        const InsetDivider(leadingInset: 14),
        SettingsRow(
          title: AppStrings.t(AppStringKeys.chatInfoAutoDeleteMessages),
          value: TDParse.formatDuration(_vm.autoDeleteTime),
          onTap: _vm.canChangeAutoDelete ? _chooseAutoDelete : null,
          showChevron: _vm.canChangeAutoDelete,
          height: 52,
          leadingInset: 14,
        ),
      ],
    );
  }

  Future<void> _chooseAutoDelete() async {
    if (!_vm.canChangeAutoDelete) return;
    final options = <(String, int)>[
      (AppStrings.t(AppStringKeys.chatInfoAutoDeleteOff), 0),
      (AppStrings.t(AppStringKeys.chatInfoAutoDeleteOneDay), 86400),
      (AppStrings.t(AppStringKeys.chatInfoAutoDeleteSevenDays), 604800),
      (AppStrings.t(AppStringKeys.chatInfoAutoDeleteOneMonth), 2592000),
    ];
    final selected = await showCupertinoModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(AppStrings.t(AppStringKeys.chatInfoAutoDeleteMessages)),
        actions: [
          for (final option in options)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(option.$2),
              child: Text(option.$1),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.t(AppStringKeys.countryPickerCancel)),
        ),
      ),
    );
    if (selected == null) return;
    _vm.setAutoDeleteTime(selected);
  }

  Widget _destructiveCard() {
    return Container(
      decoration: _card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _destructiveRow(
            AppStrings.t(AppStringKeys.chatInfoClearHistory),
            _clearHistory,
          ),
          // Only a confirmed member can quit — hide 退出 for non-joined groups/channels.
          if (_vm.isGroup && _vm.isMember) ...[
            const InsetDivider(leadingInset: 0),
            _destructiveRow(
              AppStrings.t(
                _vm.isChannel
                    ? AppStringKeys.topicChatLeaveChannel
                    : AppStringKeys.chatInfoLeaveGroup,
              ),
              _leaveChat,
            ),
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

  Future<void> _clearHistory() async {
    final first = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.chatInfoClearHistoryQuestion),
      message: AppStrings.t(AppStringKeys.chatInfoClearHistoryDescription),
      confirmText: AppStrings.t(AppStringKeys.chatInfoClear),
      destructive: true,
    );
    if (!mounted || !first) return;
    final second = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.chatInfoConfirmAgain),
      message: AppStrings.t(
        AppStringKeys.chatInfoClearHistoryIrreversibleWarning,
      ),
      confirmText: AppStrings.t(AppStringKeys.chatInfoConfirmClearHistory),
      destructive: true,
    );
    if (!mounted || !second) return;
    try {
      await _vm.clearHistory();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showToast(context, _vm.actionErrorNotice(error));
    }
  }

  Future<void> _leaveChat() async {
    try {
      await _vm.leaveChat();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showToast(context, _vm.actionErrorNotice(error));
    }
  }
}

class ChatFolderMembershipView extends StatefulWidget {
  const ChatFolderMembershipView({
    super.key,
    required this.chatId,
    required this.title,
  });

  final int chatId;
  final String title;

  @override
  State<ChatFolderMembershipView> createState() =>
      _ChatFolderMembershipViewState();
}

class _FolderMembership {
  _FolderMembership({
    required this.id,
    required this.title,
    required this.folder,
    required this.selected,
    required this.autoSelected,
    this.editable = true,
  });

  final int id;
  final String title;
  Map<String, dynamic> folder;
  bool selected;
  bool autoSelected;
  final bool editable;
  bool saving = false;
}

class _ChatFolderMembershipViewState extends State<ChatFolderMembershipView> {
  final _client = TdClient.shared;
  final List<_FolderMembership> _folders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chat = await _client.query({
        '@type': 'getChat',
        'chat_id': widget.chatId,
      });
      final activeFolderIds = <int>{};
      for (final pos
          in chat.objects('positions') ?? const <Map<String, dynamic>>[]) {
        final list = pos.obj('list');
        if (list?.type == 'chatListFolder' && (pos.int64('order') ?? 0) > 0) {
          final id = list?.integer('chat_folder_id');
          if (id != null) activeFolderIds.add(id);
        }
      }

      final infos = await _client.query({'@type': 'getChatFolders'});
      final raw =
          infos.objects('chat_folders') ??
          infos.objects('chat_folder_infos') ??
          const <Map<String, dynamic>>[];
      final loaded = <_FolderMembership>[];
      for (final info in raw) {
        final id = info.integer('id') ?? info.integer('chat_folder_id');
        if (id == null) continue;
        Map<String, dynamic>? folder;
        try {
          folder = await _client.query({
            '@type': 'getChatFolder',
            'chat_folder_id': id,
          });
        } catch (_) {}
        if (folder == null) {
          loaded.add(
            _FolderMembership(
              id: id,
              title: _folderTitle(const <String, dynamic>{}, info, id),
              folder: const <String, dynamic>{},
              selected: activeFolderIds.contains(id),
              autoSelected: activeFolderIds.contains(id),
              editable: false,
            ),
          );
          continue;
        }
        final included = _ids(folder, 'included_chat_ids');
        final excluded = _ids(folder, 'excluded_chat_ids');
        final autoSelected =
            activeFolderIds.contains(id) &&
            !included.contains(widget.chatId) &&
            !excluded.contains(widget.chatId);
        loaded.add(
          _FolderMembership(
            id: id,
            title: _folderTitle(folder, info, id),
            folder: folder,
            selected: included.contains(widget.chatId) || autoSelected,
            autoSelected: autoSelected,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _folders
          ..clear()
          ..addAll(loaded);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppStrings.t(AppStringKeys.chatInfoLoadFoldersFailed);
      });
    }
  }

  static Set<int> _ids(Map<String, dynamic> folder, String key) =>
      (folder.int64Array(key) ?? const <int>[]).toSet();

  static String _folderTitle(
    Map<String, dynamic> folder,
    Map<String, dynamic> info,
    int id,
  ) {
    final title =
        folder.str('title') ??
        folder.obj('title')?.str('text') ??
        folder.obj('name')?.obj('text')?.str('text') ??
        info.obj('name')?.obj('text')?.str('text') ??
        info.obj('title')?.str('text') ??
        info.str('title') ??
        info.str('name');
    return (title == null || title.isEmpty)
        ? AppStrings.t(AppStringKeys.chatInfoFolderName, {'value1': id})
        : title;
  }

  Future<void> _toggle(_FolderMembership item, bool value) async {
    if (!item.editable || item.saving || item.selected == value) return;
    setState(() {
      item.selected = value;
      item.saving = true;
    });

    final previous = Map<String, dynamic>.from(item.folder);
    final wasAutoSelected = item.autoSelected;
    final updated = _folderWithMembership(item, value);
    try {
      await _client.query({
        '@type': 'editChatFolder',
        'chat_folder_id': item.id,
        'folder': updated,
      });
      if (!mounted) return;
      setState(() {
        item.folder = updated;
        item.autoSelected = value ? false : wasAutoSelected;
        item.saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        item.folder = previous;
        item.selected = !value;
        item.saving = false;
      });
    }
  }

  Map<String, dynamic> _folderWithMembership(
    _FolderMembership item,
    bool include,
  ) {
    final folder = item.folder;
    final included = _ids(folder, 'included_chat_ids');
    final excluded = _ids(folder, 'excluded_chat_ids');
    if (include) {
      included.add(widget.chatId);
      excluded.remove(widget.chatId);
    } else {
      included.remove(widget.chatId);
      if (item.autoSelected) {
        excluded.add(widget.chatId);
      } else {
        excluded.remove(widget.chatId);
      }
    }

    return _chatFolderPayload(
      folder,
      includedChatIds: included,
      excludedChatIds: excluded,
    );
  }

  static Map<String, dynamic> _chatFolderPayload(
    Map<String, dynamic> folder, {
    required Set<int> includedChatIds,
    required Set<int> excludedChatIds,
  }) {
    return {
      '@type': 'chatFolder',
      'title':
          folder.str('title') ??
          _folderTitle(folder, const <String, dynamic>{}, 0),
      if (folder.obj('icon') != null) 'icon': folder.obj('icon'),
      'is_shareable': folder.boolean('is_shareable') ?? false,
      'pinned_chat_ids': folder.int64Array('pinned_chat_ids') ?? const <int>[],
      'included_chat_ids': includedChatIds.toList()..sort(),
      'excluded_chat_ids': excludedChatIds.toList()..sort(),
      'exclude_muted': folder.boolean('exclude_muted') ?? false,
      'exclude_read': folder.boolean('exclude_read') ?? false,
      'exclude_archived': folder.boolean('exclude_archived') ?? false,
      'include_contacts': folder.boolean('include_contacts') ?? false,
      'include_non_contacts': folder.boolean('include_non_contacts') ?? false,
      'include_bots': folder.boolean('include_bots') ?? false,
      'include_groups': folder.boolean('include_groups') ?? false,
      'include_channels': folder.boolean('include_channels') ?? false,
    };
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) {
        final c = context.colors;
        return AlertDialog(
          backgroundColor: c.card,
          title: Text(
            AppStrings.t(AppStringKeys.chatInfoCreateFolderTitle),
            style: TextStyle(color: c.textPrimary),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: AppStrings.t(AppStringKeys.chatInfoFolderNameLabel),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppStrings.t(AppStringKeys.countryPickerCancel)),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(AppStrings.t(AppStringKeys.chatInfoCreate)),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _client.query({
        '@type': 'createChatFolder',
        'folder': _chatFolderPayload(
          {'@type': 'chatFolder', 'title': title},
          includedChatIds: {widget.chatId},
          excludedChatIds: const <int>{},
        ),
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.t(AppStringKeys.chatInfoCreateFolderFailed)),
        ),
      );
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
            title: AppStrings.t(AppStringKeys.chatInfoChatFolders),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loading ? null : _createFolder,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AppIcon(
                  HeroAppIcons.plus,
                  size: 24,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _body(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final c = context.colors;
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: c.textSecondary)),
      );
    }
    if (_folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.t(AppStringKeys.chatInfoNoFolders),
              style: TextStyle(color: c.textSecondary),
            ),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: _createFolder,
              child: Text(AppStrings.t(AppStringKeys.chatInfoNewFolder)),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < _folders.length; i++) ...[
                _folderRow(_folders[i]),
                if (i < _folders.length - 1)
                  const InsetDivider(leadingInset: 50),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            AppStrings.t(AppStringKeys.chatInfoDisableExplicitFolderWarning),
            style: TextStyle(fontSize: 13, color: c.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _folderRow(_FolderMembership item) {
    final c = context.colors;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            AppIcon(HeroAppIcons.folder, size: 22, color: AppTheme.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
            if (item.saving)
              const SizedBox(
                width: 28,
                height: 28,
                child: Padding(
                  padding: EdgeInsets.all(5),
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              )
            else
              Opacity(
                opacity: item.editable ? 1 : 0.45,
                child: CupertinoSwitch(
                  value: item.selected,
                  activeTrackColor: AppTheme.brand,
                  onChanged: item.editable
                      ? (value) => _toggle(item, value)
                      : null,
                ),
              ),
          ],
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
  bool isChannel = false;
  int memberCount = 0;
  String groupNumber = ''; // supergroup / basic-group id, shown as 群号
  String? username; // public @username (supergroups only)
  bool isPublic = false; // has a public username → searchable
  bool isPinned = false;
  bool isMuted = false;
  bool isArchived = false;
  int autoDeleteTime = 0;
  List<ChatMember> members = [];
  bool canInvite = false;
  bool canRemove = false;
  bool canManageGroup = false;
  bool canChangeAutoDelete = false;
  bool isMember = false; // confirmed member → may quit; false hides 退出
  bool _loaded = false;
  String? _notice;

  String? takeNotice() {
    final value = _notice;
    _notice = null;
    return value;
  }

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
    isChannel = kind == ChatKind.channel;
    isGroup = kind == ChatKind.group || kind == ChatKind.channel;
    canChangeAutoDelete = !isGroup;
    isMuted = ScopeNotificationSettings.shared.isMuted(chat);
    autoDeleteTime =
        chat.obj('message_auto_delete_time')?.integer('time') ??
        chat.integer('message_auto_delete_time') ??
        chat.integer('auto_delete_time') ??
        0;
    final type = chat.obj('type');
    if (type?.type == 'chatTypeSupergroup') {
      groupNumber = type?.int64('supergroup_id')?.toString() ?? '';
    } else if (type?.type == 'chatTypeBasicGroup') {
      groupNumber = type?.int64('basic_group_id')?.toString() ?? '';
    }
    for (final pos
        in chat.objects('positions') ?? const <Map<String, dynamic>>[]) {
      switch (pos.obj('list')?.type) {
        case 'chatListMain':
          isPinned = pos.boolean('is_pinned') ?? false;
        case 'chatListArchive':
          isArchived = (pos.int64('order') ?? 0) > 0;
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
        _applySelfStatus(sg.obj('status'), defaultInvite: false);
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
      _applySelfStatus(member.obj('status'), defaultInvite: defaultInvite);
    } catch (_) {
      canInvite = defaultInvite;
      canRemove = false;
      canManageGroup = false;
      canChangeAutoDelete = !isGroup;
      isMember = isMember && isChannel;
    }
    notifyListeners();
  }

  void _applySelfStatus(
    Map<String, dynamic>? status, {
    required bool defaultInvite,
  }) {
    switch (status?.type) {
      case 'chatMemberStatusCreator':
        isMember = true;
        canInvite = true;
        canRemove = true;
        canManageGroup = true;
        canChangeAutoDelete = true;
      case 'chatMemberStatusAdministrator':
        final rights = status?.obj('rights');
        isMember = true;
        canInvite = rights?.boolean('can_invite_users') ?? false;
        canRemove = rights?.boolean('can_restrict_members') ?? false;
        canManageGroup = true;
        canChangeAutoDelete = rights?.boolean('can_change_info') ?? false;
      case 'chatMemberStatusMember':
        isMember = true;
        canInvite = defaultInvite;
        canRemove = false;
        canManageGroup = false;
        canChangeAutoDelete = false;
      case 'chatMemberStatusRestricted':
        isMember = status?.boolean('is_member') ?? false;
        canInvite = defaultInvite;
        canRemove = false;
        canManageGroup = false;
        canChangeAutoDelete = false;
      case 'chatMemberStatusLeft':
      case 'chatMemberStatusBanned':
        isMember = false;
        canInvite = false;
        canRemove = false;
        canManageGroup = false;
        canChangeAutoDelete = false;
      default:
        isMember = false;
        canInvite = defaultInvite;
        canRemove = false;
        canManageGroup = false;
        canChangeAutoDelete = !isGroup;
    }
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
    unawaited(_setPinned(value));
  }

  Future<void> _setPinned(bool value) async {
    try {
      await TdClient.shared.query({
        '@type': 'toggleChatIsPinned',
        'chat_list': {'@type': 'chatListMain'},
        'chat_id': chatId,
        'is_pinned': value,
      });
    } catch (e) {
      isPinned = !value;
      _notice = _pinErrorNotice(e);
      notifyListeners();
    }
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

  void setArchived(bool value) {
    isArchived = value;
    notifyListeners();
    TdClient.shared
        .query({
          '@type': 'addChatToList',
          'chat_id': chatId,
          'chat_list': {'@type': value ? 'chatListArchive' : 'chatListMain'},
        })
        .catchError((_) {
          isArchived = !value;
          notifyListeners();
          return <String, dynamic>{};
        });
  }

  void setAutoDeleteTime(int seconds) {
    if (!canChangeAutoDelete) return;
    autoDeleteTime = seconds;
    notifyListeners();
    TdClient.shared.send({
      '@type': 'setChatMessageAutoDeleteTime',
      'chat_id': chatId,
      'message_auto_delete_time': {
        '@type': 'messageAutoDeleteTime',
        'time': seconds,
      },
    });
  }

  Future<void> clearHistory() async {
    await TdClient.shared.query({
      '@type': 'deleteChatHistory',
      'chat_id': chatId,
      'remove_from_chat_list': false,
      'revoke': false,
    });
    TdClient.shared.emitLocalUpdate({
      '@type': 'mithkaChatHistoryCleared',
      'chat_id': chatId,
    });
  }

  Future<void> leaveChat() async {
    await TdClient.shared.query({'@type': 'leaveChat', 'chat_id': chatId});
    isMember = false;
    notifyListeners();
    TdClient.shared.emitLocalUpdate({
      '@type': 'mithkaChatLeft',
      'chat_id': chatId,
    });
  }

  String actionErrorNotice(Object error) {
    final message = error is TdError ? error.message : error.toString();
    final text = message.trim();
    return text.isEmpty
        ? AppStrings.t(AppStringKeys.topicPostContentActionFailed)
        : '${AppStrings.t(AppStringKeys.topicPostContentActionFailed)}: $text';
  }

  String _pinErrorNotice(Object error) {
    final message = error is TdError ? error.message : error.toString();
    final text = message.trim();
    final normalized = text.toLowerCase().replaceAll('_', ' ');
    final hitPinned =
        normalized.contains('pin') ||
        normalized.contains('pinned') ||
        normalized.contains(AppStrings.t(AppStringKeys.chatInfoPin));
    final hitLimit =
        normalized.contains('limit') ||
        normalized.contains('too many') ||
        normalized.contains('too much') ||
        normalized.contains('many') ||
        normalized.contains('much') ||
        normalized.contains(AppStrings.t(AppStringKeys.chatInfoPinLimit));
    if (hitPinned && hitLimit) {
      return AppStrings.t(AppStringKeys.chatInfoPinLimitReachedError);
    }
    return text.isEmpty
        ? AppStrings.t(AppStringKeys.chatInfoPinFailed)
        : AppStrings.t(AppStringKeys.chatInfoPinFailedWithReason, {
            'value1': text,
          });
  }
}
