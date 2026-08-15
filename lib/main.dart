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

import 'package:f_videoplayer/f_videoplayer.dart';
import 'package:f_videoplayer_fvp/f_videoplayer_fvp.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_navigator.dart';
import 'app/app_performance_controller.dart';
import 'app/app_version.dart';
import 'app/chat_deep_link_controller.dart';
import 'app/content_view.dart';
import 'app/deep_link_service.dart';
import 'app/desktop_chat_window.dart';
import 'app/desktop_hotkey_host.dart';
import 'app/desktop_image_preview_window.dart';
import 'app/desktop_mini_app_window.dart';
import 'app/desktop_mini_app_window_app.dart';
import 'app/desktop_utility_window.dart';
import 'app/desktop_video_window.dart';
import 'app/desktop_window_controls.dart';
import 'app/global_video_split_host.dart';
import 'app/handoff_service.dart';
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
import 'media/video_view_compatibility.dart';
import 'notifications/in_app_notification_banner.dart';
import 'notifications/notification_controller.dart';
import 'notifications/notification_preferences.dart';
import 'notifications/push_device_registrar.dart';
import 'platform/application_exit_coordinator.dart';
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
import 'settings/desktop_hotkey_controller.dart';
import 'settings/developer_mode_controller.dart';
import 'settings/keyword_blocker.dart';
import 'settings/safety_notice_controller.dart';
import 'settings/sensitive_content_controller.dart';
import 'settings/translation_controller.dart';
import 'tdlib/td_client.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// Loads the locale catalogue before the first frame.
///
/// Strings come from assets now, so every entry point — the app and each
/// desktop child window — has to await this or its early widgets render bare
/// keys. [prefs] supplies the saved language when the entry point has it;
/// without it the window follows the system language.
Future<void> _preloadLocaleCatalogue([SharedPreferences? prefs]) {
  WidgetsFlutterBinding.ensureInitialized();
  Locale? saved;
  if (prefs != null) {
    // Only the stored value is wanted here; the tree builds its own controller.
    final reader = AppLocaleController(prefs);
    saved = reader.locale;
    reader.dispose();
  }
  final locale = saved ?? ui.PlatformDispatcher.instance.locale;
  AppStrings.setLocale(locale);
  return AppStrings.ensureLoaded(locale);
}

