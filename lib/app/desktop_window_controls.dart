import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'desktop_window_controls_stub.dart'
    if (dart.library.io) 'desktop_window_controls_io.dart'
    as implementation;

bool get usesFlutterDesktopWindowControls =>
    implementation.usesFlutterDesktopWindowControls;

Future<void> configurePrimaryDesktopWindowChrome() =>
    implementation.configurePrimaryDesktopWindowChrome();

Future<void> minimizePrimaryDesktopWindow() =>
    implementation.minimizePrimaryDesktopWindow();

Future<void> togglePrimaryDesktopWindowMaximized() =>
    implementation.togglePrimaryDesktopWindowMaximized();

Future<void> closePrimaryDesktopWindow() =>
    implementation.closePrimaryDesktopWindow();

/// Minimize / maximize / close for the platforms where Mithka draws its own
/// title bar (Windows and Linux; macOS keeps its native controls).
class DesktopWindowControls extends StatelessWidget {
  const DesktopWindowControls({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _CaptionButton(
        key: const ValueKey('desktop-window-minimize'),
        icon: HeroAppIcons.minus,
        label: AppStringKeys.desktopWindowMinimize.l10n(context),
        onTap: minimizePrimaryDesktopWindow,
      ),
      _CaptionButton(
        key: const ValueKey('desktop-window-maximize'),
        icon: HeroAppIcons.square,
        label: AppStringKeys.desktopWindowMaximizeRestore.l10n(context),
        onTap: togglePrimaryDesktopWindowMaximized,
      ),
      _CaptionButton(
        key: const ValueKey('desktop-window-close'),
        icon: HeroAppIcons.xmark,
        label: AppStringKeys.desktopWindowClose.l10n(context),
        onTap: closePrimaryDesktopWindow,
        isClose: true,
      ),
    ],
  );
}

/// A single caption button.
///
/// Deliberately not built on AppInteractiveSurface: that carries a press
/// ripple which animates outward past the button's own bounds, so hovering
/// close made it balloon across the title bar. A caption button wants a flat,
/// fixed rectangle — the shape every desktop draws — so it paints its own
/// hover instead.
class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isClose = false,
  });

  /// Matches the caption metrics Windows uses, and stays fixed in every state.
  static const width = 46.0;
  static const height = 40.0;

  /// Windows' close-button red, and its pressed shade.
  static const closeHover = Color(0xFFC42B1C);
  static const closePressed = Color(0xFFB2271A);

  final AppIconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  Color _background(AppColors colors) {
    if (widget.isClose && (_hovered || _pressed)) {
      return _pressed ? _CaptionButton.closePressed : _CaptionButton.closeHover;
    }
    if (_pressed) return colors.textPrimary.withValues(alpha: 0.10);
    if (_hovered) return colors.textPrimary.withValues(alpha: 0.06);
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The glyph has to read against the red, not against the title bar.
    final iconColor = widget.isClose && (_hovered || _pressed)
        ? const Color(0xFFFFFFFF)
        : colors.textSecondary;

    final button = MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          setState(() => _pressed = false);
          unawaited(widget.onTap());
        },
        child: SizedBox(
          width: _CaptionButton.width,
          height: _CaptionButton.height,
          child: ColoredBox(
            color: _background(colors),
            child: Center(
              child: AppIcon(widget.icon, size: 16, color: iconColor),
            ),
          ),
        ),
      ),
    );
    // MaterialApp.builder places the desktop frame above the Navigator's
    // LookupBoundary, so its caption buttons do not always have an Overlay.
    // RawTooltip asserts during build in that configuration on current
    // Flutter. The semantics label still exposes the native action; only add
    // the visual tooltip when it has somewhere valid to float.
    final overlay = Overlay.maybeOf(context);
    return Semantics(
      label: widget.label,
      button: true,
      excludeSemantics: true,
      child: overlay == null
          ? button
          : Tooltip(message: widget.label, child: button),
    );
  }
}
