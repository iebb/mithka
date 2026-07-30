import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'app_press_ripple.dart';

/// Project-owned pointer, keyboard, focus, and touch behavior for controls.
///
/// The visual child remains entirely app-owned. This widget only adds the
/// interaction contract desktop users expect while retaining touch ripple,
/// long-press, and secondary-click support.
class AppInteractiveSurface extends StatefulWidget {
  const AppInteractiveSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.semanticLabel,
    this.semanticValue,
    this.selected,
    this.toggled,
    this.checked,
    this.isButton,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = BorderRadius.zero,
    this.mouseCursor = SystemMouseCursors.click,
    this.showHover = true,
    this.showFocusRing = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final String? semanticLabel;
  final String? semanticValue;
  final bool? selected;
  final bool? toggled;
  final bool? checked;
  final bool? isButton;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final BorderRadiusGeometry borderRadius;
  final MouseCursor mouseCursor;
  final bool showHover;
  final bool showFocusRing;

  @override
  State<AppInteractiveSurface> createState() => _AppInteractiveSurfaceState();
}

class _AppInteractiveSurfaceState extends State<AppInteractiveSurface> {
  bool _hovered = false;
  bool _focused = false;

  bool get _canActivate => widget.enabled && widget.onTap != null;
  bool get _hasControlContract =>
      widget.onTap != null ||
      widget.onLongPress != null ||
      widget.onSecondaryTap != null ||
      widget.semanticLabel != null ||
      widget.semanticValue != null ||
      widget.selected != null ||
      widget.toggled != null ||
      widget.checked != null ||
      widget.isButton != null;
  bool get _isInteractive =>
      widget.enabled &&
      (widget.onTap != null ||
          widget.onLongPress != null ||
          widget.onSecondaryTap != null);

  @override
  Widget build(BuildContext context) {
    if (!_hasControlContract) return widget.child;

    final colors = context.colors;
    final overlayColor = _focused
        ? colors.linkBlue.withValues(alpha: 0.07)
        : _hovered && widget.showHover
        ? colors.textPrimary.withValues(alpha: 0.045)
        : Colors.transparent;
    final focusBorder = _focused && widget.showFocusRing
        ? Border.all(color: colors.linkBlue, width: 2)
        : null;

    final content = _isInteractive
        ? AppPressRipple(
            borderRadius: widget.borderRadius,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: _canActivate ? widget.onTap : null,
              onLongPress: widget.onLongPress,
              onSecondaryTap: widget.onSecondaryTap,
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  widget.child,
                  if (overlayColor.a > 0 || focusBorder != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: AppMotion.duration(
                            context,
                            AppMotion.quick,
                          ),
                          curve: AppMotion.standard,
                          decoration: BoxDecoration(
                            color: overlayColor,
                            borderRadius: widget.borderRadius,
                            border: focusBorder,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          )
        : widget.child;

    return Semantics(
      label: widget.semanticLabel,
      value: widget.semanticValue,
      excludeSemantics: widget.semanticLabel != null,
      button:
          widget.isButton ?? (widget.toggled == null && widget.checked == null),
      enabled: widget.enabled,
      selected: widget.selected,
      toggled: widget.toggled,
      checked: widget.checked,
      onTap: _canActivate ? widget.onTap : null,
      child: FocusableActionDetector(
        enabled: _canActivate,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        mouseCursor: _isInteractive ? widget.mouseCursor : MouseCursor.defer,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
              ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
              ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_canActivate) widget.onTap!();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: content,
      ),
    );
  }
}
