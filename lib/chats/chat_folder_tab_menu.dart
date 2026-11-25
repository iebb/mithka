//
//  chat_folder_tab_menu.dart
//
//  The folder strip's reorder sheet. The tab's action menu lives in
//  components/app_anchored_menu.dart, shared with topic tabs and the in-chat
//  activity pills.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/chat_folder_icons.dart';
import '../components/toast.dart';
import '../settings/chat_folder_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Shows [folders] as a drag order sheet with the main chat list standing in
/// as an "All chats" row.
///
/// [canSave] is consulted immediately before each save; answering false reverts
/// the drop without writing, which is what a sheet whose account was switched
/// out from under it needs.
Future<void> showChatFolderReorderSheet({
  required BuildContext context,
  required List<ChatFolderRecord> folders,
  required int mainListPosition,
  required ChatFolderService service,
  bool Function()? canSave,
  bool canMoveMainList = true,
  ValueChanged<int>? onMainListPositionSaved,
}) => showAppModalSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => ChatFolderReorderSheet(
    folders: folders,
    mainListPosition: mainListPosition,
    service: service,
    canSave: canSave,
    canMoveMainList: canMoveMainList,
    onMainListPositionSaved: onMainListPositionSaved,
  ),
);

/// Reorders every folder plus the main chat list and saves each drop.
///
/// The main list is drawn as an "All chats" row at its current
/// `main_chat_list_position`; a failed save restores the previous order and
/// shows the service's reason.
class ChatFolderReorderSheet extends StatefulWidget {
  const ChatFolderReorderSheet({
    super.key,
    required this.folders,
    required this.mainListPosition,
    required this.service,
    this.canSave,
    this.canMoveMainList = true,
    this.onMainListPositionSaved,
  });

  final List<ChatFolderRecord> folders;
  final int mainListPosition;
  final ChatFolderService service;

  /// Whether the main list may be moved at all. Only a Premium account may
  /// set `main_chat_list_position`, so without the server entitlement or the
  /// local-premium overlay the "All chats" row is pinned and carries no drag
  /// grip — the sheet must not offer an edit the account cannot save.
  final bool canMoveMainList;

  /// Called after a successful save with the newly chosen main-list position.
  /// The chat list uses this to remember a local-premium position, which
  /// TDLib will have clamped back to 0.
  final ValueChanged<int>? onMainListPositionSaved;

  /// Checked immediately before every save. The sheet outlives the surface
  /// that opened it, so a run must not write into an account that has since
  /// been replaced; answering false reverts the row like a failed save.
  final bool Function()? canSave;

  @override
  State<ChatFolderReorderSheet> createState() => _ChatFolderReorderSheetState();
}

class _ChatFolderReorderSheetState extends State<ChatFolderReorderSheet> {
  late List<ChatFolderRecord?> _entries;
  late int _mainListPosition;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mainListPosition = widget.canMoveMainList ? widget.mainListPosition : 0;
    _entries = folderOrderEntries(widget.folders, _mainListPosition);
  }

  bool get _ownerIsCurrent => widget.canSave?.call() ?? true;

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_saving || oldIndex == newIndex) return;
    final previousEntries = _entries;
    final previousPosition = _mainListPosition;
    final result = reorderFolderEntries(
      _entries,
      oldIndex,
      newIndex,
      moveMainList: widget.canMoveMainList,
    );
    setState(() {
      _entries = folderOrderEntries(
        result.folders,
        result.mainChatListPosition,
      );
      _mainListPosition = result.mainChatListPosition;
      _saving = true;
    });
    try {
      if (!_ownerIsCurrent) {
        // The account this sheet belongs to is gone; there is no one to
        // report to and nothing to save. Just put the rows back.
        if (mounted) {
          setState(() {
            _entries = previousEntries;
            _mainListPosition = previousPosition;
            _saving = false;
          });
        }
        return;
      }
      await widget.service.reorder(
        result.folders.map((folder) => folder.id).toList(),
        result.mainChatListPosition,
      );
      if (widget.canMoveMainList) {
        widget.onMainListPositionSaved?.call(result.mainChatListPosition);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries = previousEntries;
        _mainListPosition = previousPosition;
      });
      showToast(
        context,
        AppStrings.t(
          AppStringKeys.chatFolderManagementCouldnTReorderFoldersValue1,
          {'value1': error},
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = (MediaQuery.sizeOf(context).height * 0.62).clamp(
      280.0,
      560.0,
    );
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('chat-folder-reorder-sheet'),
        height: height,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.t(
                        AppStringKeys.chatFolderManagementReorderFolders,
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('chat-folder-reorder-close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AppIcon(
                        HeroAppIcons.xmark,
                        size: 20,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppStrings.t(AppStringKeys.chatFolderManagementReorderHint),
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ),
            ),
            Expanded(
              // The widgets-layer list, not ReorderableListView: Material's
              // list decorates the drag with an elevation proxy and inserts
              // its own drag handles. Here the sheet supplies the proxy and
              // the row carries the drag listener.
              child: ReorderableList(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: _entries.length,
                onReorderItem: _reorder,
                proxyDecorator: _reorderProxyDecorator,
                itemBuilder: (context, index) {
                  final folder = _entries[index];
                  final key = folder == null
                      ? 'chat-folder-order-main'
                      : 'chat-folder-order-${folder.id}';
                  return _reorderRow(
                    context,
                    folder,
                    key: ValueKey(key),
                    index: index,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The drop proxy: the dragged row at the lift scale with the sheet's own
  /// shadow, painted with owned primitives so no Material surface carries
  /// elevation or a ripple into the drag.
  Widget _reorderProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) => AnimatedBuilder(
    animation: animation,
    builder: (context, row) {
      final lift = Curves.easeOut.transform(animation.value);
      return DecoratedBox(
        key: const ValueKey('chat-folder-reorder-proxy'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: AppTheme.brand.withValues(alpha: 0.10 * lift),
              blurRadius: 14 * lift,
              offset: Offset(0, 6 * lift),
            ),
          ],
        ),
        child: Transform.scale(scale: 1 + 0.03 * lift, child: row),
      );
    },
    child: child,
  );

  /// The row itself is not a drag source: wrapping the whole row in a
  /// [ReorderableDragStartListener] made every touch on the list start a
  /// reorder, so a long folder list could not be scrolled to the folders
  /// below the fold. Only the grip starts the drag; the rest of the row
  /// stays available to the scroll view.
  Widget _reorderRow(
    BuildContext context,
    ChatFolderRecord? folder, {
    required int index,
    Key? key,
  }) {
    final c = context.colors;
    return Container(
      key: key,
      height: 52,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          if (folder == null && !widget.canMoveMainList)
            // Non-Premium: All chats is a fixed row. A lock instead of the
            // grip says why it cannot be dragged.
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
              child: AppIcon(
                HeroAppIcons.lock,
                size: 19,
                color: c.textTertiary,
              ),
            )
          else
            ReorderableDragStartListener(
              key: ValueKey('chat-folder-order-grip-${folder?.id ?? 'main'}'),
              index: index,
              enabled: !_saving,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
                child: AppIcon(
                  HeroAppIcons.bars,
                  size: 19,
                  color: c.textTertiary,
                ),
              ),
            ),
          ChatFolderIcon(
            folder == null ? 'All' : folder.draft.iconName,
            size: 21,
            color: folder == null ? AppTheme.brand : c.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              folder == null
                  ? AppStrings.t(AppStringKeys.chatFolderManagementAllChats)
                  : folder.title.l10n(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
