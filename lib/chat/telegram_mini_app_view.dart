//
//  telegram_mini_app_view.dart
//
//  In-app host for Telegram Mini Apps opened from bot menus and Web App
//  keyboard buttons. TDLib supplies the authenticated launch URL; this view
//  supplies the small native bridge surface expected by telegram-web-app.js.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../chats/qr_scanner_view.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../moments/story_authoring_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'bot_platform_service.dart';
import 'chat_picker_view.dart';
import 'custom_emoji.dart';
import 'link_handler.dart';
import 'telegram_invoice_checkout_view.dart';
import 'telegram_mini_app_platform.dart';
import 'telegram_mini_app_recents.dart';

class TelegramMiniAppLaunch {
  const TelegramMiniAppLaunch({
    required this.title,
    required this.url,
    required this.botUserId,
    required this.chatId,
    this.launchId,
    this.keyboardButtonText,
  });

  final String title;
  final String url;
  final int botUserId;
  final int chatId;
  final int? launchId;
  final String? keyboardButtonText;

  bool get canSendData =>
      keyboardButtonText != null && keyboardButtonText!.isNotEmpty;
}

Future<bool> openTelegramMiniApp(
  BuildContext context, {
  required int chatId,
  required int botUserId,
  required String url,
  required String title,
  String? keyboardButtonText,
  bool mainWebApp = false,
  bool menuWebApp = false,
  bool attachmentMenuWebApp = false,
  String startParameter = '',
  String webAppShortName = '',
  bool allowWriteAccess = false,
  Map<String, dynamic>? openMode,
  TdFileRef? photo,
}) async {
  final launch = await _resolveMiniAppLaunch(
    context,
    chatId: chatId,
    botUserId: botUserId,
    url: url,
    title: title,
    keyboardButtonText: keyboardButtonText,
    mainWebApp: mainWebApp,
    menuWebApp: menuWebApp,
    attachmentMenuWebApp: attachmentMenuWebApp,
    startParameter: startParameter,
    webAppShortName: webAppShortName,
    allowWriteAccess: allowWriteAccess,
    openMode: openMode,
  );
  if (launch == null || !context.mounted) return false;
  unawaited(
    TelegramMiniAppRecents.record(
      title: title,
      url: url,
      botUserId: botUserId,
      chatId: chatId,
      keyboardButtonText: keyboardButtonText,
      mainWebApp: mainWebApp,
      startParameter: startParameter,
      webAppShortName: webAppShortName,
      allowWriteAccess: allowWriteAccess,
      photo: photo,
    ),
  );
  await showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Mini app',
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => _MiniAppDialogHost(launch: launch),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
  return true;
}

class _MiniAppDialogHost extends StatefulWidget {
  const _MiniAppDialogHost({required this.launch});

  final TelegramMiniAppLaunch launch;

  @override
  State<_MiniAppDialogHost> createState() => _MiniAppDialogHostState();
}

class _MiniAppDialogHostState extends State<_MiniAppDialogHost> {
  bool _fullscreen = false;

