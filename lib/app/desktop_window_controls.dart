import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
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

class DesktopWindowControls extends StatelessWidget {
  const DesktopWindowControls({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _button(
        context,
        key: const ValueKey('desktop-window-minimize'),
        icon: HeroAppIcons.minus,
        label: AppStringKeys.desktopWindowMinimize.l10n(context),
        onTap: minimizePrimaryDesktopWindow,
      ),
      _button(
        context,
        key: const ValueKey('desktop-window-maximize'),
        icon: HeroAppIcons.square,
        label: AppStringKeys.desktopWindowMaximizeRestore.l10n(context),
        onTap: togglePrimaryDesktopWindowMaximized,
      ),
      _button(
        context,
        key: const ValueKey('desktop-window-close'),
        icon: HeroAppIcons.xmark,
        label: AppStringKeys.desktopWindowClose.l10n(context),
        onTap: closePrimaryDesktopWindow,
      ),
    ],
  );

  Widget _button(
    BuildContext context, {
    required Key key,
    required AppIconData icon,
    required String label,
    required Future<void> Function() onTap,
  }) => Tooltip(
    message: label,
    child: AppInteractiveSurface(
      key: key,
      semanticLabel: label,
      onTap: () => unawaited(onTap()),
      borderRadius: BorderRadius.circular(5),
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: AppIcon(icon, size: 16, color: context.colors.textSecondary),
        ),
      ),
    ),
  );
}
