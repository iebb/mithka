//
//  chat_folder_tab_menu.dart
//
//  The folder strip's action sheet and folder-order sheet. A long press on a
//  mobile folder tab and a secondary click on the desktop folder rail open the
//  same command list for the folder under the pointer.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../settings/chat_folder_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// One command in a folder tab's action sheet.
class ChatFolderMenuAction {
  const ChatFolderMenuAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  /// Stable suffix for the row's key, e.g. `edit` or `mark-read`.
  final String key;

  /// Already localized label.
  final String label;
  final AppIconData icon;
  final VoidCallback onSelected;
}

/// Shows [actions] for the folder named [title] in a single sheet.
///
/// Both the mobile tab strip's long press and the desktop rail's secondary
/// click call this, so a folder offers the same commands on either surface.
Future<void> showChatFolderActionSheet({
  required BuildContext context,
  required String title,
  required List<ChatFolderMenuAction> actions,
}) {
  if (actions.isEmpty) return Future<void>.value();
  return showAppModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final c = sheetContext.colors;
      return SafeArea(
        child: Container(
          key: const ValueKey('chat-folder-action-sheet'),
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final action in actions) _ChatFolderMenuRow(action: action),
            ],
          ),
        ),
      );
    },
  );
}

class _ChatFolderMenuRow extends StatelessWidget {
  const _ChatFolderMenuRow({required this.action});

  final ChatFolderMenuAction action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: action.label,
      child: GestureDetector(
        key: ValueKey('chat-folder-action-${action.key}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).pop();
          action.onSelected();
        },
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              AppIcon(action.icon, size: 19, color: c.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
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
}) => showAppModalSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => ChatFolderReorderSheet(
    folders: folders,
    mainListPosition: mainListPosition,
    service: service,
    canSave: canSave,
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
  });

  final List<ChatFolderRecord> folders;
  final int mainListPosition;
  final ChatFolderService service;

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
    _mainListPosition = widget.mainListPosition;
    _entries = folderOrderEntries(widget.folders, _mainListPosition);
  }

  bool get _ownerIsCurrent => widget.canSave?.call() ?? true;

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_saving || oldIndex == newIndex) return;
    final previousEntries = _entries;
    final previousPosition = _mainListPosition;
    final result = reorderFolderEntries(_entries, oldIndex, newIndex);
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
                  return ReorderableDragStartListener(
                    key: ValueKey(key),
                    index: index,
                    enabled: !_saving,
                    child: _reorderRow(context, folder),
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

  Widget _reorderRow(BuildContext context, ChatFolderRecord? folder) {
    final c = context.colors;
    return Container(
      height: 52,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          AppIcon(HeroAppIcons.bars, size: 19, color: c.textTertiary),
          const SizedBox(width: 10),
          AppIcon(
            folder == null ? HeroAppIcons.inbox : HeroAppIcons.folder,
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