  @override
  Widget build(BuildContext context) {
    final radius = _fullscreen
        ? BorderRadius.zero
        : const BorderRadius.vertical(top: Radius.circular(24));
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.88, end: _fullscreen ? 1 : 0.88),
      builder: (context, heightFactor, _) => Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: heightFactor,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.background,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: _fullscreen ? 0 : 32,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: TelegramMiniAppView(
                launch: widget.launch,
                fullscreen: _fullscreen,
                onFullscreenChanged: (value) {
                  if (mounted) setState(() => _fullscreen = value);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<TelegramMiniAppLaunch?> _resolveMiniAppLaunch(
  BuildContext context, {
  required int chatId,
  required int botUserId,
  required String url,
  required String title,
  String? keyboardButtonText,
  bool mainWebApp = false,
  bool menuWebApp = false,
  bool attachmentMenuWebApp = false,
  String startParameter = '',
  String webAppShortName = '',
  bool allowWriteAccess = false,
  Map<String, dynamic>? openMode,
}) async {
  try {
    final parameters = _webAppOpenParameters(context, mode: openMode);
    if (attachmentMenuWebApp &&
        !await _ensureAttachmentMenuBot(
          context,
          botUserId: botUserId,
          allowWriteAccess: allowWriteAccess,
        )) {
      return null;
    }
    if (mainWebApp) {
      final app = await TdClient.shared.query({
        '@type': 'getMainWebApp',
        'chat_id': 0,
        'bot_user_id': botUserId,
        'start_parameter': startParameter,
        'parameters': parameters,
      });
      final resolvedUrl = _launchUrlFrom(app);
      if (resolvedUrl == null || resolvedUrl.isEmpty) return null;
      return TelegramMiniAppLaunch(
        title: title,
        url: resolvedUrl,
        botUserId: botUserId,
        chatId: chatId,
      );
    }

    if (menuWebApp) {
      // TDLib recognises menu:// URLs and translates them to a
      // messages.requestWebView call with from_bot_menu set. Stripping the
      // marker turns BotFather's internal menu into a different request and
      // produces BOT_INVALID.
      return _openAuthorizedWebApp(
        chatId: chatId,
        botUserId: botUserId,
        url: url,
        title: title,
        parameters: parameters,
      );
    }

    if (webAppShortName.isNotEmpty) {
      final resolved = await TdClient.shared.query({
        '@type': 'getWebAppLinkUrl',
        'chat_id': 0,
        'bot_user_id': botUserId,
        'web_app_short_name': webAppShortName,
        'start_parameter': startParameter,
        'allow_write_access': allowWriteAccess,
        'parameters': parameters,
      });
      final resolvedUrl = _launchUrlFrom(resolved);
      if (resolvedUrl == null || resolvedUrl.isEmpty) return null;
      return TelegramMiniAppLaunch(
        title: title,
        url: resolvedUrl,
        botUserId: botUserId,
        chatId: chatId,
      );
    }

    if (keyboardButtonText != null && keyboardButtonText.isNotEmpty) {
      try {
        final resolved = await TdClient.shared.query({
          '@type': 'getWebAppUrl',
          'bot_user_id': botUserId,
          // TDLib uses this suffix to select messages.requestSimpleWebView for
          // a reply-keyboard button. It is already present in current TDLib
          // message objects, but retaining it here makes old cached messages
          // use the same authenticated path.
          'url': _keyboardWebAppUrl(url),
          'parameters': parameters,
        });
        final resolvedUrl = _launchUrlFrom(resolved);
        if (resolvedUrl != null && _containsWebAppInitData(resolvedUrl)) {
          return TelegramMiniAppLaunch(
            title: title,
            url: resolvedUrl,
            botUserId: botUserId,
            chatId: chatId,
            keyboardButtonText: keyboardButtonText,
          );
        }
      } catch (_) {
        // Some TDLib builds return an unsigned simple-WebView URL for a
        // reply-keyboard button. The regular Web App request remains signed
        // and keeps the Mini App functional in that case.
      }
      return _openAuthorizedWebApp(
        title: title,
        botUserId: botUserId,
        chatId: chatId,
        url: url,
        parameters: parameters,
        keyboardButtonText: keyboardButtonText,
      );
    }

    return _openAuthorizedWebApp(
      chatId: chatId,
      botUserId: botUserId,
      url: url,
      title: title,
      parameters: parameters,
    );
  } catch (error) {
    debugPrint('Mini App launch failed for bot $botUserId: $error');
    return null;
  }
}

Future<bool> _ensureAttachmentMenuBot(
  BuildContext context, {
  required int botUserId,
  required bool allowWriteAccess,
}) async {
  final service = MiniAppPlatformService(
    botUserId: botUserId,
    clientId: TdClient.shared.activeClientId,
  );
  try {
    final bot = await service.attachmentMenuBot();
    if (bot == null) return false;
    if (bot.boolean('is_added') ?? false) return true;
    if (!context.mounted) return false;
    final name = bot.str('name')?.trim();
    final accepted = await showAppConfirmDialog(
      context,
      title: AppStrings.t(
        AppStringKeys.telegramMiniAppThirdPartyAttachmentPrompt,
        {
          'value1': name == null || name.isEmpty
              ? AppStrings.t(AppStringKeys.telegramMiniAppThisMiniApp)
              : name,
        },
      ),
      confirmText: AppStringKeys.chatInfoCreate,
    );
    if (!accepted) return false;
    await service.setAttachmentMenuInstalled(
      installed: true,
      allowWriteAccess:
          allowWriteAccess || (bot.boolean('request_write_access') ?? false),
    );
    return true;
  } catch (_) {
    return false;
  } finally {
    service.dispose();
  }
}

Future<TelegramMiniAppLaunch?> _openAuthorizedWebApp({
  required int chatId,
  required int botUserId,
  required String url,
  required String title,
  required Map<String, dynamic> parameters,
  String? keyboardButtonText,
}) async {
  final info = await TdClient.shared.query({
    '@type': 'openWebApp',
    'chat_id': chatId,
    'bot_user_id': botUserId,
    'url': url,
    'topic_id': null,
    'reply_to': null,
    'parameters': parameters,
  });
  final resolvedUrl = _launchUrlFrom(info);
  if (resolvedUrl == null || resolvedUrl.isEmpty) return null;
  return TelegramMiniAppLaunch(
    title: title,
    url: resolvedUrl,
    botUserId: botUserId,
    chatId: chatId,
    launchId: info.int64('launch_id'),
    keyboardButtonText: keyboardButtonText,
  );
}

String? _launchUrlFrom(Map<String, dynamic> response) {
  final candidates = <String>[];
  _collectLaunchUrls(response['url'], candidates);
  if (candidates.isNotEmpty) {
    // Prefer the URL that TDLib signed for Telegram.WebApp. Some generated
    // bindings wrap an HTTP URL and may expose the original and resolved URLs
    // together; loading the former drops the authentication payload.
    return candidates.firstWhere(
      _containsWebAppInitData,
      orElse: () => candidates.first,
    );
  }
  debugPrint(
    'Mini App launch returned ${response.type} with URL type '
    '${response['url'].runtimeType}',
  );
  return null;
}

void _collectLaunchUrls(Object? value, List<String> output) {
  if (value is String) {
    if (value.isNotEmpty) output.add(value);
    return;
  }
  if (value is! Map) return;
  for (final key in const ['url', 'value']) {
    _collectLaunchUrls(value[key], output);
  }
}

bool _containsWebAppInitData(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.queryParameters.containsKey('tgWebAppData')) return true;
  return Uri.splitQueryString(uri.fragment).containsKey('tgWebAppData');
}

Map<String, dynamic> _webAppOpenParameters(
  BuildContext context, {
  Map<String, dynamic>? mode,
}) {
  return {
    '@type': 'webAppOpenParameters',
    'theme': null,
    // Match Telegram's supported Mini App platform identifiers. In
    // particular, bots use this value when validating their launch data.
    'application_name': Platform.isIOS ? 'ios' : 'android',
    'mode': mode ?? {'@type': 'webAppOpenModeFullSize'},
  };
}

String _keyboardWebAppUrl(String url) {
  return url.endsWith('#kb') ? url : '$url#kb';
}

class TelegramMiniAppView extends StatefulWidget {
  const TelegramMiniAppView({
    super.key,
    required this.launch,
    this.fullscreen = false,
    this.onFullscreenChanged,
  });

  final TelegramMiniAppLaunch launch;
  final bool fullscreen;
  final ValueChanged<bool>? onFullscreenChanged;

  @override
  State<TelegramMiniAppView> createState() => _TelegramMiniAppViewState();
}

class _TelegramMiniAppViewState extends State<TelegramMiniAppView>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  late final MiniAppPlatformService _platform;
  late final MiniAppScopedStorage _storage;
  late final MiniAppBiometryController _biometry;
  late final BotPlatformService _botPlatform;
  final MiniAppMotionController _motion = MiniAppMotionController();
  var _progress = 0;
  var _pageReady = false;
  var _backButtonVisible = false;
  var _settingsButtonVisible = false;
  var _needClosingConfirmation = false;
  var _allowVerticalSwipe = true;
  var _downloadPending = false;
  var _popupOpen = false;
  var _invoiceOpen = false;
  var _qrScannerOpen = false;
  var _closeQrFromWeb = false;
  var _storySharePending = false;
  var _emojiStatusPending = false;
  var _orientationLocked = false;
  var _closedTdLaunch = false;
  final List<DateTime> _popupTimes = [];
  Color? _requestedBackgroundColor;
  Color? _requestedHeaderColor;
  Color? _requestedBottomColor;
  _MiniAppButtonState _mainButton = const _MiniAppButtonState();
  _MiniAppButtonState _secondaryButton = const _MiniAppButtonState();
  Timer? _viewportTimer;
  DateTime? _lastUserInteraction;
  DateTime? _lastBiometrySettingsOpen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final clientId = TdClient.shared.activeClientId;
    _platform = MiniAppPlatformService(
      botUserId: widget.launch.botUserId,
      clientId: clientId,
    );
    _storage = MiniAppScopedStorage(
      clientId: clientId,
      botUserId: widget.launch.botUserId,
    );
    _biometry = MiniAppBiometryController(
      clientId: clientId,
      botUserId: widget.launch.botUserId,
    );
    _botPlatform = BotPlatformService();
    _controller = _buildController();
    unawaited(_controller.loadRequest(Uri.parse(widget.launch.url)));
  }

