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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_navigator.dart';
import 'app/app_version.dart';
import 'app/chat_deep_link_controller.dart';
import 'app/content_view.dart';
import 'auth/account_store.dart';
import 'auth/auth_manager.dart';
import 'auth/terms_sheet.dart';
import 'chat/music_player_controller.dart';
import 'components/drawer_controller.dart' as dc;
import 'l10n/app_locale_controller.dart';
import 'l10n/app_localizations.dart';
import 'l10n/telegram_language_controller.dart';
import 'notifications/notification_controller.dart';
import 'notifications/push_device_registrar.dart';
import 'settings/app_icon_controller.dart';
import 'settings/auto_download_media_controller.dart';
import 'settings/blocked_user_service.dart';
import 'settings/developer_mode_controller.dart';
import 'settings/keyword_blocker.dart';
import 'settings/translation_controller.dart';
import 'tdlib/td_client.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

const _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const _sentryEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'production',
);
const _gitCommit = String.fromEnvironment('GIT_COMMIT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureAndroidImageCache();
  if (_sentryDsn.isEmpty) {
    await _bootstrapAndRunApp();
    return;
  }

  await SentryFlutter.init(_configureSentry, appRunner: _bootstrapAndRunApp);
}

void _configureAndroidImageCache() {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 420;
  cache.maximumSizeBytes = 80 << 20;
}

Future<void> _bootstrapAndRunApp() async {
  GoogleFonts.config.allowRuntimeFetching = true;
  if (_shouldUseFvp()) {
    // Route video_player through the MDK/FFmpeg backend so .webm (VP9 + alpha)
    // video stickers decode + play (and stay transparent).
    fvp.registerWith(
      options: defaultTargetPlatform == TargetPlatform.android
          ? {
              'video.decoders': ['FFmpeg', 'dav1d'],
            }
          : null,
    );
  }
  // Let iPhone and iPad follow every physical orientation.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final prefs = await SharedPreferences.getInstance();
  KeywordBlocker.shared.initialize(prefs);
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
    // AVFoundation owns the drawable lifecycle when iOS changes display scale,
    // resolution, or external-screen attachment. FVP/MDK can retain textures
    // from the old Flutter surface and crash while the surface is rebuilt.
    return false;
  }
  return true;
}

