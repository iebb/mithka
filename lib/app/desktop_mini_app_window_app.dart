import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/telegram_mini_app_view.dart';
import '../components/keyboard_dismiss_on_tap.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_client.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'app_navigator.dart';
import 'desktop_mini_app_window.dart';

/// Presentation shell for an independent native Telegram Mini App window.
///
/// TDLib is already configured as a child proxy before this widget mounts.
class DesktopMiniAppWindowApp extends StatefulWidget {
  const DesktopMiniAppWindowApp({
    super.key,
    required this.launch,
    required this.prefs,
  });

  final DesktopMiniAppWindowLaunch launch;
  final SharedPreferences prefs;

  @override
  State<DesktopMiniAppWindowApp> createState() =>
      _DesktopMiniAppWindowAppState();
}

class _DesktopMiniAppWindowAppState extends State<DesktopMiniAppWindowApp> {
  late final ThemeController _theme = ThemeController(
    widget.prefs,
    initialAccountSlot: widget.launch.arguments.accountSlot,
    initialAccountUserId: widget.launch.arguments.accountUserId,
  );

  @override
  void initState() {
    super.initState();
    _theme.setActiveAccountSlot(
      widget.launch.arguments.accountSlot,
      userId: widget.launch.arguments.accountUserId,
    );
    unawaited(_theme.loadSelectedEmojiFontIfAvailable());
  }

  @override
  void dispose() {
    unawaited(TdClient.shared.closeProxy());
    _theme.dispose();
    super.dispose();
  }

  ThemeData _themeData(Brightness brightness) {
    final colors = _theme.uiColorsFor(brightness);
    final families = _theme.effectiveFontFamilyChain();
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: families.isEmpty ? null : families.first,
      fontFamilyFallback: families.length > 1
          ? families.skip(1).toList()
          : null,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _theme.usesCloudThemeForUi(brightness)
            ? colors.linkBlue
            : _theme.brandColor,
        brightness: brightness,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
        },
      ),
      extensions: [colors],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: _theme.applyAppTextTheme(base.textTheme),
      primaryTextTheme: _theme.applyAppTextTheme(base.primaryTextTheme),
    );
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _theme,
    child: AnimatedBuilder(
      animation: _theme,
      builder: (context, _) {
        final arguments = widget.launch.arguments;
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: arguments.title,
          debugShowCheckedModeBanner: false,
          locale: AppLocalizations.localeFromTag(arguments.localeTag),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          scrollBehavior: const AppScrollBehavior(),
          theme: _themeData(Brightness.light),
          darkTheme: _themeData(Brightness.dark),
          themeMode: arguments.dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final currentTheme = Theme.of(context);
            AppTheme.applyBrand(
              _theme.usesCloudThemeForUi(currentTheme.brightness)
                  ? context.colors.linkBlue
                  : _theme.brandColor,
            );
            return AppKeyboardDismissOnTap(
              child: Theme(
                data: currentTheme.copyWith(
                  textTheme: _theme.applyAppTextTheme(
                    currentTheme.textTheme,
                    boldText: media.boldText,
                  ),
                  primaryTextTheme: _theme.applyAppTextTheme(
                    currentTheme.primaryTextTheme,
                    boldText: media.boldText,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: _DesktopMiniAppSurface(launch: widget.launch),
        );
      },
    ),
  );
}

class _DesktopMiniAppSurface extends StatefulWidget {
  const _DesktopMiniAppSurface({required this.launch});

  final DesktopMiniAppWindowLaunch launch;

  @override
  State<_DesktopMiniAppSurface> createState() => _DesktopMiniAppSurfaceState();
}

class _DesktopMiniAppSurfaceState extends State<_DesktopMiniAppSurface> {
  bool _fullscreen = false;

  void _requestFullscreen(bool fullscreen) {
    if (_fullscreen != fullscreen && mounted) {
      setState(() => _fullscreen = fullscreen);
    }
    unawaited(_applyNativeFullscreen(fullscreen));
  }

  Future<void> _applyNativeFullscreen(bool fullscreen) async {
    final actual = await DesktopMiniAppWindowService.instance
        .setCurrentWindowFullscreen(fullscreen);
    if (actual != null && actual != _fullscreen && mounted) {
      setState(() => _fullscreen = actual);
    }
  }

  @override
  Widget build(BuildContext context) {
    final arguments = widget.launch.arguments;
    return TelegramMiniAppView(
      launch: TelegramMiniAppLaunch(
        title: arguments.title,
        url: widget.launch.url,
        botUserId: arguments.botUserId,
        chatId: arguments.chatId,
        launchId: arguments.launchId,
        keyboardButtonText: widget.launch.keyboardButtonText,
      ),
      fullscreen: _fullscreen,
      showSheetHandle: false,
      closeTdLaunchOnDispose: false,
      onClose: DesktopMiniAppWindowService.instance.closeCurrentWindow,
      onFullscreenChanged: _requestFullscreen,
    );
  }
}
