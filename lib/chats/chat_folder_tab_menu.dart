//
//  chat_folder_tab_menu.dart
//
//  The folder strip's action sheet and folder-order sheet. A long press on a
//  mobile folder tab and a secondary click on the desktop folder rail open the
//  same command list for the folder under the pointer.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../settings/chat_folder_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// One command in a folder tab's popup menu.
class ChatFolderMenuAction {
  const ChatFolderMenuAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  /// Stable suffix for the row's key, e.g. `edit` or `mark-read`.
  final String key;

  /// Already localized label.
  final String label;
  final AppIconData icon;
  final VoidCallback onSelected;

  /// Destructive commands render in the danger color, like exteraless's red
  /// Delete item in a folder tab's popup.
  final bool destructive;
}

/// Menu chrome metrics shared with the placement math and tests: rows are
/// 44px on a compact width that hugs its longest label, with an 8px vertical
/// inset, mirroring exteraless's ActionBarPopupWindow column.
const double chatFolderMenuRowHeight = 44;
const double chatFolderMenuVerticalInset = 8;
const double chatFolderMenuMinWidth = 196;

@visibleForTesting
double chatFolderMenuHeightFor(int actionCount) =>
    chatFolderMenuVerticalInset * 2 +
    math.max(0, actionCount) * chatFolderMenuRowHeight;

/// Where a menu of [menuSize] opens for a tab at [anchor], staying inside the
/// viewport: below the tab when it fits, above when it does not, horizontally
/// clamped with the menu's left edge near the tab like exteraless's
/// ItemOptions with Gravity.LEFT.
@visibleForTesting
Offset chatFolderMenuOriginFor({
  required Rect anchor,
  required Size viewport,
  required Size menuSize,
  double margin = 8,
}) {
  final maxLeft = math.max(margin, viewport.width - menuSize.width - margin);
  final left = anchor.left.clamp(margin, maxLeft).toDouble();
  final belowTop = anchor.bottom + margin;
  final aboveTop = anchor.top - margin - menuSize.height;
  final double top;
  if (belowTop + menuSize.height <= viewport.height - margin) {
    top = belowTop;
  } else if (aboveTop >= margin) {
    top = aboveTop;
  } else {
    // Neither side fits (menu taller than the viewport): pin it to the top
    // and let the column clip inside the viewport-sized stack.
    top = margin;
  }
  return Offset(left, top);
}

/// Shows [actions] for the folder named [title] as a popup anchored to the
/// folder tab.
///
/// A long press on a mobile folder tab and a secondary click on the desktop
/// folder rail open the same command list. The menu hangs off the pressed
/// tab like exteraless's ItemOptions popup instead of a bottom sheet, so it
/// reads as acting on that folder.
Future<void> showChatFolderPopupMenu({
  required BuildContext context,
  required Rect anchor,
  required String title,
  required List<ChatFolderMenuAction> actions,
}) {
  if (actions.isEmpty) return Future<void>.value();
  final overlay = Overlay.of(context, rootOverlay: true);
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  if (overlayBox == null || !overlayBox.hasSize) {
    return Future<void>.value();
  }
  final anchorInOverlay = Rect.fromPoints(
    overlayBox.globalToLocal(anchor.topLeft),
    overlayBox.globalToLocal(anchor.bottomRight),
  );
  final completer = Completer<void>();
  var removed = false;
  void removeEntry(OverlayEntry? entry) {
    if (removed) return;
    removed = true;
    entry?.remove();
  }

  late final ChatFolderPopupMenu menu;
  menu = ChatFolderPopupMenu(
    anchor: anchorInOverlay,
    title: title,
    actions: actions,
    onDismissed: () {
      removeEntry(menu.entry);
      completer.complete();
    },
  );
  final entry = OverlayEntry(builder: (_) => menu);
  menu.entry = entry;
  overlay.insert(entry);
  return completer.future;
}

/// An app-owned anchored popup: a barrier that eats taps and Escape, one
/// compact menu card, and rows that pop the menu before invoking their
/// command.
// The mutable `entry` link is assigned by the factory right after
// construction, so this widget deliberately forgoes @immutable.
// ignore: must_be_immutable
class ChatFolderPopupMenu extends StatefulWidget {
  ChatFolderPopupMenu({
    super.key,
    required this.anchor,
    required this.title,
    required this.actions,
    required this.onDismissed,
  });

  /// The pressed tab's rect in the enclosing overlay's coordinates.
  final Rect anchor;
  final String title;
  final List<ChatFolderMenuAction> actions;
  final VoidCallback onDismissed;

  /// The overlay entry this menu renders inside; assigned by
  /// [showChatFolderPopupMenu] so a dismissal can remove it exactly once.
  OverlayEntry? entry;

  @override
  State<ChatFolderPopupMenu> createState() => _ChatFolderPopupMenuState();
}

class _ChatFolderPopupMenuState extends State<ChatFolderPopupMenu> {
  final FocusNode _menuFocus = FocusNode(debugLabel: 'Chat folder popup menu');

  bool _open = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menuFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Torn down with the menu still open (its host route disappeared):
    // report the dismissal so the caller's future completes.
    if (_open) widget.onDismissed();
    _menuFocus.dispose();
    super.dispose();
  }

  void dismiss() {
    if (!mounted || !_open) return;
    _open = false;
    widget.onDismissed();
  }

  void _select(ChatFolderMenuAction action) {
    final invoke = action.onSelected;
    dismiss();
    invoke();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final menuSize = Size(
          chatFolderMenuMinWidth,
          chatFolderMenuHeightFor(widget.actions.length),
        );
        final origin = chatFolderMenuOriginFor(
          anchor: widget.anchor,
          viewport: viewport,
          menuSize: menuSize,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('chat-folder-action-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: dismiss,
              onSecondaryTap: dismiss,
              child: const ColoredBox(color: Colors.transparent),
            ),
            Positioned(
              left: origin.dx,
              top: origin.dy,
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.escape): dismiss,
                },
                child: FocusTraversalGroup(
                  child: Focus(
                    focusNode: _menuFocus,
                    child: Container(
                      key: const ValueKey('chat-folder-action-menu'),
                      width: menuSize.width,
                      padding: const EdgeInsets.symmetric(
                        vertical: chatFolderMenuVerticalInset,
                      ),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(color: c.divider, width: 0.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                          for (final action in widget.actions)
                            _ChatFolderMenuRow(
                              action: action,
                              onTap: () => _select(action),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChatFolderMenuRow extends StatelessWidget {
  const _ChatFolderMenuRow({required this.action, required this.onTap});

  final ChatFolderMenuAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final foreground = action.destructive
        ? const Color(0xFFFF6961)
        : c.textPrimary;
    return AppInteractiveSurface(
      key: ValueKey('chat-folder-action-${action.key}'),
      semanticLabel: action.label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: chatFolderMenuRowHeight - chatFolderMenuVerticalInset,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AppIcon(action.icon, size: 19, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: foreground,
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