  @override
  void dispose() {
    _viewportTimer?.cancel();
    unawaited(_motion.dispose(_emitEvent));
    _platform.dispose();
    if (_orientationLocked) {
      unawaited(
        SystemChrome.setPreferredOrientations(DeviceOrientation.values),
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    _notifyTdClosed();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _viewportTimer?.cancel();
    _viewportTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) unawaited(_sendViewportEvent());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    unawaited(_emitEvent('visibility_changed', {'is_visible': visible}));
    unawaited(_emitEvent(visible ? 'activated' : 'deactivated', const {}));
  }

  WebViewController _buildController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_miniAppUserAgent)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'MithkaTelegramBridge',
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (_) {
            unawaited(_installBridge());
          },
          onPageFinished: (_) async {
            await _installBridge();
            await _sendThemeEvent();
            await _sendViewportEvent();
            await _sendSafeAreaEvent();
            if (mounted) setState(() => _pageReady = true);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || _isWebNavigation(uri)) {
              return NavigationDecision.navigate;
            }
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
            return NavigationDecision.prevent;
          },
        ),
      )
      ..setOnJavaScriptAlertDialog((request) async {
        if (!mounted) return;
        await _showNativeDialog(
          title: widget.launch.title,
          message: request.message,
          buttons: [
            {
              'id': 'ok',
              'type': 'ok',
              'text': AppStrings.t(AppStringKeys.confirmOk),
            },
          ],
        );
      })
      ..setOnJavaScriptConfirmDialog((request) async {
        if (!mounted) return false;
        final result = await _showNativeDialog(
          title: widget.launch.title,
          message: request.message,
          buttons: [
            {
              'id': 'cancel',
              'type': 'cancel',
              'text': AppStrings.t(AppStringKeys.confirmCancel),
            },
            {
              'id': 'ok',
              'type': 'ok',
              'text': AppStrings.t(AppStringKeys.confirmOk),
            },
          ],
        );
        return result == 'ok';
      });

    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      unawaited(android.setMediaPlaybackRequiresUserGesture(false));
      if (kDebugMode) {
        unawaited(AndroidWebViewController.enableDebugging(true));
      }
    }
    return controller;
  }

  bool _isWebNavigation(Uri uri) {
    return uri.scheme == 'http' ||
        uri.scheme == 'https' ||
        uri.scheme == 'about' ||
        uri.scheme == 'data';
  }

  Future<void> _installBridge() {
    return _controller.runJavaScript(_telegramBridgeScript).catchError((_) {});
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    final payload = decodeMiniAppBridgePayload(message.message);
    if (payload == null) return;
    final eventType = payload.type;
    final eventData = payload.data;

    switch (eventType) {
      case 'web_app_user_interaction':
        _lastUserInteraction = DateTime.now();
      case 'web_app_ready':
        if (mounted) setState(() => _pageReady = true);
      case 'web_app_close':
        unawaited(_closeView());
      case 'web_app_expand':
        unawaited(_sendViewportEvent());
      case 'web_app_setup_back_button':
        final visible = eventData['is_visible'] == true;
        if (mounted) setState(() => _backButtonVisible = visible);
      case 'web_app_setup_main_button':
        if (mounted) {
          setState(() => _mainButton = _MiniAppButtonState.fromJson(eventData));
        }
      case 'web_app_setup_secondary_button':
        if (mounted) {
          setState(
            () => _secondaryButton = _MiniAppButtonState.fromJson(eventData),
          );
        }
      case 'web_app_setup_settings_button':
        if (mounted) {
          setState(
            () => _settingsButtonVisible = eventData['is_visible'] == true,
          );
        }
      case 'web_app_setup_closing_behavior':
        _needClosingConfirmation = eventData['need_confirmation'] == true;
      case 'web_app_setup_swipe_behavior':
        _allowVerticalSwipe = eventData['allow_vertical_swipe'] != false;
      case 'web_app_set_background_color':
        final color = _MiniAppButtonState.parseColor(
          eventData['color'] as String?,
        );
        if (mounted) setState(() => _requestedBackgroundColor = color);
      case 'web_app_set_header_color':
        final color = _requestedColor(eventData);
        if (mounted) setState(() => _requestedHeaderColor = color);
      case 'web_app_set_bottom_bar_color':
        final color = _MiniAppButtonState.parseColor(
          eventData['color'] as String?,
        );
        if (mounted) setState(() => _requestedBottomColor = color);
      case 'web_app_data_send':
        final data = eventData['data'];
        if (data is String) unawaited(_sendWebAppData(data));
      case 'web_app_open_link':
        final url = eventData['url'];
        if (url is String &&
            url.isNotEmpty &&
            _consumeRecentInteraction(const Duration(seconds: 1))) {
          unawaited(_openExternal(url));
        }
      case 'web_app_open_tg_link':
        final path = eventData['path_full'] ?? eventData['path'];
        if (path is String && path.isNotEmpty) {
          final link = path.startsWith('tg:') || path.startsWith('http')
              ? path
              : 'https://t.me$path';
          unawaited(openLink(context, link));
        }
      case 'web_app_request_theme':
        unawaited(_sendThemeEvent());
      case 'web_app_request_viewport':
        unawaited(_sendViewportEvent());
      case 'web_app_request_safe_area':
        unawaited(_sendSafeAreaEvent());
      case 'web_app_request_content_safe_area':
        unawaited(_sendContentSafeAreaEvent());
      case 'web_app_read_text_from_clipboard':
        unawaited(
          _sendClipboardText(
            eventData['req_id'] as String?,
            allowed: _hasRecentInteraction,
          ),
        );
      case 'web_app_open_popup':
        unawaited(_openPopup(eventData));
      case 'web_app_open_invoice':
        unawaited(_openInvoice(eventData));
      case 'web_app_open_scan_qr_popup':
        unawaited(_openQrScanner(eventData));
      case 'web_app_close_scan_qr_popup':
        _closeQrScannerFromWeb();
      case 'web_app_share_to_story':
        unawaited(_shareToStory(eventData));
      case 'web_app_set_emoji_status':
        unawaited(_setEmojiStatus(eventData));
      case 'web_app_request_emoji_status_access':
        unawaited(_requestEmojiStatusAccess());
      case 'web_app_trigger_haptic_feedback':
        unawaited(_triggerHaptic(eventData));
      case 'web_app_request_fullscreen':
        unawaited(_setFullscreen(true, blur: eventData['blur'] != false));
      case 'web_app_exit_fullscreen':
        unawaited(_setFullscreen(false));
      case 'web_app_toggle_orientation_lock':
        unawaited(_setOrientationLocked(eventData['locked'] == true));
      case 'web_app_add_to_home_screen':
        if (_hasRecentInteraction) {
          unawaited(_emitEvent('home_screen_failed', {'error': 'UNSUPPORTED'}));
        }
      case 'web_app_check_home_screen':
        unawaited(_emitEvent('home_screen_checked', {'status': 'unsupported'}));
      case 'web_app_request_file_download':
        unawaited(_requestDownload(eventData));
      case 'web_app_check_location':
        unawaited(_checkLocation());
      case 'web_app_request_location':
        unawaited(_requestLocation());
      case 'web_app_open_location_settings':
        if (_hasRecentInteraction) unawaited(_platform.openLocationSettings());
      case 'web_app_device_storage_save_key':
        unawaited(_saveStorage(eventData, secure: false));
      case 'web_app_device_storage_get_key':
        unawaited(_readStorage(eventData, secure: false));
      case 'web_app_device_storage_clear':
        unawaited(_clearStorage(eventData, secure: false));
      case 'web_app_secure_storage_save_key':
        unawaited(_saveStorage(eventData, secure: true));
      case 'web_app_secure_storage_get_key':
        unawaited(_readStorage(eventData, secure: true));
      case 'web_app_secure_storage_restore_key':
        unawaited(_restoreSecureStorage(eventData));
      case 'web_app_secure_storage_clear':
        unawaited(_clearStorage(eventData, secure: true));
      case 'web_app_biometry_get_info':
        unawaited(_sendBiometryInfo());
      case 'web_app_biometry_request_access':
        unawaited(_requestBiometryAccess(eventData));
      case 'web_app_biometry_update_token':
        unawaited(_updateBiometryToken(eventData));
      case 'web_app_biometry_request_auth':
        unawaited(_authenticateBiometry());
      case 'web_app_biometry_open_settings':
        if (_hasRecentInteraction && _canOpenBiometrySettings) {
          unawaited(_openBiometrySettings());
        }
      case 'web_app_start_accelerometer':
        unawaited(_startMotion(MiniAppMotionKind.accelerometer, eventData));
      case 'web_app_stop_accelerometer':
        unawaited(_stopMotion(MiniAppMotionKind.accelerometer));
      case 'web_app_start_gyroscope':
        unawaited(_startMotion(MiniAppMotionKind.gyroscope, eventData));
      case 'web_app_stop_gyroscope':
        unawaited(_stopMotion(MiniAppMotionKind.gyroscope));
      case 'web_app_start_device_orientation':
        unawaited(_startMotion(MiniAppMotionKind.orientation, eventData));
      case 'web_app_stop_device_orientation':
        unawaited(_stopMotion(MiniAppMotionKind.orientation));
      case 'web_app_invoke_custom_method':
        unawaited(_invokeCustomMethod(eventData));
      case 'web_app_request_write_access':
        unawaited(_requestWriteAccess());
      case 'web_app_request_phone':
        unawaited(_requestPhone());
      case 'web_app_switch_inline_query':
        unawaited(_switchInlineQuery(eventData));
      case 'web_app_send_prepared_message':
        unawaited(_sendPreparedMessage(eventData));
      case 'web_app_hide_keyboard':
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
        );
      default:
        break;
    }
  }

  Future<void> _sendWebAppData(String data) async {
    final buttonText = widget.launch.keyboardButtonText;
    if (buttonText == null || buttonText.isEmpty) return;
    try {
      await TdClient.shared.query({
        '@type': 'sendWebAppData',
        'bot_user_id': widget.launch.botUserId,
        'button_text': buttonText,
        'data': data,
      });
      unawaited(_closeView());
    } catch (_) {}
  }

  Future<void> _sendThemeEvent() {
    return _emitEvent('theme_changed', {'theme_params': _themeParams()});
  }

  Future<void> _sendViewportEvent({bool isExpanded = true}) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final height = (size.height - padding.top - padding.bottom).round();
    return _emitEvent('viewport_changed', {
      'width': size.width.round(),
      'height': height,
      'is_expanded': isExpanded,
      'is_state_stable': true,
    });
  }

  Future<void> _sendSafeAreaEvent() {
    final padding = MediaQuery.paddingOf(context);
    final data = {
      'top': padding.top.round(),
      'bottom': padding.bottom.round(),
      'left': padding.left.round(),
      'right': padding.right.round(),
    };
    return Future.wait([
      _emitEvent('safe_area_changed', data),
      _emitEvent('content_safe_area_changed', data),
    ]);
  }

  Future<void> _sendContentSafeAreaEvent() {
    final padding = MediaQuery.paddingOf(context);
    return _emitEvent('content_safe_area_changed', {
      'top': widget.fullscreen ? padding.top.round() : 0,
      'bottom': widget.fullscreen ? padding.bottom.round() : 0,
      'left': padding.left.round(),
      'right': padding.right.round(),
    });
  }

  Future<void> _sendClipboardText(
    String? reqId, {
    required bool allowed,
  }) async {
    if (!allowed) {
      await _emitEvent('clipboard_text_received', {'req_id': reqId ?? ''});
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    await _emitEvent('clipboard_text_received', {
      'req_id': reqId ?? '',
      'data': data?.text,
    });
  }

  Future<void> _openPopup(Map<String, dynamic> data) async {
    if (!mounted || _popupOpen) return;
    final now = DateTime.now();
    _popupTimes.removeWhere(
      (value) => now.difference(value) > const Duration(seconds: 3),
    );
    if (_popupTimes.length >= 3) return;
    final buttons =
        (data['buttons'] as List?)
            ?.whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList() ??
        const <Map<String, dynamic>>[];
    final message = (data['message'] as String?)?.trim() ?? '';
    final title = (data['title'] as String?)?.trim() ?? '';
    if (message.isEmpty ||
        message.length > 256 ||
        title.length > 64 ||
        buttons.isEmpty ||
        buttons.length > 3 ||
        !_validPopupButtons(buttons)) {
      return;
    }
    _popupTimes.add(now);
    _popupOpen = true;
    final id = await _showNativeDialog(
      title: title.isEmpty ? widget.launch.title : title,
      message: message,
      buttons: [
        for (final button in buttons)
          {...button, 'text': _popupButtonText(button)},
      ],
    );
    _popupOpen = false;
    await _emitEvent('popup_closed', {'button_id': ?id});
  }

  Future<String?> _showNativeDialog({
    required String title,
    required String message,
    required List<Map<String, dynamic>> buttons,
  }) {
    final colors = context.colors;
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.countryPickerCancel),
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) => _MiniAppNativeDialog(
        title: title,
        message: message,
        buttons: buttons,
        colors: colors,
      ),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
    );
  }

  Future<void> _openInvoice(Map<String, dynamic> data) async {
    if (_invoiceOpen || !_hasRecentInteraction) return;
    final slug = (data['slug'] as String?)?.trim() ?? '';
    if (slug.isEmpty || slug.length > 2048) return;
    _invoiceOpen = true;
    var status = 'cancelled';
    try {
      final outcome = await openTelegramInvoiceSlug(context, slug);
      status = outcome.status.name;
    } catch (_) {
      status = 'failed';
    } finally {
      _invoiceOpen = false;
    }
    await _emitEvent('invoice_closed', {'slug': slug, 'status': status});
  }

  Future<void> _openQrScanner(Map<String, dynamic> data) async {
    if (_qrScannerOpen || !mounted) return;
    final rawHint = (data['text'] as String?)?.trim() ?? '';
    final hint = rawHint.length <= 64 ? rawHint : rawHint.substring(0, 64);
    _qrScannerOpen = true;
    _closeQrFromWeb = false;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => QrScannerView(
            returnAnyValue: true,
            hint: hint.isEmpty ? null : hint,
            onScan: (value) => _emitEvent('qr_text_received', {'data': value}),
          ),
        ),
      );
      if (!_closeQrFromWeb) {
        await _emitEvent('scan_qr_popup_closed', const {});
      }
    } catch (_) {
      if (!_closeQrFromWeb) {
        await _emitEvent('scan_qr_popup_closed', const {});
      }
    } finally {
      _qrScannerOpen = false;
      _closeQrFromWeb = false;
    }
  }

  void _closeQrScannerFromWeb() {
    if (!_qrScannerOpen || !mounted) return;
    _closeQrFromWeb = true;
    Navigator.of(context).pop();
  }

  Future<void> _shareToStory(Map<String, dynamic> data) async {
    if (_storySharePending || !_hasRecentInteraction || !mounted) return;
    final mediaUrl = (data['media_url'] as String?)?.trim() ?? '';
    final uri = Uri.tryParse(mediaUrl);
    if (uri == null || uri.scheme != 'https') return;
    final caption = (data['text'] as String?) ?? '';
    final widgetLink = data['widget_link'];
    final linkUrl = widgetLink is Map
        ? (widgetLink['url'] as String?)?.trim()
        : null;
    _storySharePending = true;
    try {
      final media = await _platform.downloadTemporaryStoryMedia(mediaUrl);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => StoryAuthoringView(
            initialMediaPath: media.path,
            initialCaption: caption,
            initialLinkUrl: linkUrl,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      _storySharePending = false;
    }
  }

  Future<void> _setEmojiStatus(Map<String, dynamic> data) async {
    if (_emojiStatusPending || !_hasRecentInteraction || !mounted) return;
    final customEmojiId = int.tryParse(
      data['custom_emoji_id']?.toString() ?? '',
    );
    final duration = (data['duration'] as num?)?.toInt() ?? 0;
    if (customEmojiId == null ||
        customEmojiId < 0 ||
        duration < 0 ||
        duration > const Duration(days: 365).inSeconds) {
      await _emitEvent('emoji_status_failed', {
        'error': customEmojiId == null || customEmojiId < 0
            ? 'SUGGESTED_EMOJI_INVALID'
            : 'DURATION_INVALID',
      });
      return;
    }
    _emojiStatusPending = true;
    try {
      final accepted = await showAppConfirmDialog(
        context,
        title: customEmojiId == 0
            ? 'Remove your emoji status?'
            : '${widget.launch.title} suggests a new emoji status.',
        confirmText: AppStringKeys.confirmContinue,
      );
      if (!accepted) {
        await _emitEvent('emoji_status_failed', {'error': 'USER_DECLINED'});
        return;
      }
      await _platform.setEmojiStatus(
        customEmojiId: customEmojiId,
        duration: duration,
      );
      await _emitEvent('emoji_status_set', const {});
    } catch (error) {
      final value = error.toString();
      await _emitEvent('emoji_status_failed', {
        'error': value.contains('PREMIUM')
            ? 'UNSUPPORTED'
            : value.contains('EMOJI')
            ? 'SUGGESTED_EMOJI_INVALID'
            : 'SERVER_ERROR',
      });
    } finally {
      _emojiStatusPending = false;
    }
  }

  Future<void> _requestEmojiStatusAccess() async {
    if (_emojiStatusPending || !_hasRecentInteraction || !mounted) return;
    _emojiStatusPending = true;
    var allowed = false;
    try {
      allowed = await _platform.canManageEmojiStatus();
      if (!allowed && mounted) {
        allowed = await showAppConfirmDialog(
          context,
          title: AppStrings.t(
            AppStringKeys
                .telegramMiniAppValue1WantsPermissionToManageYourEmojiStatus,
            {'value1': widget.launch.title},
          ),
          confirmText: AppStringKeys.confirmContinue,
        );
        if (allowed) {
          await _platform.setCanManageEmojiStatus(true);
          allowed = await _platform.canManageEmojiStatus();
        }
      }
    } catch (_) {
      allowed = false;
    } finally {
      _emojiStatusPending = false;
    }
    await _emitEvent('emoji_status_access_requested', {
      'status': allowed ? 'allowed' : 'cancelled',
    });
  }

  String _popupButtonText(Map<String, dynamic> button) {
    final text = (button['text'] as String?)?.trim();
    if (text != null && text.isNotEmpty) return text;
    return switch (button['type']) {
      'cancel' => AppStrings.t(AppStringKeys.countryPickerCancel),
      'close' => AppStrings.t(AppStringKeys.miniAppClose),
      _ => AppStrings.t(AppStringKeys.confirmOk),
    };
  }

  bool _validPopupButtons(List<Map<String, dynamic>> buttons) {
    const types = {'ok', 'close', 'cancel', 'default', 'destructive'};
    final ids = <String>{};
    for (final button in buttons) {
      final type = button['type'];
      final id = button['id'];
      final text = (button['text'] as String?)?.trim() ?? '';
      if (type is! String ||
          !types.contains(type) ||
          id is! String ||
          id.length > 64 ||
          !ids.add(id) ||
          text.length > 64 ||
          ((type == 'default' || type == 'destructive') && text.isEmpty)) {
        return false;
      }
    }
    return true;
  }

  bool get _hasRecentInteraction {
    return _hasRecentInteractionWithin(const Duration(seconds: 10));
  }

  bool _hasRecentInteractionWithin(Duration duration) {
    final value = _lastUserInteraction;
    return value != null && DateTime.now().difference(value) <= duration;
  }

  bool _consumeRecentInteraction(Duration duration) {
    if (!_hasRecentInteractionWithin(duration)) return false;
    _lastUserInteraction = null;
    return true;
  }

  bool get _canOpenBiometrySettings {
    final last = _lastBiometrySettingsOpen;
    return last == null ||
        DateTime.now().difference(last) >= const Duration(seconds: 1);
  }

  Color? _requestedColor(Map<String, dynamic> data) {
    final direct = _MiniAppButtonState.parseColor(data['color'] as String?);
    if (direct != null) return direct;
    return switch (data['color_key']) {
      'bg_color' => context.colors.background,
      'secondary_bg_color' => context.colors.card,
      _ => null,
    };
  }

  Future<void> _setFullscreen(bool value, {bool blur = true}) async {
    if (value == widget.fullscreen) {
      if (value) {
        await _emitEvent('fullscreen_failed', {'error': 'ALREADY_FULLSCREEN'});
      } else {
        await _emitEvent('fullscreen_changed', {'is_fullscreen': false});
      }
      return;
    }
    widget.onFullscreenChanged?.call(value);
    await Future<void>.delayed(const Duration(milliseconds: 230));
    await _sendViewportEvent(isExpanded: value);
    await _sendSafeAreaEvent();
    await _sendContentSafeAreaEvent();
    await _emitEvent('fullscreen_changed', {
      'is_fullscreen': value,
      if (value) 'blur_enabled': blur,
    });
  }

  Future<void> _setOrientationLocked(bool locked) async {
    _orientationLocked = locked;
    if (!locked) {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      return;
    }
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    await SystemChrome.setPreferredOrientations(
      portrait
          ? const [DeviceOrientation.portraitUp]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
  }

  Future<void> _requestDownload(Map<String, dynamic> data) async {
    if (_downloadPending) return;
    final url = data['url'];
    final fileName = data['file_name'];
    if (url is! String || fileName is! String || fileName.trim().isEmpty) {
      await _emitEvent('file_download_requested', {'status': 'cancelled'});
      return;
    }
    _downloadPending = true;
    try {
      final allowed = await _platform.checkDownload(
        fileName: fileName,
        url: url,
      );
      if (!allowed || !mounted) {
        await _emitEvent('file_download_requested', {'status': 'cancelled'});
        return;
      }
      final accepted = await showAppConfirmDialog(
        context,
        title: AppStrings.t(
          AppStringKeys.telegramMiniAppValue1WantsToDownloadValue2,
          {'value1': widget.launch.title, 'value2': fileName},
        ),
        confirmText: AppStringKeys.confirmContinue,
      );
      if (!accepted) {
        await _emitEvent('file_download_requested', {'status': 'cancelled'});
        return;
      }
      await _emitEvent('file_download_requested', {'status': 'downloading'});
      final file = await _platform.download(fileName: fileName, url: url);
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.telegramMiniAppDownloadedToValue1, {
            'value1': file.path,
          }),
        );
      }
    } catch (_) {
      await _emitEvent('file_download_requested', {'status': 'cancelled'});
    } finally {
      _downloadPending = false;
    }
  }

  Future<void> _checkLocation() async {
    try {
      await _emitEvent('location_checked', await _platform.checkLocation());
    } catch (_) {
      await _emitEvent('location_checked', {'available': false});
    }
  }

  Future<void> _requestLocation() async {
    try {
      await _emitEvent('location_requested', await _platform.requestLocation());
    } catch (_) {
      await _emitEvent('location_requested', {'available': false});
    }
  }

  Future<void> _saveStorage(
    Map<String, dynamic> data, {
    required bool secure,
  }) async {
    final reqId = data['req_id'] as String? ?? '';
    final key = data['key'] as String? ?? '';
    final value = data['value'] as String?;
    final prefix = secure ? 'secure_storage' : 'device_storage';
    try {
      if (secure) {
        await _storage.saveSecure(key, value);
      } else {
        await _storage.saveDevice(key, value);
      }
      await _emitEvent('${prefix}_key_saved', {'req_id': reqId});
    } catch (error) {
      await _emitEvent('${prefix}_failed', {
        'req_id': reqId,
        'error': _storageError(error),
      });
    }
  }

  Future<void> _readStorage(
    Map<String, dynamic> data, {
    required bool secure,
  }) async {
    final reqId = data['req_id'] as String? ?? '';
    final key = data['key'] as String? ?? '';
    final prefix = secure ? 'secure_storage' : 'device_storage';
    try {
      final value = secure
          ? await _storage.readSecure(key)
          : await _storage.readDevice(key);
      await _emitEvent('${prefix}_key_received', {
        'req_id': reqId,
        'value': value,
        if (secure) 'can_restore': false,
      });
    } catch (error) {
      await _emitEvent('${prefix}_failed', {
        'req_id': reqId,
        'error': _storageError(error),
      });
    }
  }

  Future<void> _clearStorage(
    Map<String, dynamic> data, {
    required bool secure,
  }) async {
    final reqId = data['req_id'] as String? ?? '';
    final prefix = secure ? 'secure_storage' : 'device_storage';
    try {
      if (secure) {
        await _storage.clearSecure();
      } else {
        await _storage.clearDevice();
      }
      await _emitEvent('${prefix}_cleared', {'req_id': reqId});
    } catch (error) {
      await _emitEvent('${prefix}_failed', {
        'req_id': reqId,
        'error': _storageError(error),
      });
    }
  }

  Future<void> _restoreSecureStorage(Map<String, dynamic> data) async {
    final reqId = data['req_id'] as String? ?? '';
    final key = data['key'] as String? ?? '';
    try {
      final value = await _storage.readSecure(key);
      if (value == null) throw StateError('NOT_FOUND');
      await _emitEvent('secure_storage_key_restored', {
        'req_id': reqId,
        'value': value,
      });
    } catch (error) {
      await _emitEvent('secure_storage_failed', {
        'req_id': reqId,
        'error': _storageError(error),
      });
    }
  }

  String _storageError(Object error) {
    final text = error.toString();
    if (text.contains('QUOTA_EXCEEDED')) return 'QUOTA_EXCEEDED';
    if (text.contains('KEY_INVALID')) return 'KEY_INVALID';
    return 'UNKNOWN_ERROR';
  }

  Future<void> _sendBiometryInfo() async {
    await _emitEvent('biometry_info_received', await _biometry.info());
  }

  Future<void> _requestBiometryAccess(Map<String, dynamic> data) async {
    final info = await _biometry.info();
    if (info['available'] != true || info['access_requested'] == true) {
      await _emitEvent('biometry_info_received', info);
      return;
    }
    final rawReason = (data['reason'] as String?)?.trim() ?? '';
    final reason = rawReason.length <= 128
        ? rawReason
        : rawReason.substring(0, 128);
    var granted = false;
    if (mounted) {
      granted = await showAppConfirmDialog(
        context,
        title: reason.isEmpty
            ? '${widget.launch.title} wants to use biometrics.'
            : reason,
        confirmText: AppStringKeys.confirmContinue,
      );
    }
    await _biometry.setAccess(granted: granted);
    await _sendBiometryInfo();
  }

  Future<void> _updateBiometryToken(Map<String, dynamic> data) async {
    final token = data['token'];
    if (token is! String) {
      await _emitEvent('biometry_token_updated', {'status': 'failed'});
      return;
    }
    final updated = await _biometry.updateToken(token);
    await _emitEvent('biometry_token_updated', {
      'status': updated ? (token.isEmpty ? 'removed' : 'updated') : 'failed',
    });
  }

  Future<void> _authenticateBiometry() async {
    final token = await _biometry.authenticate();
    await _emitEvent('biometry_auth_requested', {
      'status': token == null ? 'failed' : 'authorized',
      'token': ?token,
    });
  }

  Future<void> _openBiometrySettings() async {
    _lastBiometrySettingsOpen = DateTime.now();
    if (!mounted) return;
    final granted = await showAppConfirmDialog(
      context,
      title: AppStrings.t(
        AppStringKeys.telegramMiniAppAllowValue1ToUseBiometrics,
        {'value1': widget.launch.title},
      ),
      confirmText: AppStringKeys.confirmContinue,
    );
    await _biometry.setAccess(granted: granted);
    await _sendBiometryInfo();
  }

  Future<void> _startMotion(
    MiniAppMotionKind kind,
    Map<String, dynamic> data,
  ) async {
    final refreshRate = (data['refresh_rate'] as num?)?.toInt() ?? 1000;
    try {
      await _motion.start(
        kind: kind,
        refreshRate: refreshRate,
        emit: _emitEvent,
        needAbsolute:
            kind == MiniAppMotionKind.orientation &&
            data['need_absolute'] == true,
      );
    } catch (_) {
      await _emitEvent(
        switch (kind) {
          MiniAppMotionKind.accelerometer => 'accelerometer_failed',
          MiniAppMotionKind.gyroscope => 'gyroscope_failed',
          MiniAppMotionKind.orientation => 'device_orientation_failed',
        },
        {'error': 'UNSUPPORTED'},
      );
    }
  }

  Future<void> _stopMotion(MiniAppMotionKind kind) =>
      _motion.stop(emit: _emitEvent, kind: kind);

  Future<void> _invokeCustomMethod(Map<String, dynamic> data) async {
    final reqId = data['req_id'] as String? ?? '';
    final method = data['method'] as String? ?? '';
    final parameters = data['params'];
    if (method.isEmpty || parameters is! Map) {
      await _emitEvent('custom_method_invoked', {
        'req_id': reqId,
        'error': 'PARAMS_INVALID',
      });
      return;
    }
    try {
      final result = await _platform.invokeCustomMethod(
        method,
        Map<String, dynamic>.from(parameters),
      );
      await _emitEvent('custom_method_invoked', {
        'req_id': reqId,
        'result': result,
      });
    } catch (error) {
      await _emitEvent('custom_method_invoked', {
        'req_id': reqId,
        'error': error.toString(),
      });
    }
  }

  Future<void> _requestWriteAccess() async {
    var allowed = await _platform.canSendMessages();
    if (!allowed && mounted) {
      allowed = await showAppConfirmDialog(
        context,
        title: AppStrings.t(
          AppStringKeys.telegramMiniAppValue1WantsPermissionToSendYouMessages,
          {'value1': widget.launch.title},
        ),
        confirmText: AppStringKeys.confirmContinue,
      );
      if (allowed) {
        try {
          await _platform.allowSendMessages();
        } catch (_) {
          allowed = false;
        }
      }
    }
    await _emitEvent('write_access_requested', {
      'status': allowed ? 'allowed' : 'cancelled',
    });
  }

  Future<void> _requestPhone() async {
    var sent = false;
    if (mounted) {
      final accepted = await showAppConfirmDialog(
        context,
        title: AppStrings.t(
          AppStringKeys.telegramMiniAppValue1WantsYourPhoneNumber,
          {'value1': widget.launch.title},
        ),
        confirmText: AppStringKeys.confirmContinue,
      );
      if (accepted) {
        try {
          await _platform.sharePhoneNumber();
          sent = true;
        } catch (_) {}
      }
    }
    await _emitEvent('phone_requested', {
      'status': sent ? 'sent' : 'cancelled',
    });
  }

  Future<void> _switchInlineQuery(Map<String, dynamic> data) async {
    final query = data['query'] as String? ?? '';
    final username = await _platform.botUsername();
    if (username == null || !mounted) return;
    var chatId = widget.launch.chatId;
    final chatTypes = (data['chat_types'] as List?)
        ?.whereType<String>()
        .toSet();
    if (chatTypes != null && chatTypes.isNotEmpty) {
      final picked = await Navigator.of(context).push<ChatSummary>(
        MaterialPageRoute(
          builder: (_) => ChatPickerView(
            allowedKinds: {
              if (chatTypes.contains('users')) ChatKind.privateChat,
              if (chatTypes.contains('bots')) ChatKind.bot,
              if (chatTypes.contains('groups')) ChatKind.group,
              if (chatTypes.contains('channels')) ChatKind.channel,
            },
          ),
        ),
      );
      if (picked == null) return;
      chatId = picked.id;
    }
    await _platform.setInlineDraft(
      chatId: chatId,
      botUsername: username,
      query: query,
    );
    await _closeView();
  }

  Future<void> _sendPreparedMessage(Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    if (id == null || id.isEmpty || !mounted) return;
    try {
      final prepared = await TdClient.shared.query({
        '@type': 'getPreparedInlineMessage',
        'bot_user_id': widget.launch.botUserId,
        'prepared_message_id': id,
      });
      if (!mounted) return;
      final picked = await Navigator.of(context).push<ChatSummary>(
        MaterialPageRoute(builder: (_) => const ChatPickerView()),
      );
      if (picked == null) {
        await _emitEvent('prepared_message_failed', {'error': 'USER_DECLINED'});
        return;
      }
      final result = prepared.obj('result');
      final resultId = result?.str('id');
      final queryId = prepared.int64('inline_query_id');
      if (resultId == null || queryId == null) throw StateError('INVALID');
      await _botPlatform.sendInlineResult(
        chatId: picked.id,
        queryId: queryId,
        resultId: resultId,
      );
      await _emitEvent('prepared_message_sent', const {});
    } catch (error) {
      await _emitEvent('prepared_message_failed', {'error': error.toString()});
    }
  }

  Future<void> _triggerHaptic(Map<String, dynamic> data) {
    return switch (data['type']) {
      'impact' => switch (data['impact_style']) {
        'light' => HapticFeedback.lightImpact(),
        'heavy' || 'rigid' => HapticFeedback.heavyImpact(),
        'soft' => HapticFeedback.selectionClick(),
        _ => HapticFeedback.mediumImpact(),
      },
      'notification' => switch (data['notification_type']) {
        'error' => HapticFeedback.vibrate(),
        'warning' => HapticFeedback.mediumImpact(),
        _ => HapticFeedback.lightImpact(),
      },
      _ => HapticFeedback.selectionClick(),
    };
  }

  Future<void> _emitEvent(String eventType, Object? data) {
    final script =
        '''
(function() {
  var eventType = ${jsonEncode(eventType)};
  var eventData = ${jsonEncode(data ?? <String, dynamic>{})};
  if (window.Telegram && window.Telegram.WebView &&
      typeof window.Telegram.WebView.receiveEvent === 'function') {
    window.Telegram.WebView.receiveEvent(eventType, eventData);
  }
  window.dispatchEvent(new MessageEvent('message', {
    data: JSON.stringify({eventType: eventType, eventData: eventData})
  }));
})();
''';
    return _controller.runJavaScript(script).catchError((_) {});
  }

  Map<String, String> _themeParams() {
    final c = context.colors;
    return {
      'bg_color': _hex(c.background),
      'secondary_bg_color': _hex(c.card),
      'text_color': _hex(c.textPrimary),
      'hint_color': _hex(c.textSecondary),
      'link_color': _hex(c.linkBlue),
      'button_color': _hex(AppTheme.brand),
      'button_text_color': _hex(Colors.white),
      'header_bg_color': _hex(c.card),
      'accent_text_color': _hex(AppTheme.brand),
      'section_bg_color': _hex(c.card),
      'section_header_text_color': _hex(c.textSecondary),
      'subtitle_text_color': _hex(c.textSecondary),
      'destructive_text_color': _hex(Colors.redAccent),
    };
  }

  String _hex(Color color) {
    final value = color.toARGB32() & 0x00ffffff;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {'http', 'https', 'mailto', 'tel'}.contains(uri.scheme)) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _pressMainButton() {
    _lastUserInteraction = DateTime.now();
    unawaited(_emitEvent('main_button_pressed', const <String, dynamic>{}));
  }

  void _pressSecondaryButton() {
    _lastUserInteraction = DateTime.now();
    unawaited(
      _emitEvent('secondary_button_pressed', const <String, dynamic>{}),
    );
  }

  void _pressSettingsButton() {
    _lastUserInteraction = DateTime.now();
    unawaited(_emitEvent('settings_button_pressed', const {}));
  }

  void _pressLeading() {
    if (_backButtonVisible) {
      unawaited(_emitEvent('back_button_pressed', const <String, dynamic>{}));
    } else {
      unawaited(_closeView());
    }
  }

  Future<void> _closeView() async {
    if (_needClosingConfirmation && mounted) {
      final close = await showAppConfirmDialog(
        context,
        title: AppStrings.t(
          AppStringKeys.telegramMiniAppChangesThatYouMadeMayNotBeSaved,
        ),
        confirmText: AppStringKeys.miniAppClose,
      );
      if (!close) return;
    }
    _notifyTdClosed();
    if (mounted) await Navigator.of(context).maybePop();
  }

  void _notifyTdClosed() {
    if (_closedTdLaunch) return;
    _closedTdLaunch = true;
    final launchId = widget.launch.launchId;
    if (launchId == null) return;
    TdClient.shared.send({
      '@type': 'closeWebApp',
      'web_app_launch_id': launchId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final background = _requestedBackgroundColor ?? c.background;
    final header = _requestedHeaderColor ?? c.background;
    final bottom = _requestedBottomColor ?? c.card;
    final mainButton = _mainButton.isVisible
        ? _MiniAppBottomButton(
            state: _mainButton,
            fallbackColor: AppTheme.brand,
            fallbackTextColor: Colors.white,
            onPressed: _mainButton.isActive ? _pressMainButton : null,
          )
        : null;
    final secondaryButton = _secondaryButton.isVisible
        ? _MiniAppBottomButton(
            state: _secondaryButton,
            fallbackColor: c.card,
            fallbackTextColor: c.textPrimary,
            onPressed: _secondaryButton.isActive ? _pressSecondaryButton : null,
          )
        : null;
    final buttonLayout = _layoutBottomButtons(
      mainButton: mainButton,
      secondaryButton: secondaryButton,
    );

    return ColoredBox(
      color: background,
      child: Column(
        children: [
          if (!widget.fullscreen) ...[
            if (_allowVerticalSwipe) ...[
              const SizedBox(height: 10),
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: c.textTertiary.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
            ] else
              const SizedBox(height: 18),
          ],
          ColoredBox(
            color: header,
            child: _MiniAppToolbar(
              title: widget.launch.title,
              leadingIcon: _backButtonVisible
                  ? HeroAppIcons.chevronLeft
                  : HeroAppIcons.xmark,
              leadingSize: _backButtonVisible ? 20 : 24,
              onLeadingPressed: _pressLeading,
              onSettings: _settingsButtonVisible ? _pressSettingsButton : null,
              onReload: _controller.reload,
              onOpenExternal: () => _openExternal(widget.launch.url),
            ),
          ),
          if (!_pageReady || _progress < 100)
            SizedBox(
              height: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _progress <= 0 || _progress >= 100
                      ? 0.18
                      : _progress / 100,
                  child: ColoredBox(color: AppTheme.brand),
                ),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
          if (buttonLayout != null)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: bottom,
                  border: Border(top: BorderSide(color: c.divider, width: 0.5)),
                ),
                child: buttonLayout,
              ),
            ),
        ],
      ),
    );
  }

  Widget? _layoutBottomButtons({
    required Widget? mainButton,
    required Widget? secondaryButton,
  }) {
    if (mainButton == null) return secondaryButton;
    if (secondaryButton == null) return mainButton;
    return switch (_secondaryButton.position) {
      'right' => Row(
        children: [
          Expanded(child: mainButton),
          const SizedBox(width: 8),
          Expanded(child: secondaryButton),
        ],
      ),
      'top' => Column(
        mainAxisSize: MainAxisSize.min,
        children: [secondaryButton, const SizedBox(height: 8), mainButton],
      ),
      'bottom' => Column(
        mainAxisSize: MainAxisSize.min,
        children: [mainButton, const SizedBox(height: 8), secondaryButton],
      ),
      _ => Row(
        children: [
          Expanded(child: secondaryButton),
          const SizedBox(width: 8),
          Expanded(child: mainButton),
        ],
      ),
    };
  }
}