Future<void> main(List<String> arguments) async {
  if (supportsDesktopVideoWindows) {
    final videoArguments = await FVideoDesktopWindows.initialize(arguments);
    if (videoArguments != null) {
      _initializeVideoBackend(installGlobalLogHandler: false);
      await _preloadLocaleCatalogue();
      runApp(DesktopVideoWindowApp(arguments: videoArguments));
      return;
    }
    final miniAppArguments =
        DesktopMiniAppWindowArguments.tryParseLaunchArguments(arguments);
    if (miniAppArguments != null) {
      configureAppImageCache();
      final launch = await DesktopMiniAppWindowService.instance
          .configureChildProxy(miniAppArguments);
      final prefs = await SharedPreferences.getInstance();
      await Future.wait<void>([
        _preloadLocaleCatalogue(prefs),
        ThemeController.preloadCachedEmojiFont(prefs),
      ]);
      runApp(DesktopMiniAppWindowApp(launch: launch, prefs: prefs));
      return;
    }
    final imageArguments =
        DesktopImagePreviewWindowArguments.tryParseLaunchArguments(arguments);
    if (imageArguments != null) {
      configureAppImageCache();
      await _preloadLocaleCatalogue();
      runApp(DesktopImagePreviewWindowApp(arguments: imageArguments));
      return;
    }
    final utilityArguments =
        DesktopUtilityWindowArguments.tryParseLaunchArguments(arguments);
    if (utilityArguments != null) {
      configureAppImageCache();
      _initializeVideoBackend(installGlobalLogHandler: false);
      await DesktopUtilityWindowService.instance.configureChildProxy(
        utilityArguments,
      );
      final prefs = await SharedPreferences.getInstance();
      DesktopHotkeyController.initializeShared(prefs, replace: true);
      await Future.wait<void>([
        _preloadLocaleCatalogue(prefs),
        ThemeController.preloadCachedEmojiFont(prefs),
      ]);
      runApp(
        DesktopUtilityWindowApp(arguments: utilityArguments, prefs: prefs),
      );
      return;
    }
    final chatArguments = DesktopChatWindowArguments.tryParseLaunchArguments(
      arguments,
    );
    if (chatArguments != null) {
      configureAppImageCache();
      _initializeVideoBackend(installGlobalLogHandler: false);
      await DesktopChatWindowService.instance.configureChildProxy(
        chatArguments,
      );
      final prefs = await SharedPreferences.getInstance();
      await Future.wait<void>([
        _preloadLocaleCatalogue(prefs),
        ThemeController.preloadCachedEmojiFont(prefs),
      ]);
      runApp(DesktopChatWindowApp(arguments: chatArguments, prefs: prefs));
      return;
    }
    await configurePrimaryDesktopWindowChrome();
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
  // Register before AuthManager starts TDLib. Flutter's macOS delegate waits
  // for this cancelable exit response, so even a very early Quit drains native
  // clients before AppKit unloads libtdjson.
  try {
    await ApplicationExitCoordinator.install().timeout(
      const Duration(seconds: 5),
    );
  } catch (error) {
    // A broken lifecycle channel must not prevent Flutter from presenting the
    // login screen. The native bridge still has a mandatory-exit fallback.
    debugPrint('Application exit coordination unavailable at startup: $error');
  }
  GoogleFonts.config.allowRuntimeFetching = true;
  // Bring TDLib up first: session restore is the longest serial chain in a
  // launch, and nothing below depends on it — the widget tree attaches to
  // AuthManager's stream whenever it is ready.
  final auth = AuthManager()..start();
  _initializeVideoBackend();
  final isMobile =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  if (isMobile) {
    // Let iPhone and iPad follow every physical orientation. Desktop windows
    // have no orientation/system bars — skip both platform-channel round
    // trips there. Nothing below reads the reply, and it only lands once the
    // Activity has processed it, so it must not sit on the chain to runApp.
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    // Draw under transparent status / navigation bars (edge-to-edge).
    configureImmersiveSystemUI();
  }
  final prefs = await SharedPreferences.getInstance();
  // These must land before the first frame — the catalogue or early widgets
  // render bare keys, the lock or the chat list flashes before the gate, and
  // video surfaces must be selected before any controller is created. Their
  // platform and asset reads are independent, so they overlap.
  await Future.wait<void>([
    _preloadLocaleCatalogue(prefs),
    LocalAppLockController.shared.initialize(),
    ThemeController.preloadCachedEmojiFont(prefs),
    initializeCompatibleVideoViewType(),
  ]);
  DesktopHotkeyController.initializeShared(prefs, replace: true);
  KeywordBlocker.shared.initialize(prefs);
  CountryMessageFilter.shared.initialize(prefs);
  unawaited(SensitiveContentController.shared.initialize());
  MusicPlayerController.shared.initialize(prefs);
  // Preload Telegram blocked-user list so chat filters have data right away.
  unawaited(BlockedUserService.shared.loadBlockedUsers());
  // Firebase + analytics + Sentry tags are several platform-channel round
  // trips that nothing in the widget tree depends on. Firebase's own init runs
  // on the calling platform thread, so hold it until the scheduler is idle
  // instead of letting it contend with the channel traffic launch needs.
  unawaited(
    SchedulerBinding.instance.scheduleTask<void>(_initTelemetry, Priority.idle),
  );
  final app = MithkaApp(prefs: prefs, auth: auth);
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

void _initializeVideoBackend({bool installGlobalLogHandler = true}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FVideoFvpBackend.ensureAndroidAlphaWebmDecoderInitialized();
    return;
  }
  if (!_shouldUseFvp()) return;
  FVideoFvpBackend.ensureInitialized(
    configuration: FVideoFvpConfiguration(
      platforms: {
        FVideoFvpPlatform.ios,
        FVideoFvpPlatform.linux,
        FVideoFvpPlatform.macos,
        FVideoFvpPlatform.windows,
      },
      installGlobalLogHandler: installGlobalLogHandler,
    ),
  );
}

Future<void> _initTelemetry() async {
  try {
    // Two unrelated platform channels — awaiting them in turn costs an extra
    // round trip on a platform thread that launch is already contending for.
    final (hasFirebaseConfiguration, appVersion) = await (
      FirebaseConfiguration.isAvailable,
      AppVersion.load(),
    ).wait;
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
    Consumer3<ThemeController, AccountStore, AppLocaleController>;

class MithkaApp extends StatefulWidget {
  const MithkaApp({super.key, required this.prefs, this.auth});
  final SharedPreferences prefs;

  /// Bootstrap-started AuthManager, so TDLib session restore runs in
  /// parallel with the first build instead of after it.
  final AuthManager? auth;

  @override
  State<MithkaApp> createState() => _MithkaAppState();
}

class _MithkaAppState extends State<MithkaApp> with WidgetsBindingObserver {
  late final AuthManager _auth = widget.auth ?? AuthManager();
  late final AccountStore _accounts = AccountStore(widget.prefs);
  late final MithkaProService _mithkaPro = MithkaProService.shared;
  late ThemeController _theme = ThemeController(
    widget.prefs,
    initialAccountSlot: _accounts.activeSlot,
    initialAccountUserId: _accounts.activeUserId,
  );
  late TranslationController _translation = TranslationController(widget.prefs);
  late AiSettingsController _ai = AiSettingsController(widget.prefs);
  late AppLocaleController _locale = AppLocaleController(widget.prefs);
  late final dc.DrawerController _drawer = dc.DrawerController();
  late final ChatDeepLinkController _chatDeepLinks =
      ChatDeepLinkController.shared;
  late final GroupRemarkController _groupRemarks = GroupRemarkController(
    widget.prefs,
    initialAccountUserId: _accounts.activeUserId,
  );
  late AppIconController _appIcons = AppIconController(widget.prefs);
  late final AutoDownloadMediaController _autoDownload =
      AutoDownloadMediaController.shared;
  late DeveloperModeController _developer = DeveloperModeController(
    widget.prefs,
  );
  late AppPerformanceController _performance = AppPerformanceController(
    widget.prefs,
    memoryTrimmers: [clearChatMemoryCaches, clearAnimatedStickerMemoryCache],
  );
  late SafetyNoticeController _safetyNotice = SafetyNoticeController(
    widget.prefs,
  );
  late final SensitiveContentController _sensitiveContent =
      SensitiveContentController.shared;
  late final LocalAppLockController _appLock = LocalAppLockController.shared;
  late final CallManager _calls = CallManager()..start();
  bool _desktopSettingsReloading = false;
  bool _desktopSettingsReloadQueued = false;

  /// Whether the app has actually been in the background since the last
  /// resume. Starts true so the first resume of a session still refreshes.
  bool _wasBackgrounded = true;

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
    // FontLoader.load registers a multi-MB colour font on the UI thread and
    // invalidates the font collection, forcing a re-layout of every laid-out
    // string. Text renders with the platform emoji fallback until it lands,
    // so it waits for a gap in the scheduler instead of the launch frames.
    unawaited(
      SchedulerBinding.instance.scheduleTask<void>(
        _theme.loadSelectedEmojiFontIfAvailable,
        Priority.idle,
      ),
    );
    _autoDownload.initialize(widget.prefs);
    _auth.start();
    DeepLinkService.shared.start();
    HandoffService.shared.start(
      accounts: _accounts,
      auth: _auth,
      appLock: _appLock,
    );
    DesktopMiniAppWindowService.instance.attachMainProxy();
    DesktopChatWindowService.instance.attachMainProxy(
      accountUserIdForSlot: _accountUserIdForSlot,
    );
    DesktopUtilityWindowService.instance.attachMainProxy(
      onSettingsChanged: _reloadDesktopSettings,
      accountUserIdForSlot: _accountUserIdForSlot,
    );
    unawaited(_ai.initialize());
    // Binding the store and querying its catalogue is platform + network work
    // that nothing on the launch path reads — the paywall re-initializes it
    // itself if it opens first.
    unawaited(
      SchedulerBinding.instance.scheduleTask<void>(
        _mithkaPro.initialize,
        Priority.idle,
      ),
    );
    unawaited(_appIcons.initialize());
    unawaited(_accounts.recoverPendingAddOnStartup(_auth));
    NotificationController.shared.start(widget.prefs);
    // An iOS registerForRemoteNotifications round trip that nothing observes
    // during launch.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PushDeviceRegistrar.shared.start(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _performance.dispose();
    _accounts.removeListener(_handleActiveAccountChange);
    _theme.removeListener(_handleThemePreferencesChange);
    _groupRemarks.dispose();
    DesktopMiniAppWindowService.instance.detachMainProxy();
    DesktopChatWindowService.instance.detachMainProxy();
    DesktopUtilityWindowService.instance.detachMainProxy();
    unawaited(HandoffService.shared.stop());
    _calls.dispose();
    super.dispose();
  }

  void _handleActiveAccountChange() {
    _groupRemarks.setActiveAccountUserId(_accounts.activeUserId);
    _theme.setActiveAccountSlot(
      _accounts.activeSlot,
      userId: _accounts.activeUserId,
    );
    DesktopMiniAppWindowService.instance.notifyAccountIdentityChanged();
    DesktopChatWindowService.instance.notifyAccountIdentityChanged();
    DesktopUtilityWindowService.instance.notifyAccountIdentityChanged();
  }

  int? _accountUserIdForSlot(int slot) {
    for (final account in _accounts.summaries) {
      if (account.slot == slot) return account.userId;
    }
    return null;
  }

  void _handleThemePreferencesChange() {
    BusinessQuickReplyService.shared.setPreloadingEnabled(
      _theme.quickRepliesEnabled,
    );
    unawaited(
      DesktopImagePreviewWindowService.instance.broadcastBrightness(
        _resolvedDesktopDark,
      ),
    );
    unawaited(DesktopChatWindowService.instance.notifyPresentationChanged());
  }

  bool get _resolvedDesktopDark => switch (_theme.mode) {
    AppearanceMode.light => false,
    AppearanceMode.dark => true,
    AppearanceMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark,
  };

  Future<void> _reloadDesktopSettings() async {
    if (_desktopSettingsReloading) {
      _desktopSettingsReloadQueued = true;
      return;
    }
    _desktopSettingsReloading = true;
    try {
      do {
        _desktopSettingsReloadQueued = false;
        await widget.prefs.reload();
        await DesktopHotkeyController.shared.reload();
        NotificationPreferences.shared.initialize(widget.prefs);
        if (!mounted) return;

        final previousTheme = _theme;
        final previousTranslation = _translation;
        final previousAi = _ai;
        final previousLocale = _locale;
        final previousAppIcons = _appIcons;
        final previousDeveloper = _developer;
        final previousPerformance = _performance;
        final previousSafetyNotice = _safetyNotice;

        final nextTheme = ThemeController(
          widget.prefs,
          initialAccountSlot: _accounts.activeSlot,
          initialAccountUserId: _accounts.activeUserId,
        );
        final nextTranslation = TranslationController(widget.prefs);
        final nextAi = AiSettingsController(widget.prefs);
        final nextLocale = AppLocaleController(widget.prefs);
        final nextAppIcons = AppIconController(widget.prefs);
        final nextDeveloper = DeveloperModeController(widget.prefs);
        final nextPerformance = AppPerformanceController(
          widget.prefs,
          memoryTrimmers: [
            clearChatMemoryCaches,
            clearAnimatedStickerMemoryCache,
          ],
        )..start();
        final nextSafetyNotice = SafetyNoticeController(widget.prefs);

        previousTheme.removeListener(_handleThemePreferencesChange);
        nextTheme.addListener(_handleThemePreferencesChange);
        BusinessQuickReplyService.shared.setPreloadingEnabled(
          nextTheme.quickRepliesEnabled,
        );
        unawaited(
          SchedulerBinding.instance.scheduleTask<void>(
            nextTheme.loadSelectedEmojiFontIfAvailable,
            Priority.idle,
          ),
        );

        _autoDownload.initialize(widget.prefs);
        KeywordBlocker.shared.initialize(widget.prefs);
        CountryMessageFilter.shared.initialize(widget.prefs);
        MusicPlayerController.shared.initialize(widget.prefs);
        BlockedUserService.shared.enabled = nextTheme.hideBlockedUserMessages;
        if (nextTheme.hideBlockedUserMessages) {
          unawaited(BlockedUserService.shared.loadBlockedUsers());
        }
        unawaited(_appLock.reloadFromStorage());
        unawaited(_mithkaPro.refresh());
        unawaited(nextAi.initialize());
        unawaited(nextAppIcons.initialize());

        setState(() {
          _theme = nextTheme;
          _translation = nextTranslation;
          _ai = nextAi;
          _locale = nextLocale;
          _appIcons = nextAppIcons;
          _developer = nextDeveloper;
          _performance = nextPerformance;
          _safetyNotice = nextSafetyNotice;
        });
        unawaited(
          DesktopImagePreviewWindowService.instance.broadcastBrightness(
            _resolvedDesktopDark,
          ),
        );
        unawaited(
          DesktopChatWindowService.instance.notifyPresentationChanged(),
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          previousPerformance.dispose();
          previousAppIcons.dispose();
          previousDeveloper.dispose();
          previousSafetyNotice.dispose();
          previousLocale.dispose();
          previousAi.dispose();
          previousTranslation.dispose();
          previousTheme.dispose();
        });
      } while (_desktopSettingsReloadQueued && mounted);
    } finally {
      _desktopSettingsReloading = false;
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (_theme.mode != AppearanceMode.system) return;
    unawaited(
      DesktopImagePreviewWindowService.instance.broadcastBrightness(
        _resolvedDesktopDark,
      ),
    );
    unawaited(DesktopChatWindowService.instance.notifyPresentationChanged());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLock.handleLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      // `inactive` on its own is a Control Center glance, the notification
      // shade or a permission sheet — the app never actually left.
      if (state != AppLifecycleState.inactive) _wasBackgrounded = true;
      return;
    }
    TdClient.shared.restartReceiveIsolate();
    // Refreshing per glance is a store network round trip for an entitlement
    // that cannot have moved; purchases arrive through the gateway's own
    // transaction listener, never through this poll.
    if (!_wasBackgrounded) return;
    _wasBackgrounded = false;
    unawaited(_mithkaPro.refresh());
  }

  /// Last [_themeData] result per brightness, with the inputs it was built
  /// from. `ColorScheme.fromSeed` is uncached HCT colour science and both
  /// brightnesses are rebuilt on every ThemeController notification, almost
  /// all of which (a toggle, a slider step) change nothing the theme reads.
  final Map<Brightness, _ThemeDataMemo> _themeDataMemo = {};

  ThemeData _themeData(Brightness brightness, ThemeController theme) {
    final colors = theme.uiColorsFor(brightness);
    final families = theme.effectiveFontFamilyChain();
    final seedColor = theme.usesCloudThemeForUi(brightness)
        ? colors.linkBlue
        : theme.brandColor;
    final memo = _themeDataMemo[brightness];
    if (memo != null &&
        memo.colors == colors &&
        memo.seedColor == seedColor &&
        listEquals(memo.families, families)) {
      return memo.data;
    }
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: families.isEmpty ? null : families.first,
      fontFamilyFallback: families.length > 1
          ? families.skip(1).toList()
          : null,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
        },
      ),
      extensions: [colors],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
    final data = base.copyWith(
      textTheme: theme.applyAppTextTheme(base.textTheme),
      primaryTextTheme: theme.applyAppTextTheme(base.primaryTextTheme),
    );
    _themeDataMemo[brightness] = _ThemeDataMemo(
      colors: colors,
      families: families,
      seedColor: seedColor,
      data: data,
    );
    return data;
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
        builder: (context, theme, accounts, locale, _) {
          return MaterialApp(
            navigatorKey: appNavigatorKey,
            title: 'Mithka',
            debugShowCheckedModeBanner: false,
            // Null follows the system language, which is what
            // AppLocaleController stores for "follow system".
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
              // Aspect-scoped: MediaQuery.of would re-run this whole closure on
              // every keyboard-inset and window-resize frame just to read
              // boldText.
              final boldText = MediaQuery.boldTextOf(context);
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
                    boldText: boldText,
                  ),
                  primaryTextTheme: theme.applyAppTextTheme(
                    currentTheme.primaryTextTheme,
                    boldText: boldText,
                  ),
                ),
                // Cupertino-rooted screens (SearchView and friends) sit under no
                // text style of their own, so any Text that omits a decoration
                // inherits Flutter's yellow "unstyled" underline. A Material
                // ancestor would also fix it, but the app avoids Material
                // surfaces and only the text default is actually missing.
                child: DefaultTextStyle.merge(
                  style: const TextStyle(decoration: TextDecoration.none),
                  child: child ?? const SizedBox.shrink(),
                ),
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
              final framedUnlockedApp = DesktopPrimaryWindowFrame(
                key: desktopPrimaryWindowIdentityKey(
                  accounts.activeSlot,
                  accounts.activeUserId,
                ),
                accountReady: context.watch<AuthManager>().step is AuthReady,
                child: unlockedApp,
              );
              final appLock = context.watch<LocalAppLockController>();
              final appChild = Stack(
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      excluding: appLock.locked,
                      child: framedUnlockedApp,
                    ),
                  ),
                  const Positioned.fill(child: LocalAppLockGate()),
                ],
              );
              final hotkeyController = DesktopHotkeyController.shared;
              final hotkeyChild = DesktopHotkeyHost(
                controller: hotkeyController,
                child: DesktopPrimaryHotkeyBindings(
                  controller: hotkeyController,
                  child: appChild,
                ),
              );
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: systemUiOverlayStyleForSurface(context.colors.navBar),
                child: _ScaledAppView(
                  fontScale: theme.fontScale,
                  interfaceScale: theme.renderedInterfaceScale,
                  child: DefaultTextStyle(
                    style: theme.applyAppTextStyle(
                      AppTextStyle.body(context.colors.textPrimary),
                      boldText: boldText,
                    ),
                    child: hotkeyChild,
                  ),
                ),
              );
            },
            // Rebuild the whole tree when the active account changes.
            home: KeyedSubtree(
              key: ValueKey((accounts.activeSlot, accounts.activeUserId)),
              child: const ContentView(),
            ),
          );
        },
      ),
    );
  }
}

/// A built [ThemeData] together with everything [_MithkaAppState._themeData]
/// read to build it. Font scale and interface scale are deliberately absent:
/// they are applied downstream by `_ScaledAppView`, never by the theme.
class _ThemeDataMemo {
  const _ThemeDataMemo({
    required this.colors,
    required this.families,
    required this.seedColor,
    required this.data,
  });

  final AppColors colors;
  final List<String> families;
  final Color seedColor;
  final ThemeData data;
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