Future<void> _initTelemetry() async {
  try {
    await Firebase.initializeApp();
    final appVersion = await AppVersion.load();
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    await FirebaseAnalytics.instance.setDefaultEventParameters(
      appVersion.analyticsParameters,
    );
    await FirebaseAnalytics.instance.logAppOpen(
      parameters: appVersion.analyticsParameters,
    );
    if (_sentryDsn.isNotEmpty) {
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
  options.dsn = _sentryDsn;
  options.environment = _sentryEnvironment;
  options.release = _gitCommit.isEmpty ? 'mithka' : 'mithka@$_gitCommit';
  options.sendDefaultPii = false;
  options.tracesSampleRate = 0;
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

class MithkaApp extends StatefulWidget {
  const MithkaApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<MithkaApp> createState() => _MithkaAppState();
}

class _MithkaAppState extends State<MithkaApp> with WidgetsBindingObserver {
  late final AuthManager _auth = AuthManager();
  late final ThemeController _theme = ThemeController(widget.prefs);
  late final TranslationController _translation = TranslationController(
    widget.prefs,
  );
  late final AppLocaleController _locale = AppLocaleController(widget.prefs);
  late final TelegramLanguageController _telegramLanguage =
      TelegramLanguageController.shared;
  late final AccountStore _accounts = AccountStore(widget.prefs);
  late final dc.DrawerController _drawer = dc.DrawerController();
  late final ChatDeepLinkController _chatDeepLinks =
      ChatDeepLinkController.shared;
  late final AppIconController _appIcons = AppIconController(widget.prefs);
  late final AutoDownloadMediaController _autoDownload =
      AutoDownloadMediaController.shared;
  late final DeveloperModeController _developer = DeveloperModeController(
    widget.prefs,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme.loadSelectedEmojiFontIfAvailable();
    _autoDownload.initialize(widget.prefs);
    _auth.start();
    unawaited(_telegramLanguage.initialize(widget.prefs));
    unawaited(_appIcons.initialize());
    unawaited(_accounts.recoverPendingAddOnStartup(_auth));
    NotificationController.shared.start();
    PushDeviceRegistrar.shared.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      TdClient.shared.restartReceiveIsolate();
    }
  }

  ThemeData _themeData(Brightness brightness, ThemeController theme) {
    final colors = brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
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
        seedColor: AppTheme.brand,
        brightness: brightness,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoRadiusPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _NoRadiusPageTransitionsBuilder(),
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
        ChangeNotifierProvider.value(value: _chatDeepLinks),
        ChangeNotifierProvider.value(value: _appIcons),
        ChangeNotifierProvider.value(value: _autoDownload),
        ChangeNotifierProvider.value(value: _developer),
        ChangeNotifierProvider<dc.DrawerController>.value(value: _drawer),
      ],
      child: Consumer3<ThemeController, AccountStore, AppLocaleController>(
        builder: (context, theme, accounts, locale, _) {
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
            navigatorObservers: _analyticsNavigatorObservers(),
            theme: _themeData(Brightness.light, theme),
            darkTheme: _themeData(Brightness.dark, theme),
            themeMode: theme.themeMode,
            // Apply the user's chosen font size app-wide (设置 › 通用 › 字体大小).
            builder: (context, child) {
              final media = MediaQuery.of(context);
              final currentTheme = Theme.of(context);
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
              final appChild = Stack(
                children: [
                  Positioned.fill(child: themedChild),
                  Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (_) => const GlobalMusicPlayerOverlay(),
                      ),
                    ],
                  ),
                ],
              );
              return _ScaledAppView(
                fontScale: theme.fontScale,
                interfaceScale: theme.interfaceScale,
                child: DefaultTextStyle(
                  style: AppTextStyle.body(context.colors.textPrimary),
                  child: appChild,
                ),
              );
            },
            // Rebuild the whole tree when the active account changes.
            home: FirstLaunchTermsGate(
              prefs: widget.prefs,
              child: KeyedSubtree(
                key: ValueKey(accounts.activeSlot),
                child: const ContentView(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FirstLaunchTermsGate extends StatefulWidget {
  const FirstLaunchTermsGate({
    super.key,
    required this.prefs,
    required this.child,
  });

  static const acceptedKey = 'mithka.terms.accepted.v1';

  final SharedPreferences prefs;
  final Widget child;

  @override
  State<FirstLaunchTermsGate> createState() => _FirstLaunchTermsGateState();
}

class _FirstLaunchTermsGateState extends State<FirstLaunchTermsGate> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showIfNeeded());
  }

  @override
  void didUpdateWidget(covariant FirstLaunchTermsGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs != widget.prefs) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showIfNeeded());
    }
  }

  Future<void> _showIfNeeded() async {
    if (!mounted || _shown) return;
    if (widget.prefs.getBool(FirstLaunchTermsGate.acceptedKey) ?? false) {
      return;
    }
    _shown = true;
    await showTelegramTermsSheet(
      context,
      isDismissible: false,
      enableDrag: false,
      onAccept: () async {
        await widget.prefs.setBool(FirstLaunchTermsGate.acceptedKey, true);
      },
    );
    _shown = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

List<NavigatorObserver> _analyticsNavigatorObservers() {
  try {
    if (Firebase.apps.isEmpty) return const [];
    return [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)];
  } catch (_) {
    return const [];
  }
}

class _NoRadiusPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoRadiusPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.fullscreenDialog) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      );
      final offset = Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(curved);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: offset, child: child),
      );
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    final offset = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: offset, child: child),
    );
  }
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
      textScaler: TextScaler.linear(fontScale / scale),
    );

    return _KeyboardDismissOnTap(
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

class _KeyboardDismissOnTap extends StatelessWidget {
  const _KeyboardDismissOnTap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final focus = FocusManager.instance.primaryFocus;
        if (focus == null || !focus.hasFocus) return;

        final renderObject = focus.context?.findRenderObject();
        if (renderObject is RenderBox && renderObject.attached) {
          final topLeft = renderObject.localToGlobal(Offset.zero);
          final rect = topLeft & renderObject.size;
          if (rect.contains(event.position)) return;
        }

        focus.unfocus();
      },
      child: child,
    );
  }
}
