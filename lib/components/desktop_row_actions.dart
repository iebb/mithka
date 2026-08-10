import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../platform/adaptive_platform.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'app_interactive_surface.dart';

/// One command exposed by a native-desktop row context menu.
class DesktopRowAction {
  const DesktopRowAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onInvoke,
    this.color,
  });

  final String id;
  final String label;
  final AppIconData icon;
  final VoidCallback onInvoke;
  final Color? color;
}

/// Resolves a pointer-anchored row menu without letting it leave the overlay.
Offset desktopRowActionMenuTopLeft({
  required Offset anchor,
  required Size viewport,
  required Size menuSize,
  double margin = DesktopRowActionMenu.viewportMargin,
}) {
  final requested = anchor + const Offset(2, 2);
  final maxX = math.max(margin, viewport.width - menuSize.width - margin);
  final maxY = math.max(margin, viewport.height - menuSize.height - margin);
  return Offset(
    requested.dx.clamp(margin, maxX).toDouble(),
    requested.dy.clamp(margin, maxY).toDouble(),
  );
}

/// Opens the same app-owned command menu for a secondary click or the visible
/// trailing action button.
void showDesktopRowActionMenu(
  BuildContext context, {
  required Offset globalPosition,
  required List<DesktopRowAction> actions,
}) {
  if (!isDesktopTargetPlatform() || actions.isEmpty) return;

  final overlay = Overlay.of(context);
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  if (overlayBox == null || !overlayBox.hasSize) return;
  final anchor = overlayBox.globalToLocal(globalPosition);

  late final OverlayEntry entry;
  void dismiss() => entry.remove();

  entry = OverlayEntry(
    builder: (_) => DesktopRowActionMenu(
      anchor: anchor,
      actions: actions,
      onDismiss: dismiss,
    ),
  );
  overlay.insert(entry);
}

/// Adds native secondary-click behavior to a desktop row without changing its
/// primary action or its mobile implementation.
class DesktopRowActionRegion extends StatelessWidget {
  const DesktopRowActionRegion({
    super.key,
    required this.actions,
    required this.child,
  });

  final List<DesktopRowAction> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopTargetPlatform() || actions.isEmpty) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => showDesktopRowActionMenu(
        context,
        globalPosition: details.globalPosition,
        actions: actions,
      ),
      child: child,
    );
  }
}

/// Visible, focusable entry point for a row's desktop commands.
class DesktopRowActionButton extends StatelessWidget {
  const DesktopRowActionButton({
    super.key,
    required this.actions,
    required this.semanticLabel,
  });

  final List<DesktopRowAction> actions;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (buttonContext) => Tooltip(
      message: semanticLabel.l10n(context),
      child: AppInteractiveSurface(
        semanticLabel: semanticLabel.l10n(context),
        onTap: () {
          final box = buttonContext.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return;
          showDesktopRowActionMenu(
            buttonContext,
            globalPosition: box.localToGlobal(
              Offset(box.size.width, box.size.height),
            ),
            actions: actions,
          );
        },
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: AppIcon(
              HeroAppIcons.ellipsis,
              size: 18,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Compact pointer-anchored menu shared by desktop list rows.
class DesktopRowActionMenu extends StatefulWidget {
  const DesktopRowActionMenu({
    super.key,
    required this.anchor,
    required this.actions,
    required this.onDismiss,
  });

  static const double menuWidth = 218;
  static const double rowHeight = 38;
  static const double verticalPadding = 4;
  static const double viewportMargin = 8;

  final Offset anchor;
  final List<DesktopRowAction> actions;
  final VoidCallback onDismiss;

  @override
  State<DesktopRowActionMenu> createState() => _DesktopRowActionMenuState();
}

class _DesktopRowActionMenuState extends State<DesktopRowActionMenu> {
  final FocusNode _firstActionFocus = FocusNode(
    debugLabel: 'Desktop row action menu first command',
  );

  @override
  void initState() {
    super.initState();
    if (widget.actions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _firstActionFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _firstActionFocus.dispose();
    super.dispose();
  }

  void _select(DesktopRowAction action) {
    widget.onDismiss();
    action.onInvoke();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final resolvedWidth = math
            .min(
              DesktopRowActionMenu.menuWidth,
              math.max(
                0.0,
                viewport.width - DesktopRowActionMenu.viewportMargin * 2,
              ),
            )
            .toDouble();
        final menuSize = Size(
          resolvedWidth,
          DesktopRowActionMenu.verticalPadding * 2 +
              DesktopRowActionMenu.rowHeight * widget.actions.length,
        );
        final topLeft = desktopRowActionMenuTopLeft(
          anchor: widget.anchor,
          viewport: viewport,
          menuSize: menuSize,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('desktop-row-action-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              onSecondaryTap: widget.onDismiss,
              child: const ColoredBox(color: Colors.transparent),
            ),
            Positioned(
              left: topLeft.dx,
              top: topLeft.dy,
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.escape):
                      widget.onDismiss,
                },
                child: FocusTraversalGroup(
                  child: Container(
                    key: const ValueKey('desktop-row-action-menu'),
                    width: resolvedWidth,
                    decoration: BoxDecoration(
                      color: c.card,
                      border: Border.all(color: c.divider, width: 0.5),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: DesktopRowActionMenu.verticalPadding,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (
                            var index = 0;
                            index < widget.actions.length;
                            index++
                          )
                            _DesktopRowActionItem(
                              key: ValueKey(
                                'desktop-row-action-${widget.actions[index].id}',
                              ),
                              action: widget.actions[index],
                              focusNode: index == 0 ? _firstActionFocus : null,
                              onTap: () => _select(widget.actions[index]),
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

class _DesktopRowActionItem extends StatelessWidget {
  const _DesktopRowActionItem({
    super.key,
    required this.action,
    required this.onTap,
    this.focusNode,
  });

  final DesktopRowAction action;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final label = action.label.l10n(context);
    final foreground = action.color ?? context.colors.textPrimary;
    return AppInteractiveSurface(
      semanticLabel: label,
      focusNode: focusNode,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: DesktopRowActionMenu.rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              SizedBox(
                width: AppMetric.menuIconSlot,
                child: AppIcon(action.icon, size: 18, color: foreground),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextSize.callout,
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