class _MiniAppNativeDialog extends StatelessWidget {
  const _MiniAppNativeDialog({
    required this.title,
    required this.message,
    required this.buttons,
    required this.colors,
  });

  final String title;
  final String message;
  final List<Map<String, dynamic>> buttons;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final actions = [
      for (final button in buttons)
        _MiniAppNativeDialogAction(
          label: (button['text'] as String?) ?? '',
          color: switch (button['type']) {
            'destructive' => const Color(0xFFE5484D),
            'cancel' || 'close' => colors.textSecondary,
            _ => colors.linkBlue,
          },
          onTap: () => Navigator.of(context).pop(button['id'] as String? ?? ''),
        ),
    ];
    final actionLayout = actions.length <= 2
        ? SizedBox(
            height: 50,
            child: Row(
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  Expanded(child: actions[index]),
                  if (index != actions.length - 1)
                    ColoredBox(
                      color: colors.divider,
                      child: const SizedBox(width: 1),
                    ),
                ],
              ],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                SizedBox(height: 50, child: actions[index]),
                if (index != actions.length - 1)
                  ColoredBox(
                    color: colors.divider,
                    child: const SizedBox(height: 1),
                  ),
              ],
            ],
          );
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.title(
                            colors.textPrimary,
                            weight: AppTextWeight.semibold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.body(
                            colors.textSecondary,
                          ).copyWith(height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  ColoredBox(
                    color: colors.divider,
                    child: const SizedBox(height: 1),
                  ),
                  actionLayout,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniAppNativeDialogAction extends StatelessWidget {
  const _MiniAppNativeDialogAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.bodyLarge(color, weight: AppTextWeight.semibold),
        ),
      ),
    ),
  );
}

