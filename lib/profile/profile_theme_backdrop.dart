import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../chat/chat_wallpaper.dart';
import '../theme/app_theme.dart';

ChatWallpaper? selectProfileThemeWallpaper({
  required bool themingEnabled,
  required ChatWallpaper? defaultWallpaper,
  required ChatWallpaper? cloudThemeWallpaper,
  required ChatWallpaper? globalThemeWallpaper,
}) {
  if (!themingEnabled) return null;
  return defaultWallpaper ?? cloudThemeWallpaper ?? globalThemeWallpaper;
}

class ProfileThemeBackdrop extends StatelessWidget {
  const ProfileThemeBackdrop({super.key, required this.wallpaper});

  final ChatWallpaper? wallpaper;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Transform.scale(
              scale: 1.12,
              child: ChatWallpaperBackground(
                wallpaper: wallpaper,
                fallbackColor: colors.background,
                brightness: brightness,
                imageScrim: colors.background.withValues(alpha: 0),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          DecoratedBox(
            key: const ValueKey('profileThemeBackdropOverlay'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.background.withValues(alpha: 0.60),
                  colors.card.withValues(alpha: 0.76),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
