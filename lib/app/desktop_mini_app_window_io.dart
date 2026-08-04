import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'chat_deep_link_controller.dart';
import 'desktop_chat_window_io.dart';
import 'desktop_mini_app_window_models.dart';
import 'desktop_utility_window_io.dart';

const _connectMethod = 'mithka.mini-app.td.connect';
const _queryMethod = 'mithka.mini-app.td.query';
const _sendMethod = 'mithka.mini-app.td.send';
const _openMethod = 'mithka.mini-app.open';
const _cleanupMethod = 'mithka.mini-app.cleanup';
const _openPrimaryChatMethod = 'mithka.mini-app.primary-chat.open';

const _miniAppWindowSize = Size(460, 720);
const _miniAppWindowMinimumSize = Size(360, 500);

const _blockedRequestTypes = <String>{
  'close',
  'destroy',
  'logOut',
  'setTdlibParameters',
};

bool get supportsDesktopMiniAppWindows => Platform.isMacOS;

final _mainBridge = _DesktopMiniAppMainBridge();
DesktopMiniAppWindowArguments? _childArguments;

void attachDesktopMiniAppMainProxy() => _mainBridge.attach();

void detachDesktopMiniAppMainProxy() => _mainBridge.detach();

void notifyDesktopMiniAppAccountIdentityChanged() =>
    _mainBridge.closeStaleAccountWindows();

Future<bool> openDesktopMiniAppWindow(DesktopMiniAppWindowLaunch launch) async {
  if (!supportsDesktopMiniAppWindows) return false;
  if (MultiWindowManager.current.id <= 0) return _mainBridge.open(launch);
  return _openFromChild(launch);
}

Future<bool> openChatInPrimaryWindowFromDesktopMiniApp(
  ChatDeepLinkRequest request,
) async {
  if (!supportsDesktopMiniAppWindows || MultiWindowManager.current.id <= 0) {
    return false;
  }
  final source = _childArguments;
  if (source == null) return false;
  try {
    final response = await MultiWindowManager.current
        .invokeMethodToWindow(0, _openPrimaryChatMethod, {
          ...source.toIpcJson(),
          'chat': request.toDesktopIpcJson(),
        })
        .timeout(const Duration(seconds: 10));
    return response is Map && response['ok'] == true;
  } on Object {
    return false;
  }
}

Future<DesktopMiniAppWindowLaunch> configureDesktopMiniAppChildProxy(
  DesktopMiniAppWindowArguments arguments,
) async {
  _childArguments = arguments;
  final proxy = _DesktopMiniAppChildProxy(arguments);
  TdClient.shared.configureProxy(
    TdClientProxyTransport(
      accountSlot: arguments.accountSlot,
      accountUserId: arguments.accountUserId,
      query: proxy.query,
      send: proxy.send,
      updates: const Stream<Map<String, dynamic>>.empty(),
    ),
  );
  try {
    return await proxy.connect();
  } on Object {
    await proxy.close();
    rethrow;
  }
}

Future<bool> _openFromChild(DesktopMiniAppWindowLaunch launch) async {
  final source = _currentChildSource();
  if (source == null) return false;

  var handledByPrimary = false;
  try {
    final response = await MultiWindowManager.current
        .invokeMethodToWindow(0, _openMethod, {
          'sourceType': source.type,
          'source': source.identity,
          // Signed launch data crosses only authenticated local window IPC.
          // It is never part of createWindow startup arguments.
          'launch': launch.toPrimaryOpenJson(),
        })
        .timeout(const Duration(seconds: 20));
    handledByPrimary = response is Map && response['handled'] == true;
    return handledByPrimary && response['ok'] == true;
  } on Object {
    return false;
  } finally {
    if (!handledByPrimary) {
      await _requestPrimaryCleanup(launch.arguments, source);
    }
  }
}

({String type, Map<String, Object?> identity})? _currentChildSource() {
  final chatSource = desktopChatChildWindowIdentity();
  if (chatSource != null) return (type: 'chat', identity: chatSource);
  final utilitySource = desktopUtilityChildWindowIdentity();
  if (utilitySource != null) {
    return (type: 'utility', identity: utilitySource);
  }
  final miniAppSource = _childArguments?.toIpcJson();
  return miniAppSource == null
      ? null
      : (type: 'mini-app', identity: miniAppSource);
}

