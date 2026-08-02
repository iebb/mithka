//
//  main.dart
//
//  MithkaApp entry point. Wires the controllers (AuthManager, ThemeController,
//  AccountStore, DrawerController) as providers, applies the adaptive theme +
//  themeMode, and keys the content on the active account so the whole tree
//  rebuilds for the newly active account. Port of the Swift `MithkaApp`.
//

import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:mithka_video_player_fvp/mithka_video_player_fvp.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_navigator.dart';
import 'app/app_performance_controller.dart';
import 'app/app_version.dart';
import 'app/chat_deep_link_controller.dart';
import 'app/content_view.dart';
import 'app/desktop_video_window.dart';
import 'app/global_video_split_host.dart';
import 'app/telemetry_config.dart';
import 'auth/account_store.dart';
import 'auth/auth_manager.dart';
import 'call/call_manager.dart';
import 'call/call_overlay_host.dart';
import 'chat/animated_sticker_view.dart';
import 'chat/chat_view.dart';
import 'chat/group_remark_controller.dart';
import 'chat/music_player_controller.dart';
import 'components/drawer_controller.dart' as dc;
import 'components/keyboard_dismiss_on_tap.dart';
import 'l10n/app_locale_controller.dart';
import 'l10n/app_localizations.dart';
import 'l10n/telegram_language_controller.dart';
import 'notifications/in_app_notification_banner.dart';
import 'notifications/notification_controller.dart';
import 'notifications/push_device_registrar.dart';
import 'platform/firebase_configuration.dart';
import 'platform/system_ui.dart';
import 'pro/mithka_pro_service.dart';
import 'security/local_app_lock_controller.dart';
import 'security/local_app_lock_views.dart';
import 'settings/ai_settings_controller.dart';
import 'settings/app_icon_controller.dart';
import 'settings/auto_download_media_controller.dart';
import 'settings/blocked_user_service.dart';
import 'settings/business_service.dart';
import 'settings/country_message_filter.dart';
import 'settings/developer_mode_controller.dart';
import 'settings/keyword_blocker.dart';
import 'settings/safety_notice_controller.dart';
import 'settings/sensitive_content_controller.dart';
import 'settings/translation_controller.dart';
import 'tdlib/td_client.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main(List<String> arguments) async {
  if (supportsDesktopVideoWindows) {
    final videoArguments = await MithkaDesktopVideoWindows.initialize(
      arguments,
    );
    if (videoArguments != null) {
      _initializeVideoBackend();
      runApp(DesktopVideoWindowApp(arguments: videoArguments));
      return;
    }
  }
  if (!sentryEnabled) {
    WidgetsFlutterBinding.ensureInitialized();
    configureAppImageCache();
    await _bootstrapAndRunApp();
    return;
  }

  // Let Sentry install its frame-aware WidgetsBinding before app code creates
  // the ordinary binding. This is required for slow/frozen-frame measurements.
  await SentryFlutter.init(
    _configureSentry,
    appRunner: () async {
      configureAppImageCache();
      await _bootstrapAndRunApp();
    },
  );
}

Future<void> _bootstrapAndRunApp() async {
  GoogleFonts.config.allowRuntimeFetching = true;
  _initializeVideoBackend();
  // Let iPhone and iPad follow every physical orientation.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Draw under transparent status / navigation bars (edge-to-edge).
  configureImmersiveSystemUI();
  final prefs = await SharedPreferences.getInstance();
  await LocalAppLockController.shared.initialize();
  KeywordBlocker.shared.initialize(prefs);
  CountryMessageFilter.shared.initialize(prefs);
  unawaited(SensitiveContentController.shared.initialize());
  MusicPlayerController.shared.initialize(prefs);
  // Preload Telegram blocked-user list so chat filters have data right away.
  unawaited(BlockedUserService.shared.loadBlockedUsers());
  // Firebase + analytics + Sentry tags are several platform-channel round
  // trips that nothing in the widget tree depends on — initialize them in
  // parallel with the first frame instead of blocking it.
  unawaited(_initTelemetry());
  final app = MithkaApp(prefs: prefs);
  _runAppWithNonFatalGoogleFonts(app);
}

bool _shouldUseFvp() {
  if (kIsWeb) return false;
  if (defaultTargetPlatform == TargetPlatform.android) {
    // Android's platform player owns Surface lifecycle transitions. Routing all
    // video through FVP's SurfaceProducer can retain a stale Java Surface when
    // Android 16 recreates it, which crashes in android_view_Surface_getSurface.
    return false;
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    // The platform player requires a complete HTTP response for a range
    // request, which prevents progressive playback of TDLib's sparse files.
    // MDK can seek to the MP4 metadata range and decode while TDLib downloads.
    return true;
  }
  return true;
}

