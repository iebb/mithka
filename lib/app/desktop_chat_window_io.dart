import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'chat_deep_link_controller.dart';
import 'desktop_chat_window_models.dart';
import 'desktop_utility_window.dart';

const _subscribeMethod = 'mithka.chat.td.subscribe';
const _queryMethod = 'mithka.chat.td.query';
const _sendMethod = 'mithka.chat.td.send';
const _updateMethod = 'mithka.chat.td.update';
const _openUtilityMethod = 'mithka.chat.utility.open';
const _openPrimaryChatMethod = 'mithka.chat.primary-chat.open';
const _presentationChangedMethod = 'mithka.chat.presentation.changed';

const _chatWindowSize = Size(1120, 760);
const _chatWindowMinimumSize = Size(720, 520);

const _blockedRequestTypes = <String>{
  'close',
  'destroy',
  'logOut',
  'setTdlibParameters',
};

bool get supportsDesktopChatWindows =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

final _mainBridge = _DesktopChatMainBridge();
Future<void> Function()? _childPresentationReload;
DesktopChatWindowArguments? _childArguments;

void attachDesktopChatMainProxy({
  int? Function(int accountSlot)? accountUserIdForSlot,
}) => _mainBridge.attach(accountUserIdForSlot: accountUserIdForSlot);

void detachDesktopChatMainProxy() => _mainBridge.detach();

void notifyDesktopChatAccountIdentityChanged() =>
    _mainBridge.closeStaleAccountWindows();

void attachDesktopChatChildPresentationReload(
  Future<void> Function() callback,
) => _childPresentationReload = callback;

void detachDesktopChatChildPresentationReload() =>
    _childPresentationReload = null;

Map<String, Object?>? desktopChatChildWindowIdentity() =>
    _childArguments?.toIpcJson();

int? registeredDesktopChatWindowAccountSlot(int windowId, Object? source) =>
    _mainBridge.registeredAccountSlot(windowId, source);

({int accountSlot, int? accountUserId})?
registeredDesktopChatWindowAccountIdentity(int windowId, Object? source) =>
    _mainBridge.registeredAccountIdentity(windowId, source);

Future<void> notifyDesktopChatPresentationChanged() async {
  if (!supportsDesktopChatWindows || MultiWindowManager.current.id > 0) {
    return;
  }
  _mainBridge.schedulePresentationChanged();
  await DesktopUtilityWindowService.instance.notifyPresentationChanged();
}

Future<bool> openDesktopChatWindow(DesktopChatWindowArguments arguments) =>
    _mainBridge.open(arguments);