Future<bool> _requestPrimaryCleanup(
  DesktopMiniAppWindowArguments arguments,
  ({String type, Map<String, Object?> identity}) source,
) async {
  for (var attempt = 0; attempt < 3; attempt += 1) {
    try {
      final response = await MultiWindowManager.current
          .invokeMethodToWindow(0, _cleanupMethod, {
            'sourceType': source.type,
            'source': source.identity,
            'cleanup': arguments.toPrimaryCleanupJson(),
          })
          .timeout(const Duration(seconds: 3));
      if (response is Map && response['handled'] == true) return true;
    } on Object {
      // Window zero can still be completing the original open request. Retry
      // this authenticated, URL-free cleanup without falling back to TD IPC.
    }
    if (attempt < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  return false;
}

Future<void> closeCurrentDesktopMiniAppWindow() async {
  if (!supportsDesktopMiniAppWindows || MultiWindowManager.current.id <= 0) {
    return;
  }
  try {
    await MultiWindowManager.current.close();
  } on Object {
    // Closing an already-destroyed native child is a harmless no-op.
  }
}

Future<bool?> setCurrentDesktopMiniAppWindowFullscreen(bool fullscreen) async {
  if (!supportsDesktopMiniAppWindows || MultiWindowManager.current.id <= 0) {
    return null;
  }
  try {
    final window = MultiWindowManager.current;
    if (await window.isFullScreen() != fullscreen) {
      await window.setFullScreen(fullscreen);
    }
    return await window.isFullScreen();
  } on Object {
    return null;
  }
}

WindowOptions desktopMiniAppWindowOptions(
  DesktopMiniAppWindowArguments arguments,
) => WindowOptions(
  size: _miniAppWindowSize,
  minimumSize: _miniAppWindowMinimumSize,
  center: true,
  title: DesktopMiniAppWindowArguments.normalizeTitle(arguments.title),
  backgroundColor: arguments.dark
      ? const Color(0xFF111113)
      : const Color(0xFFFFFFFF),
  // The mini-app toolbar is the title bar (custom-rendered chrome); the
  // native bar would double it.
  titleBarStyle: TitleBarStyle.hidden,
  windowButtonVisibility: true,
);

@visibleForTesting
Map<String, dynamic>? desktopMiniAppSanitizeRequest(Object? source) {
  final request = desktopMiniAppNormalizeIpcMap(source);
  if (request == null) return null;
  final type = request['@type'];
  if (type is! String || type.isEmpty || _blockedRequestTypes.contains(type)) {
    return null;
  }
  request
    ..remove('@client_id')
    ..remove('@extra');
  return request;
}

@visibleForTesting
Map<String, dynamic>? desktopMiniAppNormalizeIpcMap(Object? source) {
  final normalized = _normalizeDesktopMiniAppIpcValue(source);
  return normalized is Map<String, dynamic> ? normalized : null;
}

Object? _normalizeDesktopMiniAppIpcValue(Object? source) {
  if (source is Map) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      if (entry.key is String) {
        result[entry.key as String] = _normalizeDesktopMiniAppIpcValue(
          entry.value,
        );
      }
    }
    return result;
  }
  if (source is TypedData) return source;
  if (source is List) {
    return source
        .map<Object?>(_normalizeDesktopMiniAppIpcValue)
        .toList(growable: false);
  }
  return source;
}

Map<String, dynamic> _sanitizeTdObject(Map<String, dynamic> source) =>
    <String, dynamic>{...source}
      ..remove('@client_id')
      ..remove('@extra');

class _DesktopMiniAppMainBridge with WindowListener {
  final DesktopMiniAppWindowRegistry _registry = DesktopMiniAppWindowRegistry();
  final DesktopMiniAppLaunchLifecycle _lifecycle =
      DesktopMiniAppLaunchLifecycle();
  final Map<int, MultiWindowManager> _controllers = {};
  final Map<String, DesktopMiniAppWindowArguments> _pendingLaunches = {};
  final Map<String, DesktopMiniAppAccountBinding> _bindings = {};
  bool _attached = false;

  void attach() {
    if (_attached || !supportsDesktopMiniAppWindows) return;
    try {
      MultiWindowManager.current.addListener(this);
      MultiWindowManager.addGlobalListener(this);
      MultiWindowManager.current.activeWindows.addListener(
        _handleActiveWindowsChanged,
      );
      _attached = true;
    } on Object {
      // Portable/test builds can omit the native plugin. Never start TDLib in
      // a child engine as a fallback.
    }
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    MultiWindowManager.current.removeListener(this);
    MultiWindowManager.removeGlobalListener(this);
    MultiWindowManager.current.activeWindows.removeListener(
      _handleActiveWindowsChanged,
    );
    for (final arguments in _pendingLaunches.values.toList(growable: false)) {
      _cancelLaunch(arguments);
    }
    for (final windowId in _registry.windowIds.toList(growable: false)) {
      final controller = _removeWindow(windowId);
      if (controller != null) unawaited(_closeController(controller));
    }
    _pendingLaunches.clear();
    _bindings.clear();
  }