void _initializeVideoBackend() {
  if (!_shouldUseFvp()) return;
  MithkaFvpBackend.ensureInitialized(
    configuration: const MithkaFvpConfiguration(
      platforms: {
        MithkaFvpPlatform.ios,
        MithkaFvpPlatform.linux,
        MithkaFvpPlatform.macos,
        MithkaFvpPlatform.windows,
      },
    ),
  );
}

Future<void> _initTelemetry() async {
  try {
    final hasFirebaseConfiguration = await FirebaseConfiguration.isAvailable;
    final appVersion = await AppVersion.load();
    if (hasFirebaseConfiguration) {
      await Firebase.initializeApp();
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
      await FirebaseAnalytics.instance.setDefaultEventParameters(
        appVersion.analyticsParameters,
      );
      await FirebaseAnalytics.instance.logAppOpen(
        parameters: appVersion.analyticsParameters,
      );
    } else {
      debugPrint('Firebase configuration not found; analytics disabled');
    }
    if (sentryEnabled) {
      await Sentry.configureScope((scope) async {
        await scope.setTag('app.version', appVersion.version);
        await scope.setTag('app.build_number', appVersion.buildNumber);
        await scope.setTag('git.commit', appVersion.commit);
      });
    }
  } catch (error) {
    // Telemetry must never take the app down (e.g. missing Firebase config
    // on a dev build); the app runs fine without it.
    debugPrint('telemetry init failed: $error');
  }
}

void _configureSentry(SentryFlutterOptions options) {
  options.dsn = sentryDsn;
  options.environment = sentryEnvironment;
  // Let SentryFlutter derive bundle-id@version+build so Dart events share the
  // same release as native iOS crash reports. The git SHA remains a tag.
  options.navigatorKey = appNavigatorKey;
  options.sendDefaultPii = false;
  options.tracesSampleRate = sentryTracesSampleRate;
  options.maxBreadcrumbs = 200;
  options.beforeSend = (event, hint) =>
      _isGoogleFontLoadFailure(event) ? null : event;
}

bool _isGoogleFontLoadFailure(SentryEvent event) {
  final parts = <String>[
    event.throwable?.toString() ?? '',
    event.message?.formatted ?? '',
    event.message?.template ?? '',
    for (final exception in event.exceptions ?? const [])
      '${exception.type ?? ''} ${exception.value ?? ''}',
  ];
  return _isGoogleFontLoadFailureText(parts.join('\n'));
}

void _runAppWithNonFatalGoogleFonts(Widget app) {
  final previousFlutterOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isGoogleFontLoadFailureText(details.exceptionAsString())) return;
    previousFlutterOnError?.call(details);
  };

  final previousPlatformOnError = ui.PlatformDispatcher.instance.onError;
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    if (_isGoogleFontLoadFailureText(error.toString())) return true;
    return previousPlatformOnError?.call(error, stack) ?? false;
  };

  runApp(app);
}

bool _isGoogleFontLoadFailureText(String value) {
  final text = value.toLowerCase();
  final isGoogleFonts =
      text.contains('google_fonts') ||
      text.contains('googlefonts') ||
      text.contains('fonts.gstatic.com') ||
      text.contains('fonts.googleapis.com');
  if (!isGoogleFonts) return false;
  return text.contains('failed to load font') ||
      text.contains('unable to load font') ||
      text.contains('handshakeexception') ||
      text.contains('socketexception') ||
      text.contains('clientexception');
}

typedef _MithkaAppConsumer =
    Consumer4<
      ThemeController,
      AccountStore,
      AppLocaleController,
      TelegramLanguageController
    >;

class MithkaApp extends StatefulWidget {
  const MithkaApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<MithkaApp> createState() => _MithkaAppState();
}