Future<bool> openChatInPrimaryWindowFromDesktopChat(
  ChatDeepLinkRequest request,
) async {
  if (!supportsDesktopChatWindows || MultiWindowManager.current.id <= 0) {
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

Future<bool> requestDesktopUtilityWindowFromChat({
  required DesktopChatWindowArguments requestingChat,
  required DesktopUtilityWindowArguments utility,
}) async {
  if (!supportsDesktopChatWindows ||
      !desktopChatUtilityRequestIsAllowed(
        requestingChat: requestingChat,
        utility: utility,
      )) {
    return false;
  }
  if (MultiWindowManager.current.id <= 0) {
    return DesktopUtilityWindowService.instance.open(utility);
  }
  try {
    final response = await MultiWindowManager.current
        .invokeMethodToWindow(0, _openUtilityMethod, {
          ...requestingChat.toIpcJson(),
          'utility': utility.encode(),
        })
        .timeout(const Duration(seconds: 10));
    return response is Map && response['ok'] == true;
  } on Object {
    return false;
  }
}

Future<void> configureDesktopChatChildProxy(
  DesktopChatWindowArguments arguments,
) async {
  _childArguments = arguments;
  final proxy = _DesktopChatChildProxy(arguments);
  TdClient.shared.configureProxy(
    TdClientProxyTransport(
      accountSlot: arguments.accountSlot,
      accountUserId: arguments.accountUserId,
      query: proxy.query,
      send: proxy.send,
      updates: proxy.updates,
    ),
  );
  await proxy.subscribe();
}

Future<void> closeCurrentDesktopChatWindow() async {
  if (!supportsDesktopChatWindows || MultiWindowManager.current.id <= 0) {
    return;
  }
  try {
    await MultiWindowManager.current.close();
  } on Object {
    // Closing an already-destroyed native child is a harmless no-op.
  }
}

Widget buildDesktopChatWindowHost({
  required DesktopChatWindowArguments initialArguments,
  required Widget Function(
    BuildContext context,
    DesktopChatWindowArguments arguments,
  )
  builder,
}) => Builder(builder: (context) => builder(context, initialArguments));

WindowOptions _windowOptions(DesktopChatWindowArguments arguments) =>
    WindowOptions(
      size: _chatWindowSize,
      minimumSize: _chatWindowMinimumSize,
      center: true,
      title: arguments.title,
      backgroundColor: Color(arguments.palette.chatBackground),
      titleBarStyle: TitleBarStyle.normal,
      windowButtonVisibility: true,
    );

@visibleForTesting
bool desktopChatRequestTypeIsAllowed(Object? type) =>
    type is String && type.isNotEmpty && !_blockedRequestTypes.contains(type);

@visibleForTesting
bool desktopChatUtilityRequestIsAllowed({
  required DesktopChatWindowArguments requestingChat,
  required DesktopUtilityWindowArguments utility,
}) {
  if (utility.accountSlot != requestingChat.accountSlot ||
      (utility.accountUserId != null &&
          utility.accountUserId != requestingChat.accountUserId)) {
    return false;
  }
  return switch (utility.kind) {
    DesktopUtilityWindowKind.chatInfo =>
      utility.chatId == requestingChat.chatId,
    DesktopUtilityWindowKind.userProfile => (utility.userId ?? 0) > 0,
    DesktopUtilityWindowKind.audioPicker ||
    DesktopUtilityWindowKind.locationPicker ||
    DesktopUtilityWindowKind.contactPicker ||
    DesktopUtilityWindowKind.pollComposer ||
    DesktopUtilityWindowKind.checklistComposer ||
    DesktopUtilityWindowKind.scheduledMessages ||
    DesktopUtilityWindowKind.richTextComposer ||
    DesktopUtilityWindowKind.aiEditor =>
      utility.chatId == requestingChat.chatId,
    _ => false,
  };
}

@visibleForTesting
Map<String, dynamic>? desktopChatSanitizeRequest(Object? source) {
  final request = desktopChatNormalizeIpcMap(source);
  if (request == null) return null;
  if (!desktopChatRequestTypeIsAllowed(request['@type'])) return null;
  request
    ..remove('@client_id')
    ..remove('@extra');
  return request;
}

/// StandardMessageCodec returns nested maps as `Map<Object?, Object?>`.
/// Normalize the complete object graph once at the desktop IPC boundary so
/// TDLib's typed JSON helpers can read messages, entities, and live updates.
@visibleForTesting
Map<String, dynamic>? desktopChatNormalizeIpcMap(Object? source) {
  final normalized = _normalizeDesktopChatIpcValue(source);
  return normalized is Map<String, dynamic> ? normalized : null;
}

Object? _normalizeDesktopChatIpcValue(Object? source) {
  if (source is Map) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      if (entry.key is String) {
        result[entry.key as String] = _normalizeDesktopChatIpcValue(
          entry.value,
        );
      }
    }
    return result;
  }
  if (source is TypedData) return source;
  if (source is List) {
    return source.map<Object?>(_normalizeDesktopChatIpcValue).toList();
  }
  return source;
}

Map<String, dynamic> _sanitizeTdObject(Map<String, dynamic> source) =>
    <String, dynamic>{...source}
      ..remove('@client_id')
      ..remove('@extra');

class _DesktopChatMainBridge with WindowListener {
  final DesktopChatWindowRegistry _registry = DesktopChatWindowRegistry();
  final Map<int, DesktopChatWindowArguments> _argumentsByWindow = {};
  final Set<int> _subscribedWindows = {};
  StreamSubscription<Map<String, dynamic>>? _tdUpdates;
  Timer? _presentationChangedDebounce;
  int? Function(int accountSlot)? _accountUserIdForSlot;
  bool _attached = false;

