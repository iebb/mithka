import 'package:flutter/widgets.dart';

import '../chat/chat_wallpaper.dart';
import '../components/app_confirm_dialog.dart';
import '../l10n/app_localizations.dart';
import 'app_theme.dart';
import 'telegram_cloud_theme.dart';

/// Keeps theme colors and wallpapers independently selectable while offering
/// Telegram's bundled wallpaper when a newly selected theme provides one.
Future<void> promptForThemeWallpaper(
  BuildContext context, {
  required TelegramCloudTheme theme,
  required Brightness brightness,
  required TelegramCloudTheme? previousTheme,
  AppColors? colors,
}) async {
  final nextWallpaper = theme.wallpaper;
  if (nextWallpaper == null) return;

  final useWallpaper = await showAppConfirmDialog(
    context,
    title: AppStringKeys.globalThemeWallpaperPrompt,
    confirmText: AppStringKeys.globalThemeWallpaperApply,
    cancelText: AppStringKeys.globalThemeWallpaperKeep,
    colors: colors,
  );
  if (!context.mounted) return;

  final controller = ChatWallpaperController.shared;
  final dark = brightness == Brightness.dark;
  await controller.loadDefaultWallpaper(dark: dark);
  final existingDefault = controller.defaultWallpaper(dark: dark);
  final wallpaper = useWallpaper
      ? nextWallpaper
      : existingDefault ??
            previousTheme?.wallpaper ??
            controller.globalThemeWallpaperFor(dark: dark);
  if (wallpaper == null || (!useWallpaper && existingDefault != null)) return;
  try {
    await controller.applyDefaultWallpaper(wallpaper, dark: dark);
  } catch (_) {
    // A theme remains usable when its remote wallpaper is temporarily
    // unavailable. The existing background is left untouched in that case.
  }
}