class _MithkaAppState extends State<MithkaApp> with WidgetsBindingObserver {
  late final AuthManager _auth = AuthManager();
  late final AccountStore _accounts = AccountStore(widget.prefs);
  late final MithkaProService _mithkaPro = MithkaProService.shared;
  late final ThemeController _theme = ThemeController(
    widget.prefs,
    initialAccountSlot: _accounts.activeSlot,
  );
  late final TranslationController _translation = TranslationController(
    widget.prefs,
  );
  late final AiSettingsController _ai = AiSettingsController(widget.prefs);
  late final AppLocaleController _locale = AppLocaleController(widget.prefs);
  late final TelegramLanguageController _telegramLanguage =
      TelegramLanguageController.shared;
  late final dc.DrawerController _drawer = dc.DrawerController();
  late final ChatDeepLinkController _chatDeepLinks =
      ChatDeepLinkController.shared;
  late final GroupRemarkController _groupRemarks = GroupRemarkController(
    widget.prefs,
    initialAccountUserId: _accounts.activeUserId,
  );
  late final AppIconController _appIcons = AppIconController(widget.prefs);
  late final AutoDownloadMediaController _autoDownload =
      AutoDownloadMediaController.shared;
  late final DeveloperModeController _developer = DeveloperModeController(
    widget.prefs,
  );
  late final AppPerformanceController _performance = AppPerformanceController(
    widget.prefs,
    memoryTrimmers: [clearChatMemoryCaches, clearAnimatedStickerMemoryCache],
  );
  late final SafetyNoticeController _safetyNotice = SafetyNoticeController(
    widget.prefs,
  );
  late final SensitiveContentController _sensitiveContent =
      SensitiveContentController.shared;
  late final LocalAppLockController _appLock = LocalAppLockController.shared;
  late final CallManager _calls = CallManager()..start();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _performance.start();
    _accounts.addListener(_handleActiveAccountChange);
    _theme.addListener(_handleThemePreferencesChange);
    BusinessQuickReplyService.shared.startPreloading(
      enabled: _theme.quickRepliesEnabled,
    );
    _theme.loadSelectedEmojiFontIfAvailable();
    _autoDownload.initialize(widget.prefs);
    _auth.start();
    unawaited(_ai.initialize());
    unawaited(_mithkaPro.initialize());
    unawaited(_telegramLanguage.initialize(widget.prefs));
    unawaited(_appIcons.initialize());
    unawaited(_accounts.recoverPendingAddOnStartup(_auth));
    NotificationController.shared.start(widget.prefs);
    PushDeviceRegistrar.shared.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _performance.dispose();
    _accounts.removeListener(_handleActiveAccountChange);
    _theme.removeListener(_handleThemePreferencesChange);
    _groupRemarks.dispose();
    _calls.dispose();
    super.dispose();
  }

  void _handleActiveAccountChange() {
    _groupRemarks.setActiveAccountUserId(_accounts.activeUserId);
    _theme.setActiveAccountSlot(
      _accounts.activeSlot,
      userId: _accounts.activeUserId,
    );
  }

  void _handleThemePreferencesChange() {
    BusinessQuickReplyService.shared.setPreloadingEnabled(
      _theme.quickRepliesEnabled,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appLock.lock();
    }
    if (state == AppLifecycleState.resumed) {
      TdClient.shared.restartReceiveIsolate();
      unawaited(_mithkaPro.refresh());
    }
  }

  ThemeData _themeData(Brightness brightness, ThemeController theme) {
    final colors = theme.uiColorsFor(brightness);
    final families = theme.effectiveFontFamilyChain();
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: families.isEmpty ? null : families.first,
      fontFamilyFallback: families.length > 1
          ? families.skip(1).toList()
          : null,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: theme.usesCloudThemeForUi(brightness)
            ? colors.linkBlue
            : theme.brandColor,
        brightness: brightness,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
        },
      ),
      extensions: [colors],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: theme.applyAppTextTheme(base.textTheme),
      primaryTextTheme: theme.applyAppTextTheme(base.primaryTextTheme),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _theme),
        ChangeNotifierProvider.value(value: _translation),
        ChangeNotifierProvider.value(value: _ai),
        ChangeNotifierProvider.value(value: _locale),
        ChangeNotifierProxyProvider<
          AppLocaleController,
          TelegramLanguageController
        >(
          create: (_) => _telegramLanguage,
          update: (_, locale, telegramLanguage) {
            final controller = telegramLanguage ?? _telegramLanguage;
            unawaited(controller.syncAppLocale(locale.locale));
            return controller;
          },
        ),
        ChangeNotifierProvider.value(value: _accounts),
        ChangeNotifierProvider.value(value: _groupRemarks),
        ChangeNotifierProvider.value(value: _mithkaPro),
        ChangeNotifierProvider.value(value: _chatDeepLinks),
        ChangeNotifierProvider.value(value: _appIcons),
        ChangeNotifierProvider.value(value: _autoDownload),
        ChangeNotifierProvider.value(value: _developer),
        ChangeNotifierProvider.value(value: _performance),
        ChangeNotifierProvider.value(value: _safetyNotice),
        ChangeNotifierProvider.value(value: _sensitiveContent),
        ChangeNotifierProvider.value(value: _appLock),
        ChangeNotifierProvider.value(value: _calls),
        ChangeNotifierProvider<dc.DrawerController>.value(value: _drawer),
      ],
      child: _MithkaAppConsumer(
        builder: (context, theme, accounts, locale, _, _) {
          return MaterialApp(
            navigatorKey: appNavigatorKey,
            title: 'Mithka',
            debugShowCheckedModeBanner: false,
            locale: locale.locale,
            localeResolutionCallback: (locale, _) => locale == null
                ? AppLocalizations.fallbackLocale
                : AppLocalizations.resolve(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            navigatorObservers: _telemetryNavigatorObservers(),
            scrollBehavior: const AppScrollBehavior(),
            theme: _themeData(Brightness.light, theme),
            darkTheme: _themeData(Brightness.dark, theme),
            themeMode: theme.themeMode,
            // Apply the user's chosen font size app-wide (设置 › 通用 › 字体大小).
            builder: (context, child) {
              final media = MediaQuery.of(context);
              final currentTheme = Theme.of(context);
              AppTheme.applyBrand(
                theme.usesCloudThemeForUi(currentTheme.brightness)
                    ? context.colors.linkBlue
                    : theme.brandColor,
              );
              final themedChild = Theme(
                data: currentTheme.copyWith(
                  textTheme: theme.applyAppTextTheme(
                    currentTheme.textTheme,
                    boldText: media.boldText,
                  ),
                  primaryTextTheme: theme.applyAppTextTheme(
                    currentTheme.primaryTextTheme,
                    boldText: media.boldText,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
              final unlockedApp = Stack(
                children: [
                  Positioned.fill(
                    child: GlobalVideoSplitHost(child: themedChild),
                  ),
                  Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (_) => const GlobalMusicPlayerOverlay(),
                      ),
                    ],
                  ),
                  Positioned.fill(
                    child: InAppNotificationBannerHost(
                      controller: NotificationController.shared,
                    ),
                  ),
                  const Positioned.fill(child: GlobalCallOverlayHost()),
                ],
              );
              final appLock = context.watch<LocalAppLockController>();
              final appChild = Stack(
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      excluding: appLock.locked,
                      child: unlockedApp,
                    ),
                  ),
                  const Positioned.fill(child: LocalAppLockGate()),
                ],
              );
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: systemUiOverlayStyleForSurface(context.colors.navBar),
                child: _ScaledAppView(
                  fontScale: theme.fontScale,
                  interfaceScale: theme.renderedInterfaceScale,
                  child: DefaultTextStyle(
                    style: theme.applyAppTextStyle(
                      AppTextStyle.body(context.colors.textPrimary),
                      boldText: media.boldText,
                    ),
                    child: appChild,
                  ),
                ),
              );
            },
            // Rebuild the whole tree when the active account changes.
            home: KeyedSubtree(
              key: ValueKey(accounts.activeSlot),
              child: const ContentView(),
            ),
          );
        },
      ),
    );
  }
}