  void attach({int? Function(int accountSlot)? accountUserIdForSlot}) {
    if (!_attached || accountUserIdForSlot != null) {
      _accountUserIdForSlot = accountUserIdForSlot;
    }
    if (_attached || !supportsDesktopChatWindows) return;
    try {
      MultiWindowManager.current.addListener(this);
      MultiWindowManager.addGlobalListener(this);
      MultiWindowManager.current.activeWindows.addListener(
        _handleActiveWindowsChanged,
      );
      _tdUpdates = TdClient.shared.subscribeAll().listen(_handleTdUpdate);
      _attached = true;
    } on Object {
      // Portable builds may omit the native plugin. The primary process still
      // owns TDLib; never create a second client as a fallback.
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
    unawaited(_tdUpdates?.cancel());
    _tdUpdates = null;
    _presentationChangedDebounce?.cancel();
    _presentationChangedDebounce = null;
    _argumentsByWindow.clear();
    _subscribedWindows.clear();
    _registry.clear();
    _accountUserIdForSlot = null;
  }

  void schedulePresentationChanged() {
    attach();
    _presentationChangedDebounce?.cancel();
    _presentationChangedDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_broadcastPresentationChanged()),
    );
  }

  Future<void> _broadcastPresentationChanged() async {
    _presentationChangedDebounce = null;
    for (final windowId in _argumentsByWindow.keys.toList(growable: false)) {
      try {
        await MultiWindowManager.current.invokeMethodToWindow(
          windowId,
          _presentationChangedMethod,
          const {'reloadPreferences': true},
        );
      } on Object {
        _removeWindow(windowId);
      }
    }
  }

  Future<bool> open(DesktopChatWindowArguments arguments) async {
    if (!supportsDesktopChatWindows) return false;
    attach();
    if (!_identityIsCurrent(arguments)) return false;
    MultiWindowManager? createdWindow;
    try {
      final active = await MultiWindowManager.current.getActiveWindowIds();
      final existing = _registry.activeWindowFor(arguments.key, active);
      if (existing != null) {
        final window = MultiWindowManager.fromWindowId(existing);
        await window.show();
        await window.focus();
        return true;
      }

      // A chat child binds its TD proxy exactly once. Always create a fresh
      // engine instead of reusing a hidden child that may belong to another
      // account or to the video/image window type.
      createdWindow = await MultiWindowManager.createWindow([
        arguments.encode(),
      ]);
      if (createdWindow == null || createdWindow.id <= 0) return false;
      _registerWindow(createdWindow.id, arguments);

      await createdWindow.waitUntilReadyToShow(_windowOptions(arguments));
      await createdWindow.show();
      await createdWindow.focus();
      return true;
    } on Object catch (error) {
      final failedWindow = createdWindow;
      if (failedWindow != null) {
        _removeWindow(failedWindow.id);
        try {
          await failedWindow.close();
        } on Object {
          // The native child may already have closed during startup.
        }
      }
      assert(() {
        debugPrint('Desktop chat window open failed: $error');
        return true;
      }());
      return false;
    }
  }

  void _registerWindow(int windowId, DesktopChatWindowArguments arguments) {
    for (final entry in _argumentsByWindow.entries.toList(growable: false)) {
      if (entry.key == windowId || entry.value.key == arguments.key) {
        _removeWindow(entry.key);
      }
    }
    _argumentsByWindow[windowId] = arguments;
    _registry.register(arguments.key, windowId);
  }

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic arguments,
  ) async {
    final registered = _registeredRequest(fromWindowId, arguments);
    if (registered == null) return null;

    switch (eventName) {
      case _subscribeMethod:
        _subscribedWindows.add(fromWindowId);
        return {
          'ok': true,
          'updates': _bootstrapUpdates(registered.accountSlot),
        };
      case _queryMethod:
        final request = arguments is Map
            ? desktopChatSanitizeRequest(arguments['request'])
            : null;
        return request == null
            ? const <String, dynamic>{
                '@type': 'error',
                'code': 400,
                'message': 'Unsupported desktop chat request',
              }
            : _query(registered.accountSlot, request);
      case _sendMethod:
        final request = arguments is Map
            ? desktopChatSanitizeRequest(arguments['request'])
            : null;
        if (request == null) return const {'ok': false};
        return _send(registered.accountSlot, request);
      case _openUtilityMethod:
        final encoded = arguments is Map ? arguments['utility'] : null;
        final utility = encoded is String
            ? DesktopUtilityWindowArguments.tryParse(encoded)
            : null;
        if (utility == null ||
            !desktopChatUtilityRequestIsAllowed(
              requestingChat: registered,
              utility: utility,
            )) {
          return const {'ok': false};
        }
        return {'ok': await DesktopUtilityWindowService.instance.open(utility)};
      case _openPrimaryChatMethod:
        final request = arguments is Map
            ? ChatDeepLinkRequest.tryParseDesktopIpc(arguments['chat'])
            : null;
        if (request == null) return const {'ok': false};
        ChatDeepLinkController.shared.openChat(
          chatId: request.chatId,
          title: request.title,
          messageId: request.messageId,
          accountSlot: registered.accountSlot,
          accountUserId: registered.accountUserId,
        );
        try {
          await MultiWindowManager.current.show();
          await MultiWindowManager.current.focus();
        } on Object {
          // The queued primary-window deep link remains valid if native focus
          // is unavailable on this desktop build.
        }
        return const {'ok': true};
      default:
        return null;
    }
  }

  DesktopChatWindowArguments? _registeredRequest(int windowId, Object? source) {
    if (windowId <= 0) return null;
    final requestedKey = _keyFromIpc(source);
    final registered = _argumentsByWindow[windowId];
    if (requestedKey == null ||
        registered == null ||
        !desktopChatWindowRequestIsRegistered(
          registry: _registry,
          windowId: windowId,
          requestedKey: requestedKey,
        )) {
      return null;
    }
    if (!_identityIsCurrent(registered)) {
      _rejectStaleWindow(windowId);
      return null;
    }
    return registered;
  }

  bool _identityIsCurrent(DesktopChatWindowArguments arguments) {
    final resolver = _accountUserIdForSlot;
    return resolver == null ||
        resolver(arguments.accountSlot) == arguments.accountUserId;
  }

  void closeStaleAccountWindows() {
    if (_accountUserIdForSlot == null) return;
    for (final entry in _argumentsByWindow.entries.toList(growable: false)) {
      if (!_identityIsCurrent(entry.value)) _rejectStaleWindow(entry.key);
    }
  }

  void _rejectStaleWindow(int windowId) {
    _removeWindow(windowId);
    unawaited(_closeWindow(windowId));
  }

  Future<void> _closeWindow(int windowId) async {
    try {
      await MultiWindowManager.fromWindowId(windowId).close();
    } on Object {
      // A stale or already-closed child is fully rejected locally.
    }
  }

  int? registeredAccountSlot(int windowId, Object? source) =>
      _registeredRequest(windowId, source)?.accountSlot;

  ({int accountSlot, int? accountUserId})? registeredAccountIdentity(
    int windowId,
    Object? source,
  ) {
    final registered = _registeredRequest(windowId, source);
    return registered == null
        ? null
        : (
            accountSlot: registered.accountSlot,
            accountUserId: registered.accountUserId,
          );
  }

  DesktopChatWindowKey? _keyFromIpc(Object? source) {
    if (source is! Map ||
        source['accountSlot'] is! int ||
        source['chatId'] is! int) {
      return null;
    }
    final accountSlot = source['accountSlot']! as int;
    final chatId = source['chatId']! as int;
    if (accountSlot < 0 || chatId == 0) return null;
    return DesktopChatWindowKey(accountSlot: accountSlot, chatId: chatId);
  }

  List<Map<String, dynamic>> _bootstrapUpdates(int accountSlot) {
    final clientId = TdClient.shared.clientId(accountSlot);
    if (clientId == null) return const [];
    return [
      TdClient.shared.latestChatFoldersUpdateForClient(clientId),
      TdClient.shared.latestEmojiChatThemesUpdateForClient(clientId),
      TdClient.shared.latestTextCompositionStylesUpdateForClient(clientId),
      ...TdClient.shared.latestCommunityUpdatesForClient(clientId),
    ].whereType<Map<String, dynamic>>().map(_sanitizeTdObject).toList();
  }

  Future<Map<String, dynamic>> _query(
    int accountSlot,
    Map<String, dynamic> request,
  ) async {
    final clientId = TdClient.shared.clientId(accountSlot);
    if (clientId == null) {
      return const {
        '@type': 'error',
        'code': 503,
        'message': 'Account is unavailable',
      };
    }
    try {
      return _sanitizeTdObject(
        await TdClient.shared.queryTo(request, clientId),
      );
    } on TdError catch (error) {
      return {'@type': 'error', 'code': error.code, 'message': error.message};
    } on Object {
      return const {
        '@type': 'error',
        'code': 500,
        'message': 'Desktop chat request failed',
      };
    }
  }

  Map<String, Object?> _send(int accountSlot, Map<String, dynamic> request) {
    final clientId = TdClient.shared.clientId(accountSlot);
    if (clientId == null) return const {'ok': false};
    TdClient.shared.sendTo(request, clientId);
    return const {'ok': true};
  }

  void _handleTdUpdate(Map<String, dynamic> source) {
    final clientId = source.integer('@client_id');
    if (clientId == null) return;
    final accountSlot = TdClient.shared.slotForClient(clientId);
    if (accountSlot == null) return;
    final update = _sanitizeTdObject(source);
    for (final entry in _argumentsByWindow.entries.toList(growable: false)) {
      if (entry.value.accountSlot != accountSlot ||
          !_subscribedWindows.contains(entry.key)) {
        continue;
      }
      if (!_identityIsCurrent(entry.value)) {
        _rejectStaleWindow(entry.key);
        continue;
      }
      unawaited(_pushUpdate(entry.key, update));
    }
  }

  Future<void> _pushUpdate(int windowId, Map<String, dynamic> update) async {
    try {
      await MultiWindowManager.current.invokeMethodToWindow(
        windowId,
        _updateMethod,
        update,
      );
    } on Object {
      _removeWindow(windowId);
    }
  }

  void _handleActiveWindowsChanged() {
    final active = MultiWindowManager.current.activeWindows.value.toSet();
    for (final windowId in _argumentsByWindow.keys.toList(growable: false)) {
      if (!active.contains(windowId)) _removeWindow(windowId);
    }
    _registry.retainActive(active);
  }

  void _removeWindow(int windowId) {
    _argumentsByWindow.remove(windowId);
    _subscribedWindows.remove(windowId);
    _registry.removeWindow(windowId);
  }

  @override
  void onWindowClose([int? windowId]) {
    if (windowId != null && windowId > 0) _removeWindow(windowId);
  }
}

