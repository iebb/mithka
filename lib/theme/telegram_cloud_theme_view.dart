import 'package:flutter/widgets.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../chat/chat_wallpaper.dart';
import '../components/app_confirm_dialog.dart';
import '../components/ui_components.dart';
import 'app_theme.dart';
import 'telegram_cloud_theme.dart';
import 'theme_controller.dart';
import 'theme_wallpaper_prompt.dart';

class TelegramCloudThemePreviewView extends StatelessWidget {
  const TelegramCloudThemePreviewView({
    super.key,
    required this.theme,
    this.targetBrightness,
    this.currentAppBrightness,
  });

  final TelegramCloudTheme theme;
  final Brightness? targetBrightness;
  final Brightness? currentAppBrightness;

  @override
  Widget build(BuildContext context) {
    final colors = theme.uiColors;
    return ColoredBox(
      color: colors.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.cloudThemePreviewTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                _identity(colors),
                const SizedBox(height: AppSpacing.xl),
                _chatPreview(context, colors),
              ],
            ),
          ),
          _applyBar(context, colors),
        ],
      ),
    );
  }

  Widget _identity(AppColors colors) => Container(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          theme.displayTitle,
          style: AppTextStyle.title(
            colors.textPrimary,
            weight: AppTextWeight.semibold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(theme.slug, style: AppTextStyle.footnote(colors.textSecondary)),
      ],
    ),
  );

  Widget _chatPreview(BuildContext context, AppColors colors) {
    final outgoing = theme.outgoingColor ?? theme.accentColor;
    final outgoingText =
        theme.outgoingTextColor ?? readableForeground(outgoing);
    final incoming = theme.incomingColor ?? colors.bubbleIncoming;
    final incomingText = theme.incomingTextColor ?? colors.bubbleIncomingText;
    final wallpaperController = ChatWallpaperController.shared;
    return AnimatedBuilder(
      animation: wallpaperController,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          height: 360,
          child: ChatWallpaperBackground(
            wallpaper: theme.wallpaper == null
                ? null
                : wallpaperController.resolvedWallpaper(theme.wallpaper!),
            fallbackColor: colors.chatBackground,
            brightness: theme.isDark ? Brightness.dark : Brightness.light,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _bubble(
                    AppStringKeys.chatWallpaperPreviewIncoming.l10n(context),
                    incoming,
                    incomingText,
                    Alignment.centerLeft,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _bubble(
                    AppStringKeys.chatWallpaperPreviewOutgoing.l10n(context),
                    outgoing,
                    outgoingText,
                    Alignment.centerRight,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(
    String text,
    Color background,
    Color foreground,
    Alignment alignment,
  ) => Align(
    alignment: alignment,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(text, style: AppTextStyle.body(foreground)),
    ),
  );

  Widget _applyBar(BuildContext context, AppColors colors) => ColoredBox(
    color: colors.card,
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.all(AppSpacing.xl),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _applyTheme(context, colors),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.accentColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Text(
            AppStringKeys.cloudThemeApply.l10n(context),
            style: AppTextStyle.bodyLarge(
              readableForeground(theme.accentColor),
              weight: AppTextWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _applyTheme(BuildContext context, AppColors colors) async {
    final controller = context.read<ThemeController>();
    final target = theme.isBuiltIn
        ? targetBrightness ??
              (theme.isDark ? Brightness.dark : Brightness.light)
        : (theme.isDark ? Brightness.dark : Brightness.light);
    final current =
        currentAppBrightness ??
        switch (controller.mode) {
          AppearanceMode.light => Brightness.light,
          AppearanceMode.dark => Brightness.dark,
          AppearanceMode.system => MediaQuery.platformBrightnessOf(context),
        };
    if (!theme.isBuiltIn && target != current) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: target == Brightness.dark
            ? AppStringKeys.globalThemeSwitchToDark
            : AppStringKeys.globalThemeSwitchToLight,
        confirmText: AppStringKeys.globalThemeSwitchModeAction,
        colors: colors,
      );
      if (!context.mounted || !confirmed) return;
      controller.mode = target == Brightness.dark
          ? AppearanceMode.dark
          : AppearanceMode.light;
    }
    await promptForThemeWallpaper(
      context,
      theme: theme,
      brightness: target,
      previousTheme: controller.cloudThemeFor(target),
      colors: colors,
    );
    if (!context.mounted) return;
    controller.installCloudTheme(theme, brightness: target);
    if (context.mounted) Navigator.of(context).pop();
  }
}
