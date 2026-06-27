//
//  main.dart
//
//  MithkaApp entry point. Wires the controllers (AuthManager, ThemeController,
//  AccountStore, DrawerController) as providers, applies the adaptive theme +
//  themeMode, and keys the content on the active account so the whole tree
//  rebuilds for the newly active account. Port of the Swift `MithkaApp`.
//

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/content_view.dart';
import 'app/app_version.dart';
import 'app/app_navigator.dart';
import 'auth/account_store.dart';
import 'auth/auth_manager.dart';
import 'components/drawer_controller.dart' as dc;
import 'l10n/app_locale_controller.dart';
import 'l10n/app_localizations.dart';
import 'notifications/notification_controller.dart';
import 'settings/keyword_blocker.dart';
import 'settings/translation_controller.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

const _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const _sentryEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'production',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Route video_player through the MDK/FFmpeg backend so .webm (VP9 + alpha)
  // video stickers decode + play (and stay transparent).
  //
  // MDK's Android hardware decoder path uses AMediaCodec. Some Android 14 /
  // HyperOS builds crash natively in AMediaCodec_dequeueInputBuffer, so Android
  // uses software decoders first. Video stickers are small enough that this is a
  // better tradeoff than risking a process abort.
  fvp.registerWith(
    options: defaultTargetPlatform == TargetPlatform.android
        ? {
            'video.decoders': ['FFmpeg', 'dav1d'],
          }
        : null,
  );
  // Let iPhone and iPad follow every physical orientation.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await Firebase.initializeApp();
  final appVersion = await AppVersion.load();
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
  await FirebaseAnalytics.instance.setDefaultEventParameters(
    appVersion.analyticsParameters,
  );
  await FirebaseAnalytics.instance.logAppOpen(
    parameters: appVersion.analyticsParameters,
  );
  final prefs = await SharedPreferences.getInstance();
  KeywordBlocker.shared.initialize(prefs);
  final app = MithkaApp(prefs: prefs);
  if (_sentryDsn.isEmpty) {
    runApp(app);
    return;
  }

  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn;
    options.environment = _sentryEnvironment;
    options.release = 'mithka@${appVersion.version}+${appVersion.buildNumber}';
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0;
  }, appRunner: () => runApp(app));
}

class MithkaApp extends StatefulWidget {
  const MithkaApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<MithkaApp> createState() => _MithkaAppState();
}

class _MithkaAppState extends State<MithkaApp> {
  late final AuthManager _auth = AuthManager();
  late final ThemeController _theme = ThemeController(widget.prefs);
  late final TranslationController _translation = TranslationController(
    widget.prefs,
  );
  late final AppLocaleController _locale = AppLocaleController(widget.prefs);
  late final AccountStore _accounts = AccountStore(widget.prefs);
  late final dc.DrawerController _drawer = dc.DrawerController();

  @override
  void initState() {
    super.initState();
    _auth.start();
    NotificationController.shared.start();
  }

  ThemeData _themeData(Brightness brightness, ThemeController theme) {
    final fontChoice = theme.fontChoice;
    final cjkFontChoice = theme.cjkFontChoice;
    final customPrimary = theme.customPrimaryFontFamily;
    final customCjk = theme.customCjkFontFamily;
    final colors = brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
    final fallback = fontChoice.effectiveFallback(
      cjkFontChoice,
      null,
      customCjk,
    );
    final useCustomPrimary =
        fontChoice.isCustom && customPrimary.trim().isNotEmpty;
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: useCustomPrimary ? customPrimary : fontChoice.fontFamily,
      fontFamilyFallback: fallback,
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
      textTheme: fontChoice.applyTextTheme(
        base.textTheme,
        cjkFallback: cjkFontChoice,
        customPrimaryFamily: customPrimary,
        customCjkFamily: customCjk,
      ),
      primaryTextTheme: fontChoice.applyTextTheme(
        base.primaryTextTheme,
        cjkFallback: cjkFontChoice,
        customPrimaryFamily: customPrimary,
        customCjkFamily: customCjk,
      ),
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
        ChangeNotifierProvider.value(value: _accounts),
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
            navigatorObservers: [
              FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
            ],
            theme: _themeData(Brightness.light, theme),
            darkTheme: _themeData(Brightness.dark, theme),
            themeMode: theme.themeMode,
            // Apply the user's chosen font size app-wide (设置 › 通用 › 字体大小).
            builder: (context, child) {
              return _ScaledAppView(
                fontScale: theme.fontScale,
                interfaceScale: theme.interfaceScale,
                child: child ?? const SizedBox.shrink(),
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
      final offset = Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(position: offset, child: child),
      );
    }

    final offset = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: animation,
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