NavigatorObserver? _buildSentryNavigatorObserver() =>
    sentryEnabled ? SentryNavigatorObserver() : null;

final NavigatorObserver? _sentryNavigatorObserver =
    _buildSentryNavigatorObserver();

List<NavigatorObserver> _telemetryNavigatorObservers() {
  final observers = <NavigatorObserver>[?_sentryNavigatorObserver];
  try {
    if (Firebase.apps.isNotEmpty) {
      observers.add(
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      );
    }
  } catch (_) {
    // Sentry navigation breadcrumbs do not depend on Firebase availability.
  }
  return observers;
}

class _ScaledAppView extends StatelessWidget {
  const _ScaledAppView({
    required this.fontScale,
    required this.interfaceScale,
    required this.child,
  });

  final double fontScale;
  final double interfaceScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = interfaceScale;
    final virtualSize = Size(
      media.size.width / scale,
      media.size.height / scale,
    );
    final scaledMedia = media.copyWith(
      size: virtualSize,
      padding: _unscaleInsets(media.padding, scale),
      viewPadding: _unscaleInsets(media.viewPadding, scale),
      viewInsets: _unscaleInsets(media.viewInsets, scale),
      systemGestureInsets: _unscaleInsets(media.systemGestureInsets, scale),
      // The outer transform scales geometry and text together. Keep only the
      // independent font preference here; dividing by interfaceScale caused
      // normal Text widgets to stay small while noScaling text still grew.
      textScaler: TextScaler.linear(fontScale),
    );

    return AppKeyboardDismissOnTap(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: virtualSize.width,
          maxWidth: virtualSize.width,
          minHeight: virtualSize.height,
          maxHeight: virtualSize.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: virtualSize.width,
              height: virtualSize.height,
              child: MediaQuery(data: scaledMedia, child: child),
            ),
          ),
        ),
      ),
    );
  }

  EdgeInsets _unscaleInsets(EdgeInsets insets, double scale) {
    return EdgeInsets.fromLTRB(
      insets.left / scale,
      insets.top / scale,
      insets.right / scale,
      insets.bottom / scale,
    );
  }
}
