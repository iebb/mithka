//
//  app_anchored_menu.dart
//
//  The app's tab-anchored action menu: a narrow popup that hangs off the
//  pressed control (folder tab, topic tab, in-chat activity pill) instead of
//  a wide bottom sheet. One implementation keeps every anchored menu on the
//  same chrome, placement math and entrance animation.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/theme/app_motion.dart';
import 'package:mithka/theme/app_theme.dart';

/// One command in an anchored popup menu.
class AppMenuAction {
  const AppMenuAction({
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

  /// Destructive commands render in the danger color, like the reference client's red
  /// Delete item in a tab's popup.
  final bool destructive;
}

/// Menu chrome metrics shared with the placement math and tests: 36px rows on
/// a compact 196px column with an 8px vertical inset, mirroring the reference client's
/// ActionBarPopupWindow column.
const double appAnchoredMenuRowHeight = 36;
const double appAnchoredMenuVerticalInset = 8;
const double appAnchoredMenuMinWidth = 196;

/// The optional title block above the rows: 8px top inset, a 13px semibold
/// line, 6px below.
const double appAnchoredMenuTitleHeight = 30;

/// The dim layer's opacity, the reference client's tab ItemOptions value
/// (`setDimAlpha(0x60)` on DialogsActivity's filter tabs).
const double appAnchoredMenuDimOpacity = 0x60 / 0xff;

/// The menu's entrance mirrors the reference client's PopupContextAnimation: fade in
/// 150ms while scaling 95%→100% over 200ms with a light overshoot from the
/// corner nearest the pressed control. Exit reverses both at the same tempo.
const Duration _menuScaleDuration = Duration(milliseconds: 200);

/// Where the 150ms fade and dim tracks end inside the 200ms entrance.
const double _menuFastTrack = 150 / 200;

const Curve _menuGrowCurve = Cubic(0.34, 1.56, 0.64, 1.0); // easeOutBack

@visibleForTesting
double appAnchoredMenuHeightFor(int actionCount, {bool hasTitle = false}) =>
    appAnchoredMenuVerticalInset * 2 +
    (hasTitle ? appAnchoredMenuTitleHeight : 0) +
    math.max(0, actionCount) * appAnchoredMenuRowHeight;

/// Where a menu of [menuSize] opens for a control at [anchor], staying inside
/// the viewport: below the control when it fits, above when it does not,
/// horizontally clamped with the menu's left edge near the control like
/// the reference client's ItemOptions with Gravity.LEFT.
@visibleForTesting
Offset appAnchoredMenuOriginFor({
  required Rect anchor,
  required Size viewport,
  required Size menuSize,
  double margin = 8,
  double? gap,
}) {
  // [margin] keeps the menu off the viewport edges; [gap] is the distance to
  // the pressed control itself, so a caller can hug a tab strip without also
  // pinning the menu to the screen edge.
  final controlGap = gap ?? margin;
  final maxLeft = math.max(margin, viewport.width - menuSize.width - margin);
  final left = anchor.left.clamp(margin, maxLeft).toDouble();
  final belowTop = anchor.bottom + controlGap;
  final aboveTop = anchor.top - controlGap - menuSize.height;
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

/// Shows [actions] anchored to [anchor] — the pressed tab or pill.
///
/// A long press on a folder tab, a topic tab or an in-chat activity pill all
/// open this same command list. The menu hangs off the pressed control like
/// the reference client's ItemOptions popup instead of a bottom sheet, so it reads as
/// acting on that control.
Future<void> showAppAnchoredMenu({
  required BuildContext context,
  required Rect anchor,
  required List<AppMenuAction> actions,
  String? header,
  double gap = 8,
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

  late final AppAnchoredMenuPopup menu;
  menu = AppAnchoredMenuPopup(
    anchor: anchorInOverlay,
    gap: gap,
    header: header,
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
class AppAnchoredMenuPopup extends StatefulWidget {
  AppAnchoredMenuPopup({
    super.key,
    required this.anchor,
    required this.actions,
    required this.onDismissed,
    this.header,
    this.gap = 8,
  });

  /// The pressed control's rect in the enclosing overlay's coordinates.
  final Rect anchor;

  /// Distance from the control to the menu's near edge. A tab strip passes a
  /// tighter gap so its menu hugs the bar instead of floating below it.
  final double gap;

  /// Optional caption naming the surface the menu acts on.
  final String? header;
  final List<AppMenuAction> actions;
  final VoidCallback onDismissed;

  /// The overlay entry this menu renders inside; assigned by
  /// [showAppAnchoredMenu] so a dismissal can remove it exactly once.
  OverlayEntry? entry;

  @override
  State<AppAnchoredMenuPopup> createState() => _AppAnchoredMenuPopupState();
}

class _AppAnchoredMenuPopupState extends State<AppAnchoredMenuPopup>
    with TickerProviderStateMixin {
  final FocusNode _menuFocus = FocusNode(debugLabel: 'Anchored popup menu');

  bool _open = true;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _menuScaleDuration,
  );

  /// The scrim's fade, the menu's fade, and the menu's grow share one
  /// controller so all three run in lockstep on the way in and out.
  late final Animation<double> _dim = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, _menuFastTrack, curve: AppMotion.standard),
  );
  late final Animation<double> _menuFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, _menuFastTrack),
  );
  late final Animation<double> _menuScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 1, curve: _menuGrowCurve),
  );

  bool _reducedSeen = false;

  bool get _hasHeader => (widget.header ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menuFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reducedSeen) return;
    _reducedSeen = true;
    if (AppMotion.isReduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    // Torn down with the menu still open (its host route disappeared):
    // report the dismissal so the caller's future completes.
    if (_open) widget.onDismissed();
    _menuFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void dismiss() {
    if (!mounted || !_open) return;
    _open = false;
    if (!AppMotion.isReduced(context) &&
        _controller.status.isForwardOrCompleted) {
      unawaited(_controller.reverse().whenComplete(widget.onDismissed));
    } else {
      widget.onDismissed();
    }
  }

  void _select(AppMenuAction action) {
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
          appAnchoredMenuMinWidth,
          appAnchoredMenuHeightFor(widget.actions.length, hasTitle: _hasHeader),
        );
        final origin = appAnchoredMenuOriginFor(
          anchor: widget.anchor,
          viewport: viewport,
          menuSize: menuSize,
          gap: widget.gap,
        );
        // The menu grows from the corner nearest the pressed control,
        // matching the reference client's pivotX/pivotY on the control-adjacent corner:
        // below the control grows from its top-left corner, a flip above
        // grows from the bottom edge nearest the control's horizontal side.
        final growsFromBottom = origin.dy > widget.anchor.bottom;
        final growsFromRight = origin.dx > widget.anchor.left;
        final scaleAlignment = Alignment(
          growsFromRight ? -1 : 1,
          growsFromBottom ? -1 : 1,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('app-anchored-menu-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: dismiss,
              onSecondaryTap: dismiss,
              child: FadeTransition(
                opacity: _dim,
                child: ColoredBox(
                  key: const ValueKey('app-anchored-menu-scrim'),
                  color: Colors.black.withValues(
                    alpha: appAnchoredMenuDimOpacity,
                  ),
                ),
              ),
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
                    child: FadeTransition(
                      opacity: _menuFade,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.95,
                          end: 1,
                        ).animate(_menuScale),
                        alignment: scaleAlignment,
                        child: Container(
                          key: const ValueKey('app-anchored-menu'),
                          width: menuSize.width,
                          padding: const EdgeInsets.symmetric(
                            vertical: appAnchoredMenuVerticalInset,
                          ),
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
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
                              if (_hasHeader)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    6,
                                  ),
                                  child: Text(
                                    widget.header!,
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
                                _AppAnchoredMenuRow(
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
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AppAnchoredMenuRow extends StatelessWidget {
  const _AppAnchoredMenuRow({required this.action, required this.onTap});

  final AppMenuAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final foreground = action.destructive
        ? const Color(0xFFFF6961)
        : c.textPrimary;
    return AppInteractiveSurface(
      key: ValueKey('app-anchored-menu-${action.key}'),
      semanticLabel: action.label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: appAnchoredMenuRowHeight,
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
