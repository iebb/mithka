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
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../components/app_icons.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'link_handler.dart';
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
  String startParameter = '',
  String webAppShortName = '',
  bool allowWriteAccess = false,
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
    startParameter: startParameter,
    webAppShortName: webAppShortName,
    allowWriteAccess: allowWriteAccess,
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
    pageBuilder: (context, animation, secondaryAnimation) {
      final c = context.colors;
      const radius = BorderRadius.vertical(top: Radius.circular(24));
      return Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 32,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: TelegramMiniAppView(launch: launch),
            ),
          ),
        ),
      );
    },
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

Future<TelegramMiniAppLaunch?> _resolveMiniAppLaunch(
  BuildContext context, {
  required int chatId,
  required int botUserId,
  required String url,
  required String title,
  String? keyboardButtonText,
  bool mainWebApp = false,
  bool menuWebApp = false,
  String startParameter = '',
  String webAppShortName = '',
  bool allowWriteAccess = false,
}) async {
  try {
    final parameters = _webAppOpenParameters(context);
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

Map<String, dynamic> _webAppOpenParameters(BuildContext context) {
  return {
    '@type': 'webAppOpenParameters',
    'theme': null,
    // Match Telegram's supported Mini App platform identifiers. In
    // particular, bots use this value when validating their launch data.
    'application_name': Platform.isIOS ? 'ios' : 'android',
    'mode': {'@type': 'webAppOpenModeFullSize'},
  };
}

String _keyboardWebAppUrl(String url) {
  return url.endsWith('#kb') ? url : '$url#kb';
}

class TelegramMiniAppView extends StatefulWidget {
  const TelegramMiniAppView({super.key, required this.launch});

  final TelegramMiniAppLaunch launch;

  @override
  State<TelegramMiniAppView> createState() => _TelegramMiniAppViewState();
}

class _TelegramMiniAppViewState extends State<TelegramMiniAppView>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  var _progress = 0;
  var _pageReady = false;
  var _backButtonVisible = false;
  var _closedTdLaunch = false;
  _MiniAppButtonState _mainButton = const _MiniAppButtonState();
  _MiniAppButtonState _secondaryButton = const _MiniAppButtonState();
  Timer? _viewportTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = _buildController();
    unawaited(_controller.loadRequest(Uri.parse(widget.launch.url)));
  }

  @override
  void dispose() {
    _viewportTimer?.cancel();
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
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(request.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      })
      ..setOnJavaScriptConfirmDialog((request) async {
        if (!mounted) return false;
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                content: Text(request.message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ) ??
            false;
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
    final payload = _decodePayload(message.message);
    final eventType = payload['eventType'] as String?;
    if (eventType == null || eventType.isEmpty) return;
    final eventData = _decodeEventData(payload['eventData']);

    switch (eventType) {
      case 'web_app_ready':
        if (mounted) setState(() => _pageReady = true);
      case 'web_app_close':
        _closeView();
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
      case 'web_app_data_send':
        final data = eventData['data'];
        if (data is String) unawaited(_sendWebAppData(data));
      case 'web_app_open_link':
        final url = eventData['url'];
        if (url is String && url.isNotEmpty) {
          unawaited(_openInCurrentWebView(url));
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
      case 'web_app_read_text_from_clipboard':
        unawaited(_sendClipboardText(eventData['req_id'] as String?));
      case 'web_app_open_popup':
        unawaited(_openPopup(eventData));
      case 'web_app_trigger_haptic_feedback':
        HapticFeedback.selectionClick();
      default:
        break;
    }
  }

  Map<String, dynamic> _decodePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {'eventType': raw, 'eventData': <String, dynamic>{}};
  }

  Map<String, dynamic> _decodeEventData(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
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
      _closeView();
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

  Future<void> _sendClipboardText(String? reqId) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    await _emitEvent('clipboard_text_received', {
      'req_id': reqId ?? '',
      'data': data?.text,
    });
  }

  Future<void> _openPopup(Map<String, dynamic> data) async {
    if (!mounted) return;
    final buttons =
        (data['buttons'] as List?)
            ?.whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList() ??
        const <Map<String, dynamic>>[];
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text((data['title'] as String?) ?? widget.launch.title),
        content: Text((data['message'] as String?) ?? ''),
        actions: [
          if (buttons.isEmpty)
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('OK'),
            ),
          for (final button in buttons)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop((button['id'] as String?) ?? ''),
              child: Text((button['text'] as String?) ?? 'OK'),
            ),
        ],
      ),
    );
    await _emitEvent('popup_closed', {'button_id': id ?? ''});
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

  Future<void> _openInCurrentWebView(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (_isWebNavigation(uri)) {
      await _controller.loadRequest(uri);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _pressMainButton() {
    unawaited(_emitEvent('main_button_pressed', const <String, dynamic>{}));
  }

  void _pressSecondaryButton() {
    unawaited(
      _emitEvent('secondary_button_pressed', const <String, dynamic>{}),
    );
  }

  void _pressLeading() {
    if (_backButtonVisible) {
      unawaited(_emitEvent('back_button_pressed', const <String, dynamic>{}));
    } else {
      _closeView();
    }
  }

  void _closeView() {
    _notifyTdClosed();
    if (mounted) Navigator.of(context).maybePop();
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
    final buttons = <Widget>[
      if (_secondaryButton.isVisible)
        _MiniAppBottomButton(
          state: _secondaryButton,
          fallbackColor: c.card,
          fallbackTextColor: c.textPrimary,
          onPressed: _secondaryButton.isActive ? _pressSecondaryButton : null,
        ),
      if (_mainButton.isVisible)
        _MiniAppBottomButton(
          state: _mainButton,
          fallbackColor: AppTheme.brand,
          fallbackTextColor: Colors.white,
          onPressed: _mainButton.isActive ? _pressMainButton : null,
        ),
    ];

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
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
          _MiniAppToolbar(
            title: widget.launch.title,
            leadingIcon: _backButtonVisible
                ? HeroAppIcons.chevronLeft
                : HeroAppIcons.xmark,
            leadingSize: _backButtonVisible ? 20 : 24,
            onLeadingPressed: _pressLeading,
            onReload: _controller.reload,
            onOpenExternal: () => _openExternal(widget.launch.url),
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
          if (buttons.isNotEmpty)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: c.card,
                  border: Border(top: BorderSide(color: c.divider, width: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      buttons[i],
                      if (i < buttons.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniAppToolbar extends StatelessWidget {
  const _MiniAppToolbar({
    required this.title,
    required this.leadingIcon,
    required this.leadingSize,
    required this.onLeadingPressed,
    required this.onReload,
    required this.onOpenExternal,
  });

  final String title;
  final AppIconData leadingIcon;
  final double leadingSize;
  final VoidCallback onLeadingPressed;
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
              label: 'Close mini app',
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
            _MiniAppToolbarAction(
              label: 'Reload mini app',
              icon: HeroAppIcons.arrowsRotate,
              onPressed: onReload,
            ),
            _MiniAppToolbarAction(
              label: 'Open in browser',
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
  });

  final bool isVisible;
  final bool isActive;
  final bool isProgressVisible;
  final String text;
  final Color? color;
  final Color? textColor;

  factory _MiniAppButtonState.fromJson(Map<String, dynamic> json) {
    return _MiniAppButtonState(
      isVisible: json['is_visible'] == true,
      isActive: json['is_active'] != false,
      isProgressVisible: json['is_progress_visible'] == true,
      text: (json['text'] as String?)?.trim() ?? '',
      color: _parseColor(json['color'] as String?),
      textColor: _parseColor(json['text_color'] as String?),
    );
  }

  static Color? _parseColor(String? value) {
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
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.45),
          disabledForegroundColor: foreground.withValues(alpha: 0.72),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: TextStyle(
            fontSize: 16,
            fontWeight: context.appFontWeight(FontWeight.w600),
          ),
        ),
        onPressed: onPressed,
        child: state.isProgressVisible
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(foreground),
                ),
              )
            : Text(state.text.isEmpty ? '继续' : state.text),
      ),
    );
  }
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
})();
''';
