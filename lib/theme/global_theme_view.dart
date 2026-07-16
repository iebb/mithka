import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../chat/chat_wallpaper.dart';
import '../chat/chat_wallpaper_color_view.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import 'app_theme.dart';
import 'telegram_cloud_theme.dart';
import 'theme_controller.dart';
import 'theme_wallpaper_prompt.dart';

/// Global Telegram .attheme management. This intentionally contains no chat
/// emoji themes. Applying its palette to the rest of the app is opt-in.
class GlobalThemeView extends StatefulWidget {
  const GlobalThemeView({super.key, this.themeService});

  final TelegramCloudThemeService? themeService;

  @override
  State<GlobalThemeView> createState() => _GlobalThemeViewState();
}

class _GlobalThemeViewState extends State<GlobalThemeView> {
  static const _officialAccentPresets = <Color>[
    Color(0xFF168ACD),
    Color(0xFF30A3E6),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFFF3B30),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
    Color(0xFF8E8E93),
  ];
  bool _requestedCommunityThemes = false;
  bool _initializedTargetBrightness = false;
  List<TelegramCloudTheme>? _communityThemes;
  Brightness _targetBrightness = Brightness.light;
  Brightness _appBrightness = Brightness.light;
  AppColors _pageColors = AppColors.light;

  TelegramCloudThemeService get _themeService =>
      widget.themeService ?? TelegramCloudThemeService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedTargetBrightness) {
      _initializedTargetBrightness = true;
      _targetBrightness = Theme.of(context).brightness;
    }
    if (_requestedCommunityThemes) return;
    _requestedCommunityThemes = true;
    _synchronizeCommunityThemes(context.read<ThemeController>());
  }

  Future<void> _synchronizeCommunityThemes(ThemeController controller) async {
    final themes = await _themeService.loadInstalled(
      fallback: controller.installedCloudThemes,
    );
    if (!mounted) return;
    controller.synchronizeInstalledCloudThemes(themes);
    setState(() => _communityThemes = themes);
  }

  Future<void> _applyImportedTheme(
    ThemeController controller,
    TelegramCloudTheme theme,
  ) async {
    final target = theme.isDark ? Brightness.dark : Brightness.light;
    if (target != _appBrightness) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: target == Brightness.dark
            ? AppStringKeys.globalThemeSwitchToDark
            : AppStringKeys.globalThemeSwitchToLight,
        confirmText: AppStringKeys.globalThemeSwitchModeAction,
        colors: _pageColors,
      );
      if (!mounted || !confirmed) return;
      setState(() => _targetBrightness = target);
      controller.mode = target == Brightness.dark
          ? AppearanceMode.dark
          : AppearanceMode.light;
    }
    await _installTheme(controller, theme, target);
  }

  Future<void> _installTheme(
    ThemeController controller,
    TelegramCloudTheme theme,
    Brightness target,
  ) async {
    await promptForThemeWallpaper(
      context,
      theme: theme,
      brightness: target,
      previousTheme: controller.cloudThemeFor(target),
      colors: _pageColors,
    );
    if (!mounted) return;
    controller.installCloudTheme(theme, brightness: target);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final theme = controller.cloudThemeFor(_targetBrightness);
    _pageColors =
        theme?.uiColors ??
        (_targetBrightness == Brightness.dark
            ? AppColors.dark
            : AppColors.light);
    final inheritedTheme = Theme.of(context);
    _appBrightness = inheritedTheme.brightness;
    return Theme(
      data: inheritedTheme.copyWith(
        brightness: _targetBrightness,
        extensions: [_pageColors],
      ),
      child: Builder(
        builder: (previewContext) =>
            _buildPage(previewContext, controller: controller, theme: theme),
      ),
    );
  }

  Widget _buildPage(
    BuildContext previewContext, {
    required ThemeController controller,
    required TelegramCloudTheme? theme,
  }) {
    final c = _pageColors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.globalThemeTitle,
            onBack: () => Navigator.of(previewContext).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                _brightnessPicker(),
                const SizedBox(height: 14),
                _activeThemeCard(controller, theme),
                const SizedBox(height: 22),
                _sectionTitle(AppStringKeys.globalThemeOfficial),
                const SizedBox(height: 9),
                _themeStrip(controller, theme, builtInTelegramCloudThemes),
                const SizedBox(height: 22),
                _sectionTitle(AppStringKeys.globalThemeCommunity),
                const SizedBox(height: 9),
                _communityThemeStrip(controller, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _brightnessPicker() {
    final c = _pageColors;
    return Container(
      key: const ValueKey('global-theme-brightness-picker'),
      height: 40,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.panelBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _brightnessButton(
              brightness: Brightness.light,
              icon: HeroAppIcons.sun,
              label: AppStringKeys.globalThemeDay,
            ),
          ),
          Expanded(
            child: _brightnessButton(
              brightness: Brightness.dark,
              icon: HeroAppIcons.moon,
              label: AppStringKeys.globalThemeNight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _brightnessButton({
    required Brightness brightness,
    required AppIconData icon,
    required String label,
  }) {
    final c = _pageColors;
    final selected = _targetBrightness == brightness;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _targetBrightness = brightness),
      child: AnimatedContainer(
        key: ValueKey('global-theme-brightness-${brightness.name}'),
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected
              ? c.linkBlue.withValues(alpha: 0.15)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                icon,
                size: 17,
                color: selected ? c.linkBlue : c.textTertiary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label.l10n(context),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? c.linkBlue : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String key) {
    final c = _pageColors;
    return Text(
      key.l10n(context),
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.textSecondary,
      ),
    );
  }

  Widget _communityThemeStrip(
    ThemeController controller,
    TelegramCloudTheme? selectedTheme,
  ) {
    final themes = _communityThemes;
    if (themes == null) {
      return SizedBox(
        height: 126,
        child: Center(
          child: Text(
            AppStringKeys.globalThemeLoading.l10n(context),
            style: TextStyle(fontSize: 13, color: _pageColors.textTertiary),
          ),
        ),
      );
    }
    if (themes.isEmpty) {
      return SizedBox(
        height: 54,
        child: Center(
          child: Text(
            AppStringKeys.globalThemeCommunityEmpty.l10n(context),
            style: TextStyle(fontSize: 13, color: _pageColors.textTertiary),
          ),
        ),
      );
    }
    return _themeStrip(controller, selectedTheme, themes);
  }

  Widget _themeStrip(
    ThemeController controller,
    TelegramCloudTheme? selectedTheme,
    Iterable<TelegramCloudTheme> source,
  ) {
    final themes = source.toList(growable: false);
    return SizedBox(
      height: 126,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: themes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final sourceTheme = themes[index];
          // A customized built-in keeps the same official identity/slug. Show
          // the persisted tint in the strip rather than the stock constant.
          final theme = selectedTheme?.slug == sourceTheme.slug
              ? selectedTheme!
              : sourceTheme;
          return _installedThemeCard(
            theme,
            selected: selectedTheme?.slug == theme.slug,
            onTap: () => theme.isBuiltIn
                ? _installTheme(controller, theme, _targetBrightness)
                : _applyImportedTheme(controller, theme),
          );
        },
      ),
    );
  }

  Widget _installedThemeCard(
    TelegramCloudTheme theme, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = _pageColors;
    final themeColors = theme.uiColors;
    final outgoing = theme.outgoingColor ?? themeColors.linkBlue;
    final wallpaperController = ChatWallpaperController.shared;
    final wallpaper = theme.wallpaper;
    Widget preview(Widget child) {
      if (wallpaper == null) {
        return ColoredBox(color: themeColors.background, child: child);
      }
      return AnimatedBuilder(
        animation: wallpaperController,
        builder: (context, _) {
          final resolved = wallpaperController.resolvedWallpaper(wallpaper);
          return RepaintBoundary(
            key: ValueKey('global-theme-wallpaper-${theme.slug}'),
            child: ChatWallpaperBackground(
              wallpaper: resolved,
              fallbackColor: themeColors.chatBackground,
              brightness: theme.isDark ? Brightness.dark : Brightness.light,
              imageScrim: const Color(0x16000000),
              child: child,
            ),
          );
        },
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 142,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 92,
              padding: EdgeInsets.all(selected ? 2.5 : 1),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: selected ? c.linkBlue : c.divider,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 11.5 : 13),
                child: preview(
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 72,
                            height: 20,
                            decoration: BoxDecoration(
                              color: themeColors.bubbleIncoming,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x22000000),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 78,
                            height: 20,
                            decoration: BoxDecoration(
                              color: outgoing,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x22000000),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              theme.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? c.linkBlue : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeThemeCard(
    ThemeController controller,
    TelegramCloudTheme? theme,
  ) {
    final c = _pageColors;
    final colors = theme?.uiColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme?.displayTitle ??
                          AppStringKeys.globalThemeDefault.l10n(context),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    if (theme != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        theme.slug,
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (theme != null) ...[
                const SizedBox(width: 12),
                _themeColorGrid(theme),
              ],
            ],
          ),
          if (colors != null) ...[
            if (theme?.isBuiltIn == true) ...[
              const SizedBox(height: 16),
              _builtInAccentPicker(controller, theme!),
            ],
          ],
        ],
      ),
    );
  }

  Widget _swatch(Color color, int index) => Container(
    key: ValueKey('global-theme-semantic-swatch-$index'),
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x22000000)),
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 4),
      ],
    ),
  );

  Widget _themeColorGrid(TelegramCloudTheme theme) {
    final swatches = theme.semanticUiPreviewColors;
    return SizedBox(
      key: const ValueKey('global-theme-color-grid'),
      width: 84,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        children: [
          for (var index = 0; index < swatches.length; index++)
            _swatch(swatches[index], index),
        ],
      ),
    );
  }

  Widget _builtInAccentPicker(
    ThemeController controller,
    TelegramCloudTheme theme,
  ) {
    final c = _pageColors;
    final selected = theme.accentColor.toARGB32();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStringKeys.chatWallpaperColor.l10n(context),
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 36,
          child: ListView.separated(
            key: const ValueKey('global-theme-accent-list'),
            scrollDirection: Axis.horizontal,
            itemCount: _officialAccentPresets.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index < _officialAccentPresets.length) {
                final color = _officialAccentPresets[index];
                return _accentChoice(
                  color: color,
                  selected: color.toARGB32() == selected,
                  onTap: () => controller.installCloudTheme(
                    theme.withBuiltInAccent(color),
                    brightness: _targetBrightness,
                  ),
                );
              }
              return GestureDetector(
                key: const ValueKey('global-theme-custom-accent'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _chooseCustomAccent(controller, theme),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.searchFill,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.divider),
                  ),
                  child: AppIcon(
                    HeroAppIcons.palette,
                    size: 16,
                    color: c.linkBlue,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _accentChoice({
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? _pageColors.textPrimary : const Color(0x22000000),
          width: selected ? 2.5 : 1,
        ),
      ),
      child: selected
          ? AppIcon(
              HeroAppIcons.check,
              size: 14,
              color: readableForeground(color),
            )
          : null,
    ),
  );

  Future<void> _chooseCustomAccent(
    ThemeController controller,
    TelegramCloudTheme theme,
  ) async {
    final rgb = theme.accentColor.toARGB32() & 0x00FFFFFF;
    final result = await Navigator.of(context).push<ChatWallpaper>(
      PageRouteBuilder<ChatWallpaper>(
        pageBuilder: (_, _, _) => ChatWallpaperColorView(
          controller: ChatWallpaperController.shared,
          dark: _targetBrightness == Brightness.dark,
          colorOnly: true,
          initial: ChatWallpaper.telegram(
            backgroundId: 0,
            remoteType: 'fill',
            colors: [rgb],
          ),
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted || result == null || result.colors.isEmpty) return;
    controller.installCloudTheme(
      theme.withBuiltInAccent(
        Color(0xFF000000 | (result.colors.first & 0x00FFFFFF)),
      ),
      brightness: _targetBrightness,
    );
  }
}