  Future<bool> open(DesktopMiniAppWindowLaunch launch) async {
    if (!supportsDesktopMiniAppWindows) return false;
    final pinnedLaunch = await _pinLaunchToCurrentAccount(launch);
    if (pinnedLaunch == null) return false;
    return _openPinned(pinnedLaunch);
  }

  Future<bool> _openPinned(
    ({DesktopMiniAppWindowLaunch launch, DesktopMiniAppAccountBinding binding})
    pinned,
  ) async {
    final launch = pinned.launch;
    final arguments = launch.arguments;
    if (_lifecycle.isCancelled(arguments) || _lifecycle.isClosed(arguments)) {
      return false;
    }
    attach();
    _bindings[arguments.lifecycleKey] = pinned.binding;
    _pendingLaunches[arguments.lifecycleKey] = arguments;
    MultiWindowManager? createdWindow;
    var registered = false;
    try {
      // Mini Apps intentionally never reuse or deduplicate an engine: each
      // launch has its own WKWebView, navigation stack, and TD launch lifetime.
      createdWindow = await MultiWindowManager.createWindow([
        arguments.encode(),
      ]);
      if (createdWindow == null || createdWindow.id <= 0) {
        _closeLaunch(arguments);
        return false;
      }
      if (_lifecycle.isCancelled(arguments) || _lifecycle.isClosed(arguments)) {
        await _closeController(createdWindow);
        return false;
      }
      _registry.register(createdWindow.id, launch);
      _controllers[createdWindow.id] = createdWindow;
      registered = true;
      await createdWindow.waitUntilReadyToShow(
        desktopMiniAppWindowOptions(arguments),
      );
      if (!_isActiveLaunch(createdWindow.id, arguments)) {
        await _closeController(createdWindow);
        return false;
      }
      await createdWindow.show();
      if (!_isActiveLaunch(createdWindow.id, arguments)) {
        await _closeController(createdWindow);
        return false;
      }
      await createdWindow.focus();
      return _isActiveLaunch(createdWindow.id, arguments);
    } on Object {
      final failedWindow = createdWindow;
      if (failedWindow != null) {
        if (registered) {
          _removeWindow(failedWindow.id);
        } else {
          _closeLaunch(arguments);
        }
        await _closeController(failedWindow);
      } else {
        _closeLaunch(arguments);
      }
      assert(() {
        debugPrint('Desktop Mini App window open failed');
        return true;
      }());
      return false;
    } finally {
      if (identical(_pendingLaunches[arguments.lifecycleKey], arguments)) {
        _pendingLaunches.remove(arguments.lifecycleKey);
      }
    }
  }

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic arguments,
  ) async {
    if (eventName == _openMethod) {
      return _handleChildOpenRequest(fromWindowId, arguments);
    }
    if (eventName == _cleanupMethod) {
      return _handleChildCleanupRequest(fromWindowId, arguments);
    }
    final registered = _registeredRequest(fromWindowId, arguments);
    if (registered == null) return null;

    switch (eventName) {
      case _connectMethod:
        final binding = _bindingFor(registered.arguments);
        if (binding == null || !await _verifyAccountBinding(binding)) {
          _closeStaleWindow(fromWindowId);
          return const {'ok': false};
        }
        return {'ok': true, 'launch': registered.toChildJson()};
      case _queryMethod:
        final request = arguments is Map
            ? desktopMiniAppSanitizeRequest(arguments['request'])
            : null;
        if (request == null || request.type == 'closeWebApp') {
          return const <String, dynamic>{
            '@type': 'error',
            'code': 400,
            'message': 'Unsupported Mini App window request',
          };
        }
        return _query(registered.arguments, request);
      case _sendMethod:
        final request = arguments is Map
            ? desktopMiniAppSanitizeRequest(arguments['request'])
            : null;
        if (request == null || request.type == 'closeWebApp') {
          return const {'ok': false};
        }
        return _send(registered.arguments, request);
      case _openPrimaryChatMethod:
        final binding = _bindingFor(registered.arguments);
        if (binding == null || !await _verifyAccountBinding(binding)) {
          _closeStaleWindow(fromWindowId);
          return const {'ok': false};
        }
        final request = arguments is Map
            ? ChatDeepLinkRequest.tryParseDesktopIpc(arguments['chat'])
            : null;
        if (request == null) return const {'ok': false};
        ChatDeepLinkController.shared.openChat(
          chatId: request.chatId,
          title: request.title,
          messageId: request.messageId,
          accountSlot: binding.accountSlot,
          accountUserId: binding.accountUserId,
        );
        try {
          await MultiWindowManager.current.show();
          await MultiWindowManager.current.focus();
        } on Object {
          // The authenticated deep link remains queued if native focus fails.
        }
        return const {'ok': true};
      default:
        return null;
    }
  }

  Future<Map<String, Object?>> _handleChildOpenRequest(
    int fromWindowId,
    Object? source,
  ) async {
    if (source is! Map) return const {'ok': false, 'handled': false};
    final account = _registeredSourceAccount(fromWindowId, source);
    if (account == null) {
      return const {'ok': false, 'handled': false};
    }
    final launch = DesktopMiniAppWindowLaunch.tryParsePrimaryOpenJson(
      source['launch'],
      accountSlot: account.accountSlot,
      accountUserId: account.accountUserId,
    );
    if (launch == null) return const {'ok': false, 'handled': false};
    final pinned = await _pinLaunchToCurrentAccount(launch);
    if (pinned == null) return const {'ok': false, 'handled': false};
    return {'ok': await _openPinned(pinned), 'handled': true};
  }

  Future<Map<String, Object?>> _handleChildCleanupRequest(
    int fromWindowId,
    Object? source,
  ) async {
    if (source is! Map) return const {'ok': false, 'handled': false};
    final account = _registeredSourceAccount(fromWindowId, source);
    if (account == null) {
      return const {'ok': false, 'handled': false};
    }
    final requested = DesktopMiniAppWindowArguments.tryParsePrimaryCleanupJson(
      source['cleanup'],
      accountSlot: account.accountSlot,
      accountUserId: account.accountUserId,
    );
    if (requested == null) {
      return const {'ok': false, 'handled': false};
    }
    final pinned = await _pinArgumentsToCurrentAccount(requested);
    if (pinned == null) return const {'ok': false, 'handled': false};
    _cancelLaunch(pinned.arguments, binding: pinned.binding);
    return const {'ok': true, 'handled': true};
  }

  ({int accountSlot, int? accountUserId})? _registeredSourceAccount(
    int fromWindowId,
    Map source,
  ) {
    final sourceIdentity = source['source'];
    final account = switch (source['sourceType']) {
      'chat' => registeredDesktopChatWindowAccountIdentity(
        fromWindowId,
        sourceIdentity,
      ),
      'utility' => registeredDesktopUtilityWindowAccountIdentity(
        fromWindowId,
        sourceIdentity,
      ),
      'mini-app' => switch (_registeredRequest(fromWindowId, sourceIdentity)) {
        final registered? => (
          accountSlot: registered.arguments.accountSlot,
          accountUserId: registered.arguments.accountUserId,
        ),
        null => null,
      },
      _ => null,
    };
    // A slot without its original user cannot distinguish account A from a
    // later account B that reused the same slot, so it cannot authorize a
    // nested launch or cleanup request.
    return account?.accountUserId == null ? null : account;
  }

  DesktopMiniAppWindowLaunch? _registeredRequest(int windowId, Object? source) {
    if (windowId <= 0) return null;
    final registered = _registry.launchFor(windowId);
    return registered != null && registered.arguments.matchesIpc(source)
        ? registered
        : null;
  }

  Future<
    ({DesktopMiniAppWindowLaunch launch, DesktopMiniAppAccountBinding binding})?
  >
  _pinLaunchToCurrentAccount(DesktopMiniAppWindowLaunch launch) async {
    final pinned = await _pinArgumentsToCurrentAccount(launch.arguments);
    if (pinned == null) return null;
    return (
      launch: DesktopMiniAppWindowLaunch(
        arguments: pinned.arguments,
        url: launch.url,
        keyboardButtonText: launch.keyboardButtonText,
      ),
      binding: pinned.binding,
    );
  }

  Future<
    ({
      DesktopMiniAppWindowArguments arguments,
      DesktopMiniAppAccountBinding binding,
    })?
  >
  _pinArgumentsToCurrentAccount(DesktopMiniAppWindowArguments arguments) async {
    final clientId = TdClient.shared.clientId(arguments.accountSlot);
    if (clientId == null) return null;
    try {
      final me = await TdClient.shared
          .queryTo({'@type': 'getMe'}, clientId)
          .timeout(const Duration(seconds: 5));
      final accountUserId = me.int64('id');
      if (accountUserId == null || accountUserId <= 0) return null;
      final expectedAccountUserId = arguments.accountUserId;
      if (expectedAccountUserId != null &&
          expectedAccountUserId != accountUserId) {
        return null;
      }
      final binding = DesktopMiniAppAccountBinding(
        accountSlot: arguments.accountSlot,
        accountUserId: accountUserId,
        clientId: clientId,
      );
      if (!binding.matchesCurrent(
        currentClientId: TdClient.shared.clientId(arguments.accountSlot),
        currentAccountUserId: accountUserId,
      )) {
        return null;
      }
      return (
        arguments: arguments.withAccountIdentity(
          accountSlot: arguments.accountSlot,
          accountUserId: accountUserId,
        ),
        binding: binding,
      );
    } on Object {
      return null;
    }
  }

  Future<Map<String, dynamic>> _query(
    DesktopMiniAppWindowArguments arguments,
    Map<String, dynamic> request,
  ) async {
    final binding = _bindingFor(arguments);
    if (binding == null || !await _verifyAccountBinding(binding)) {
      return const {
        '@type': 'error',
        'code': 403,
        'message': 'Mini App account is no longer available',
      };
    }
    try {
      return _sanitizeTdObject(
        await TdClient.shared.queryTo(request, binding.clientId),
      );
    } on TdError catch (error) {
      return {'@type': 'error', 'code': error.code, 'message': error.message};
    } on Object {
      return const {
        '@type': 'error',
        'code': 500,
        'message': 'Mini App window request failed',
      };
    }
  }

  Future<Map<String, Object?>> _send(
    DesktopMiniAppWindowArguments arguments,
    Map<String, dynamic> request,
  ) async {
    final binding = _bindingFor(arguments);
    if (binding == null || !await _verifyAccountBinding(binding)) {
      return const {'ok': false};
    }
    TdClient.shared.sendTo(request, binding.clientId);
    return const {'ok': true};
  }

  DesktopMiniAppAccountBinding? _bindingFor(
    DesktopMiniAppWindowArguments arguments,
  ) {
    final binding = _bindings[arguments.lifecycleKey];
    return binding != null &&
            binding.accountSlot == arguments.accountSlot &&
            binding.accountUserId == arguments.accountUserId
        ? binding
        : null;
  }

  Future<bool> _verifyAccountBinding(
    DesktopMiniAppAccountBinding binding,
  ) async {
    if (TdClient.shared.clientId(binding.accountSlot) != binding.clientId) {
      return false;
    }
    try {
      final me = await TdClient.shared
          .queryTo({'@type': 'getMe'}, binding.clientId)
          .timeout(const Duration(seconds: 3));
      final currentAccountUserId = me.int64('id');
      return binding.matchesCurrent(
        currentClientId: TdClient.shared.clientId(binding.accountSlot),
        currentAccountUserId: currentAccountUserId,
      );
    } on Object {
      return false;
    }
  }

  void closeStaleAccountWindows() {
    for (final windowId in _registry.windowIds.toList(growable: false)) {
      final launch = _registry.launchFor(windowId);
      final binding = launch == null ? null : _bindingFor(launch.arguments);
      if (binding == null) {
        _closeStaleWindow(windowId);
      } else {
        unawaited(_closeWindowUnlessBindingIsCurrent(windowId, binding));
      }
    }
  }

  Future<void> _closeWindowUnlessBindingIsCurrent(
    int windowId,
    DesktopMiniAppAccountBinding binding,
  ) async {
    if (!await _verifyAccountBinding(binding)) _closeStaleWindow(windowId);
  }

  void _closeStaleWindow(int windowId) {
    final controller = _removeWindow(windowId);
    if (controller != null) unawaited(_closeController(controller));
  }

  void _handleActiveWindowsChanged() {
    final active = MultiWindowManager.current.activeWindows.value.toSet();
    for (final windowId in _registry.windowIds.toList(growable: false)) {
      if (!active.contains(windowId)) _removeWindow(windowId);
    }
  }

  bool _isActiveLaunch(int windowId, DesktopMiniAppWindowArguments arguments) =>
      _registry.launchFor(windowId)?.arguments.lifecycleKey ==
          arguments.lifecycleKey &&
      !_lifecycle.isCancelled(arguments) &&
      !_lifecycle.isClosed(arguments);

  MultiWindowManager? _removeWindow(int windowId) {
    final launch = _registry.remove(windowId);
    if (launch != null) _closeLaunch(launch.arguments);
    return _controllers.remove(windowId);
  }

  void _cancelLaunch(
    DesktopMiniAppWindowArguments arguments, {
    DesktopMiniAppAccountBinding? binding,
  }) {
    final closeIsDue = _lifecycle.cancel(arguments);
    final closeBinding = _bindings.remove(arguments.lifecycleKey) ?? binding;
    if (closeIsDue && closeBinding != null) {
      unawaited(_sendCloseWebApp(arguments, closeBinding));
    }
    final windowId = _registry.windowForLifecycleKey(arguments.lifecycleKey);
    if (windowId == null) return;
    final controller = _removeWindow(windowId);
    if (controller != null) unawaited(_closeController(controller));
  }

  void _closeLaunch(DesktopMiniAppWindowArguments arguments) {
    final binding = _bindings.remove(arguments.lifecycleKey);
    if (!_lifecycle.claimClose(arguments)) return;
    if (binding != null) unawaited(_sendCloseWebApp(arguments, binding));
  }

  Future<void> _sendCloseWebApp(
    DesktopMiniAppWindowArguments arguments,
    DesktopMiniAppAccountBinding binding,
  ) async {
    final launchId = arguments.launchId;
    if (launchId == null ||
        arguments.accountSlot != binding.accountSlot ||
        arguments.accountUserId != binding.accountUserId) {
      return;
    }
    for (var attempt = 0; attempt < 3; attempt += 1) {
      if (TdClient.shared.clientId(binding.accountSlot) != binding.clientId) {
        return;
      }
      if (await _verifyAccountBinding(binding)) {
        TdClient.shared.sendTo({
          '@type': 'closeWebApp',
          'web_app_launch_id': launchId,
        }, binding.clientId);
        return;
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> _closeController(MultiWindowManager controller) async {
    try {
      await controller.close();
    } on Object {
      // The native child may already have closed during a startup race.
    }
  }

  @override
  void onWindowClose([int? windowId]) {
    if (windowId != null && windowId > 0) _removeWindow(windowId);
  }
}

class _DesktopMiniAppChildProxy with WindowListener {
  _DesktopMiniAppChildProxy(this.arguments) {
    MultiWindowManager.current.addListener(this);
  }

  final DesktopMiniAppWindowArguments arguments;
  bool _closed = false;

  Future<DesktopMiniAppWindowLaunch> connect() async {
    for (var attempt = 0; attempt < 30; attempt += 1) {
      try {
        final response = await MultiWindowManager.current
            .invokeMethodToWindow(0, _connectMethod, arguments.toIpcJson())
            .timeout(const Duration(seconds: 2));
        if (response is Map && response['ok'] == true) {
          final launch = DesktopMiniAppWindowLaunch.tryParseChildJson(
            arguments,
            response['launch'],
          );
          if (launch != null) return launch;
        }
      } on Object {
        // Window creation can finish before the primary registry entry is
        // visible to the child engine. Retry only this local handshake.
      }
      if (attempt < 29) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    throw StateError('Primary Mini App transport is unavailable');
  }

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    if (_closed) {
      return const {
        '@type': 'error',
        'code': 503,
        'message': 'Mini App window transport is closed',
      };
    }
    final response = await MultiWindowManager.current
        .invokeMethodToWindow(0, _queryMethod, {
          ...arguments.toIpcJson(),
          'request': request,
        })
        .timeout(const Duration(seconds: 30));
    return desktopMiniAppNormalizeIpcMap(response) ??
        const {
          '@type': 'error',
          'code': 500,
          'message': 'Invalid primary Mini App response',
        };
  }

  Future<void> send(Map<String, dynamic> request) async {
    if (_closed) return;
    await MultiWindowManager.current
        .invokeMethodToWindow(0, _sendMethod, {
          ...arguments.toIpcJson(),
          'request': request,
        })
        .timeout(const Duration(seconds: 10));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    MultiWindowManager.current.removeListener(this);
    await TdClient.shared.closeProxy();
  }

  @override
  void onWindowClose([int? windowId]) {
    unawaited(close());
  }
}