class _DesktopChatChildProxy with WindowListener {
  _DesktopChatChildProxy(this.arguments) {
    MultiWindowManager.current.addListener(this);
  }

  final DesktopChatWindowArguments arguments;
  final StreamController<Map<String, dynamic>> _updates =
      StreamController.broadcast(sync: true);
  bool _closed = false;

  Stream<Map<String, dynamic>> get updates => _updates.stream;

  Future<void> subscribe() async {
    Map? response;
    for (var attempt = 0; attempt < 30 && response == null; attempt += 1) {
      try {
        final value = await MultiWindowManager.current
            .invokeMethodToWindow(0, _subscribeMethod, arguments.toIpcJson())
            .timeout(const Duration(seconds: 2));
        if (value is Map && value['ok'] == true) response = value;
      } on Object {
        // createWindow can finish before the primary registry entry becomes
        // visible to the new engine. Retry only this bounded local handshake.
      }
      if (response == null && attempt < 29) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (response == null) {
      throw StateError('Primary chat transport is unavailable');
    }
    final bootstrap = response['updates'];
    if (bootstrap is List) {
      for (final update in bootstrap) {
        final normalized = desktopChatNormalizeIpcMap(update);
        if (normalized != null) _updates.add(normalized);
      }
    }
  }

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    if (_closed) {
      return const {
        '@type': 'error',
        'code': 503,
        'message': 'Desktop chat transport is closed',
      };
    }
    final response = await MultiWindowManager.current
        .invokeMethodToWindow(0, _queryMethod, {
          ...arguments.toIpcJson(),
          'request': request,
        })
        .timeout(const Duration(seconds: 30));
    return desktopChatNormalizeIpcMap(response) ??
        const {
          '@type': 'error',
          'code': 500,
          'message': 'Invalid primary chat response',
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

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic eventArguments,
  ) async {
    if (fromWindowId != 0) return null;
    if (eventName == _updateMethod) {
      final update = desktopChatNormalizeIpcMap(eventArguments);
      if (!_closed && update != null) _updates.add(update);
      return const {'ok': true};
    }
    if (eventName == _presentationChangedMethod) {
      final callback = _childPresentationReload;
      if (callback == null) return const {'ok': false};
      await callback();
      return const {'ok': true};
    }
    return null;
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    MultiWindowManager.current.removeListener(this);
    await TdClient.shared.closeProxy();
    await _updates.close();
  }

  @override
  void onWindowClose([int? windowId]) {
    unawaited(_close());
  }
}