class _MiniAppToolbar extends StatelessWidget {
  const _MiniAppToolbar({
    required this.title,
    required this.leadingIcon,
    required this.leadingSize,
    required this.onLeadingPressed,
    this.onSettings,
    required this.onReload,
    required this.onOpenExternal,
  });

  final String title;
  final AppIconData leadingIcon;
  final double leadingSize;
  final VoidCallback onLeadingPressed;
  final VoidCallback? onSettings;
  final VoidCallback onReload;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _MiniAppToolbarAction(
              label: AppStrings.t(AppStringKeys.miniAppClose),
              icon: leadingIcon,
              size: leadingSize,
              onPressed: onLeadingPressed,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: AppTextSize.bodyLarge,
                  fontWeight: context.appFontWeight(FontWeight.w500),
                ),
              ),
            ),
            if (onSettings != null)
              _MiniAppToolbarAction(
                label: AppStrings.t(
                  AppStringKeys.telegramMiniAppMiniAppSettings,
                ),
                icon: HeroAppIcons.gear,
                onPressed: onSettings!,
              ),
            _MiniAppToolbarAction(
              label: AppStrings.t(AppStringKeys.miniAppReload),
              icon: HeroAppIcons.arrowsRotate,
              onPressed: onReload,
            ),
            _MiniAppToolbarAction(
              label: AppStrings.t(AppStringKeys.miniAppOpenInBrowser),
              icon: HeroAppIcons.arrowTopRight,
              onPressed: onOpenExternal,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAppToolbarAction extends StatelessWidget {
  const _MiniAppToolbarAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.size = 21,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 42,
          height: 44,
          child: Center(
            child: AppIcon(icon, size: size, color: context.colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _MiniAppButtonState {
  const _MiniAppButtonState({
    this.isVisible = false,
    this.isActive = true,
    this.isProgressVisible = false,
    this.text = '',
    this.color,
    this.textColor,
    this.position = 'left',
    this.hasShineEffect = false,
    this.iconCustomEmojiId = 0,
  });

  final bool isVisible;
  final bool isActive;
  final bool isProgressVisible;
  final String text;
  final Color? color;
  final Color? textColor;
  final String position;
  final bool hasShineEffect;
  final int iconCustomEmojiId;

  factory _MiniAppButtonState.fromJson(Map<String, dynamic> json) {
    final text = (json['text'] as String?)?.trim() ?? '';
    return _MiniAppButtonState(
      isVisible: json['is_visible'] == true && text.isNotEmpty,
      isActive: json['is_active'] != false,
      isProgressVisible: json['is_progress_visible'] == true,
      text: text,
      color: parseColor(json['color'] as String?),
      textColor: parseColor(json['text_color'] as String?),
      position: json['position'] as String? ?? 'left',
      hasShineEffect: json['has_shine_effect'] == true,
      iconCustomEmojiId:
          int.tryParse(json['icon_custom_emoji_id']?.toString() ?? '') ?? 0,
    );
  }

  static Color? parseColor(String? value) {
    if (value == null || value.isEmpty) return null;
    final hex = value.replaceFirst('#', '');
    final parsed = int.tryParse(hex.length == 6 ? 'ff$hex' : hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}

class _MiniAppBottomButton extends StatelessWidget {
  const _MiniAppBottomButton({
    required this.state,
    required this.fallbackColor,
    required this.fallbackTextColor,
    required this.onPressed,
  });

  final _MiniAppButtonState state;
  final Color fallbackColor;
  final Color fallbackTextColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final background = state.color ?? fallbackColor;
    final foreground = state.textColor ?? fallbackTextColor;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: state.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onPressed == null
                ? background.withValues(alpha: 0.45)
                : background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (state.hasShineEffect)
                Positioned.fill(child: _MiniAppButtonShine(color: foreground)),
              if (state.isProgressVisible)
                _MiniAppProgressGlyph(color: foreground)
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.iconCustomEmojiId != 0) ...[
                      CustomEmojiView(
                        id: state.iconCustomEmojiId,
                        color: foreground,
                      ),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        state.text,
                        style: TextStyle(
                          color: onPressed == null
                              ? foreground.withValues(alpha: 0.72)
                              : foreground,
                          fontSize: 16,
                          fontWeight: context.appFontWeight(FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAppProgressGlyph extends StatefulWidget {
  const _MiniAppProgressGlyph({required this.color});

  final Color color;

  @override
  State<_MiniAppProgressGlyph> createState() => _MiniAppProgressGlyphState();
}

class _MiniAppProgressGlyphState extends State<_MiniAppProgressGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: AppIcon(HeroAppIcons.arrowsRotate, size: 20, color: widget.color),
  );
}

class _MiniAppButtonShine extends StatefulWidget {
  const _MiniAppButtonShine({required this.color});

  final Color color;

  @override
  State<_MiniAppButtonShine> createState() => _MiniAppButtonShineState();
}

class _MiniAppButtonShineState extends State<_MiniAppButtonShine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => FractionalTranslation(
        translation: Offset(-1.4 + (_controller.value * 2.8), 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Transform.rotate(
            angle: -0.22,
            child: Container(
              width: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.color.withValues(alpha: 0),
                    widget.color.withValues(alpha: 0.22),
                    widget.color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final _miniAppUserAgent =
    'Mozilla/5.0 (${Platform.operatingSystem}) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Mithka/1.0 TelegramWebView/1.0';

const _telegramBridgeScript = r'''
(function() {
  if (window.__mithkaTelegramBridgeInstalled) return;
  window.__mithkaTelegramBridgeInstalled = true;

  function postToDart(eventType, eventData) {
    try {
      if (window.MithkaTelegramBridge &&
          typeof window.MithkaTelegramBridge.postMessage === 'function') {
        window.MithkaTelegramBridge.postMessage(JSON.stringify({
          eventType: eventType,
          eventData: eventData || ''
        }));
      }
    } catch (e) {}
  }

  window.TelegramWebviewProxy = {
    postEvent: function(eventType, eventData) {
      postToDart(eventType, eventData);
    }
  };

  window.TelegramGameProxy = window.TelegramGameProxy || {};
  window.TelegramGameProxy.postEvent = function(eventType, eventData) {
    postToDart(eventType, eventData);
  };

  ['pointerdown', 'touchstart', 'keydown'].forEach(function(type) {
    document.addEventListener(type, function() {
      postToDart('web_app_user_interaction', {});
    }, {passive: true, capture: true});
  });
})();
''';
