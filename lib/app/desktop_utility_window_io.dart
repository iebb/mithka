import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'chat_deep_link_controller.dart';
import 'desktop_utility_window_models.dart';

const _subscribeMethod = 'mithka.utility.td.subscribe';
const _queryMethod = 'mithka.utility.td.query';
const _sendMethod = 'mithka.utility.td.send';
const _updateMethod = 'mithka.utility.td.update';
const _settingsChangedMethod = 'mithka.utility.settings.changed';
const _presentationChangedMethod = 'mithka.utility.presentation.changed';
const _openUtilityMethod = 'mithka.utility.open';
const _chatOpenUtilityMethod = 'mithka.chat.utility.open';
const _openPrimaryChatMethod = 'mithka.utility.primary-chat.open';

const _blockedRequestTypes = <String>{
  'close',
  'destroy',
  'logOut',
  'setTdlibParameters',
};

bool get supportsDesktopUtilityWindows =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

final _mainBridge = _DesktopUtilityMainBridge();
Future<void> Function()? _childPresentationReload;
DesktopUtilityWindowArguments? _childArguments;

void attachDesktopUtilityMainProxy({
  Future<void> Function()? onSettingsChanged,
  int? Function(int accountSlot)? accountUserIdForSlot,
}) => _mainBridge.attach(
  onSettingsChanged: onSettingsChanged,
  accountUserIdForSlot: accountUserIdForSlot,
);

void detachDesktopUtilityMainProxy() => _mainBridge.detach();

void notifyDesktopUtilityAccountIdentityChanged() =>
    _mainBridge.closeStaleAccountWindows();

void attachDesktopUtilityChildPresentationReload(
  Future<void> Function() callback,
) => _childPresentationReload = callback;

void detachDesktopUtilityChildPresentationReload() =>
    _childPresentationReload = null;

Map<String, Object?>? desktopUtilityChildWindowIdentity() =>
    _childArguments?.toIpcJson();

int? registeredDesktopUtilityWindowAccountSlot(int windowId, Object? source) =>
    _mainBridge.registeredAccountSlot(windowId, source);

({int accountSlot, int? accountUserId})?
registeredDesktopUtilityWindowAccountIdentity(int windowId, Object? source) =>
    _mainBridge.registeredAccountIdentity(windowId, source);

Future<void> notifyDesktopUtilityPresentationChanged() async {
  if (!supportsDesktopUtilityWindows || MultiWindowManager.current.id > 0) {
    return;
  }
  _mainBridge.schedulePresentationChanged();
}

Future<bool> openDesktopUtilityWindow(
  DesktopUtilityWindowArguments arguments,
) async {
  if (!supportsDesktopUtilityWindows) return false;
  if (MultiWindowManager.current.id <= 0) return _mainBridge.open(arguments);

  final sourceUtility = _childArguments;
  if (sourceUtility == null &&
      (!arguments.kind.isComposerPicker || arguments.chatId == null)) {
    return false;
  }
  try {
    final response = await MultiWindowManager.current
        .invokeMethodToWindow(
          0,
          sourceUtility == null ? _chatOpenUtilityMethod : _openUtilityMethod,
          {
            ...?sourceUtility?.toIpcJson(),
            if (sourceUtility == null) ...{
              'accountSlot': arguments.accountSlot,
              'chatId': arguments.chatId,
            },
            'utility': arguments.encode(),
          },
        )
        .timeout(const Duration(seconds: 10));
    return response is Map && response['ok'] == true;
  } on Object {
    return false;
  }
}

Future<bool> openChatInPrimaryWindowFromDesktopUtility(
  ChatDeepLinkRequest request,
) async {
  if (!supportsDesktopUtilityWindows) return false;
  // Only a registered child hands a conversation over, and `current` throws
  // until the window manager is initialized — so the child check has to come
  // first or the primary window's own callers blow up here.
  final source = _childArguments;
  if (source == null) return false;
  try {
    if (MultiWindowManager.current.id <= 0) return false;
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

Future<void> configureDesktopUtilityChildProxy(
  DesktopUtilityWindowArguments arguments,
) async {
  _childArguments = arguments;
  final proxy = _DesktopUtilityChildProxy(arguments);
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

Future<void> closeCurrentDesktopUtilityWindow() async {
  if (!supportsDesktopUtilityWindows || MultiWindowManager.current.id <= 0) {
    return;
  }
  try {
    await MultiWindowManager.current.close();
  } on Object {
    // Closing an already-destroyed native child is a harmless no-op.
  }
}

Future<void> notifyDesktopUtilitySettingsChanged(
  DesktopUtilityWindowArguments arguments,
) async {
  if (!supportsDesktopUtilityWindows ||
      MultiWindowManager.current.id <= 0 ||
      arguments.kind != DesktopUtilityWindowKind.settings) {
    return;
  }
  try {
    await MultiWindowManager.current
        .invokeMethodToWindow(0, _settingsChangedMethod, arguments.toIpcJson())
        .timeout(const Duration(seconds: 5));
  } on Object {
    // The primary window may already be closing. Preference writes remain
    // durable and will be loaded on the next primary launch.
  }
}

WindowOptions desktopUtilityWindowOptions(
  DesktopUtilityWindowArguments arguments,
) {
  final (size, minimumSize) = switch (arguments.kind) {
    DesktopUtilityWindowKind.calls => (
      const Size(880, 700),
      const Size(640, 480),
    ),
    DesktopUtilityWindowKind.savedMessages => (
      const Size(1080, 760),
      const Size(720, 520),
    ),
    DesktopUtilityWindowKind.files || DesktopUtilityWindowKind.videos => (
      const Size(1040, 760),
      const Size(720, 520),
    ),
    DesktopUtilityWindowKind.search => (
      const Size(900, 720),
      const Size(680, 520),
    ),
    DesktopUtilityWindowKind.settings => (
      const Size(1080, 760),
      const Size(760, 560),
    ),
    // Single-column forms; they do not need the settings window's width.
    DesktopUtilityWindowKind.editProfile ||
    DesktopUtilityWindowKind.businessProfile => (
      const Size(620, 760),
      const Size(480, 560),
    ),
    DesktopUtilityWindowKind.audioPicker => (
      const Size(640, 720),
      const Size(480, 520),
    ),
    DesktopUtilityWindowKind.locationPicker => (
      const Size(840, 720),
      const Size(600, 520),
    ),
    DesktopUtilityWindowKind.contactPicker => (
      const Size(540, 700),
      const Size(420, 500),
    ),
    DesktopUtilityWindowKind.pollComposer ||
    DesktopUtilityWindowKind.checklistComposer => (
      const Size(680, 760),
      const Size(520, 560),
    ),
    DesktopUtilityWindowKind.scheduledMessages => (
      const Size(720, 720),
      const Size(520, 500),
    ),
    DesktopUtilityWindowKind.richTextComposer => (
      const Size(920, 780),
      const Size(680, 580),
    ),
    DesktopUtilityWindowKind.aiEditor => (
      const Size(680, 720),
      const Size(520, 540),
    ),
    DesktopUtilityWindowKind.chatInfo || DesktopUtilityWindowKind.userProfile =>
      (const Size(500, 700), const Size(420, 520)),
  };
  return WindowOptions(
    size: size,
    minimumSize: minimumSize,
    center: true,
    title: arguments.title,
    backgroundColor: arguments.dark
        ? const Color(0xFF111113)
        : const Color(0xFFF4F4F7),
    titleBarStyle: TitleBarStyle.normal,
    windowButtonVisibility: true,
  );
}

@visibleForTesting
bool desktopUtilityRequestTypeIsAllowed(Object? type) =>
    type is String && type.isNotEmpty && !_blockedRequestTypes.contains(type);

@visibleForTesting
bool desktopUtilityChildRequestIsAllowed({
  required DesktopUtilityWindowArguments requestingUtility,
  required DesktopUtilityWindowArguments requestedUtility,
}) =>
    requestingUtility.kind == DesktopUtilityWindowKind.savedMessages &&
    requestedUtility.kind.isComposerPicker &&
    requestedUtility.chatId == requestingUtility.chatId &&
    requestedUtility.accountSlot == requestingUtility.accountSlot &&
    (requestedUtility.accountUserId == null ||
        requestedUtility.accountUserId == requestingUtility.accountUserId);

@visibleForTesting
Map<String, dynamic>? desktopUtilitySanitizeRequest(Object? source) {
  final request = desktopUtilityNormalizeIpcMap(source);
  if (request == null) return null;
  if (!desktopUtilityRequestTypeIsAllowed(request['@type'])) return null;
  request
    ..remove('@client_id')
    ..remove('@extra');
  return request;
}

/// StandardMessageCodec materializes nested maps as
/// `Map<Object?, Object?>`. Normalize the complete object graph at the IPC
/// boundary before passing requests, results, or updates to TDLib consumers.
@visibleForTesting
Map<String, dynamic>? desktopUtilityNormalizeIpcMap(Object? source) {
  final normalized = _normalizeDesktopUtilityIpcValue(source);
  return normalized is Map<String, dynamic> ? normalized : null;
}

Object? _normalizeDesktopUtilityIpcValue(Object? source) {
  if (source is Map) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      if (entry.key is String) {
        result[entry.key as String] = _normalizeDesktopUtilityIpcValue(
          entry.value,
        );
      }
    }
    return result;
  }
  if (source is TypedData) return source;
  if (source is List) {
    return source
        .map<Object?>(_normalizeDesktopUtilityIpcValue)
        .toList(growable: false);
  }
  return source;
}

Map<String, dynamic> _sanitizeTdObject(Map<String, dynamic> source) =>
    <String, dynamic>{...source}
      ..remove('@client_id')
      ..remove('@extra');

class _DesktopUtilityMainBridge with WindowListener {
  final DesktopUtilityWindowRegistry _registry = DesktopUtilityWindowRegistry();
  final Map<int, DesktopUtilityWindowArguments> _argumentsByWindow = {};
  final Map<int, int> _clientIdByWindow = {};
  final Set<int> _subscribedWindows = {};
  final Map<int, List<Map<String, dynamic>>> _pendingUpdatesByWindow = {};
  StreamSubscription<Map<String, dynamic>>? _tdUpdates;
  Future<void> Function()? _onSettingsChanged;
  int? Function(int accountSlot)? _accountUserIdForSlot;
  Timer? _pendingUpdateFlush;
  Timer? _presentationChangedDebounce;
  bool _attached = false;

  void attach({
    Future<void> Function()? onSettingsChanged,
    int? Function(int accountSlot)? accountUserIdForSlot,
  }) {
    if (!_attached || onSettingsChanged != null) {
      _onSettingsChanged = onSettingsChanged;
    }
    if (!_attached || accountUserIdForSlot != null) {
      _accountUserIdForSlot = accountUserIdForSlot;
    }
    if (_attached || !supportsDesktopUtilityWindows) return;
    try {
      MultiWindowManager.current.addListener(this);
      MultiWindowManager.addGlobalListener(this);
      MultiWindowManager.current.activeWindows.addListener(
        _handleActiveWindowsChanged,
      );
      _tdUpdates = TdClient.shared.subscribeAll().listen(_handleTdUpdate);
      _attached = true;
    } on Object {
      // Portable builds can omit the native plugin. The primary process stays
      // the sole TDLib owner; never create a local child client as fallback.
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
    _pendingUpdateFlush?.cancel();
    _pendingUpdateFlush = null;
    _pendingUpdatesByWindow.clear();
    _presentationChangedDebounce?.cancel();
    _presentationChangedDebounce = null;
    _argumentsByWindow.clear();
    _clientIdByWindow.clear();
    _subscribedWindows.clear();
    _registry.clear();
    _onSettingsChanged = null;
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

  Future<bool> open(DesktopUtilityWindowArguments arguments) async {
    if (!supportsDesktopUtilityWindows) return false;
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

      createdWindow = await MultiWindowManager.createWindow([
        arguments.encode(),
      ]);
      if (createdWindow == null || createdWindow.id <= 0) return false;
      _registerWindow(createdWindow.id, arguments);
      await createdWindow.waitUntilReadyToShow(
        desktopUtilityWindowOptions(arguments),
      );
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
        debugPrint('Desktop utility window open failed: $error');
        return true;
      }());
      return false;
    }
  }

  void _registerWindow(int windowId, DesktopUtilityWindowArguments arguments) {
    for (final entry in _argumentsByWindow.entries.toList(growable: false)) {
      if (entry.key == windowId || entry.value.key == arguments.key) {
        _removeWindow(entry.key);
      }
    }
    _argumentsByWindow[windowId] = arguments;
    final clientId = TdClient.shared.clientId(arguments.accountSlot);
    if (clientId != null) _clientIdByWindow[windowId] = clientId;
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
    final registeredClientId = _clientIdByWindow[fromWindowId];
    if (registeredClientId == null) return null;

    switch (eventName) {
      case _settingsChangedMethod:
        if (registered.kind != DesktopUtilityWindowKind.settings) {
          return const {'ok': false};
        }
        final callback = _onSettingsChanged;
        if (callback == null) return const {'ok': false};
        await callback();
        return const {'ok': true};
      case _subscribeMethod:
        _subscribedWindows.add(fromWindowId);
        return {'ok': true, 'updates': _bootstrapUpdates(registeredClientId)};
      case _queryMethod:
        final request = arguments is Map
            ? desktopUtilitySanitizeRequest(arguments['request'])
            : null;
        return request == null
            ? const <String, dynamic>{
                '@type': 'error',
                'code': 400,
                'message': 'Unsupported desktop utility request',
              }
            : _query(registeredClientId, request);
      case _sendMethod:
        final request = arguments is Map
            ? desktopUtilitySanitizeRequest(arguments['request'])
            : null;
        if (request == null) return const {'ok': false};
        return _send(registeredClientId, request);
      case _openUtilityMethod:
        final encoded = arguments is Map ? arguments['utility'] : null;
        final requested = encoded is String
            ? DesktopUtilityWindowArguments.tryParse(encoded)
            : null;
        if (requested == null ||
            !desktopUtilityChildRequestIsAllowed(
              requestingUtility: registered,
              requestedUtility: requested,
            )) {
          return const {'ok': false};
        }
        return {'ok': await open(requested)};
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
          // The deep link remains queued even if the native focus request is
          // unavailable on a portable desktop build.
        }
        return const {'ok': true};
      default:
        return null;
    }
  }

  DesktopUtilityWindowArguments? _registeredRequest(
    int windowId,
    Object? source,
  ) {
    if (windowId <= 0) return null;
    final requestedKey = _keyFromIpc(source);
    final registered = _argumentsByWindow[windowId];
    if (requestedKey == null ||
        registered == null ||
        !desktopUtilityWindowRequestIsRegistered(
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

  bool _identityIsCurrent(DesktopUtilityWindowArguments arguments) {
    final resolver = _accountUserIdForSlot;
    if (resolver == null) return true;
    return desktopUtilityAccountIdentityIsCurrent(
      kind: arguments.kind,
      registeredAccountUserId: arguments.accountUserId,
      currentAccountUserId: resolver(arguments.accountSlot),
    );
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
      // A stale or already-closed native child is fully rejected locally.
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

  DesktopUtilityWindowKey? _keyFromIpc(Object? source) {
    if (source is! Map || source['accountSlot'] is! int) return null;
    final kind = DesktopUtilityWindowKind.tryParse(source['kind']);
    final accountSlot = source['accountSlot']! as int;
    if (kind == null || accountSlot < 0) return null;
    final sourceChatId = source['chatId'];
    if (kind.requiresChatId && (sourceChatId is! int || sourceChatId == 0)) {
      return null;
    }
    final sourceUserId = source['userId'];
    if (kind.requiresUserId && (sourceUserId is! int || sourceUserId <= 0)) {
      return null;
    }
    String? query;
    String? instanceId;
    if (kind == DesktopUtilityWindowKind.search) {
      final sourceQuery = source['query'];
      if (sourceQuery is! String) return null;
      query = DesktopUtilityWindowArguments.normalizeSearchQuery(sourceQuery);
      final sourceInstanceId = source['instanceId'];
      if (sourceInstanceId != null && sourceInstanceId is! String) return null;
      instanceId = DesktopUtilityWindowArguments.normalizeInstanceId(
        sourceInstanceId as String?,
      );
    }
    return DesktopUtilityWindowKey(
      accountSlot: accountSlot,
      kind: kind,
      chatId: kind.requiresChatId ? sourceChatId! as int : null,
      userId: kind.requiresUserId ? sourceUserId! as int : null,
      query: query,
      instanceId: instanceId,
    );
  }

  List<Map<String, dynamic>> _bootstrapUpdates(int clientId) {
    return [
      TdClient.shared.latestChatFoldersUpdateForClient(clientId),
      TdClient.shared.latestEmojiChatThemesUpdateForClient(clientId),
      TdClient.shared.latestTextCompositionStylesUpdateForClient(clientId),
      ...TdClient.shared.latestCommunityUpdatesForClient(clientId),
    ].whereType<Map<String, dynamic>>().map(_sanitizeTdObject).toList();
  }

  Future<Map<String, dynamic>> _query(
    int clientId,
    Map<String, dynamic> request,
  ) async {
    if (TdClient.shared.slotForClient(clientId) == null) {
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
        'message': 'Desktop utility request failed',
      };
    }
  }

  Map<String, Object?> _send(int clientId, Map<String, dynamic> request) {
    if (TdClient.shared.slotForClient(clientId) == null) {
      return const {'ok': false};
    }
    TdClient.shared.sendTo(request, clientId);
    return const {'ok': true};
  }

  void _handleTdUpdate(Map<String, dynamic> source) {
    // No popped-out window is the common case; do not pay the sanitize copy.
    if (_subscribedWindows.isEmpty) return;
    final clientId = source.integer('@client_id');
    if (clientId == null) return;
    if (TdClient.shared.slotForClient(clientId) == null) return;
    final update = _sanitizeTdObject(source);
    for (final entry in _argumentsByWindow.entries.toList(growable: false)) {
      if (_clientIdByWindow[entry.key] != clientId ||
          !_subscribedWindows.contains(entry.key)) {
        continue;
      }
      if (!_identityIsCurrent(entry.value)) {
        _rejectStaleWindow(entry.key);
        continue;
      }
      _enqueueUpdate(entry.key, update);
    }
  }

  /// Buffers one frame's worth of updates per window.
  ///
  /// Every push is a StandardMessageCodec encode of the whole nested update
  /// plus a platform-thread hop, and a parallel download burst emits hundreds
  /// of `updateFile` per second — one hop per frame instead of one per update.
  void _enqueueUpdate(int windowId, Map<String, dynamic> update) {
    final pending = _pendingUpdatesByWindow.putIfAbsent(
      windowId,
      () => <Map<String, dynamic>>[],
    );
    final fileId = _progressFileId(update);
    if (fileId != null &&
        pending.isNotEmpty &&
        _progressFileId(pending.last) == fileId) {
      // updateFile is pure progress state, so a run of them for one file can
      // collapse to the last without the child missing anything.
      pending[pending.length - 1] = update;
    } else {
      pending.add(update);
    }
    _pendingUpdateFlush ??= Timer(
      const Duration(milliseconds: 16),
      _flushPendingUpdates,
    );
  }

  static int? _progressFileId(Map<String, dynamic> update) {
    if (update['@type'] != 'updateFile') return null;
    final file = update['file'];
    return file is Map ? (file['id'] as num?)?.toInt() : null;
  }

  void _flushPendingUpdates() {
    _pendingUpdateFlush = null;
    if (_pendingUpdatesByWindow.isEmpty) return;
    final batches = _pendingUpdatesByWindow.entries.toList(growable: false);
    _pendingUpdatesByWindow.clear();
    for (final batch in batches) {
      unawaited(_pushUpdate(batch.key, batch.value));
    }
  }

  Future<void> _pushUpdate(
    int windowId,
    List<Map<String, dynamic>> updates,
  ) async {
    try {
      await MultiWindowManager.current.invokeMethodToWindow(
        windowId,
        _updateMethod,
        updates,
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
    _clientIdByWindow.remove(windowId);
    _subscribedWindows.remove(windowId);
    _pendingUpdatesByWindow.remove(windowId);
    _registry.removeWindow(windowId);
  }

  @override
  void onWindowClose([int? windowId]) {
    if (windowId != null && windowId > 0) _removeWindow(windowId);
  }
}

class _DesktopUtilityChildProxy with WindowListener {
  _DesktopUtilityChildProxy(this.arguments) {
    MultiWindowManager.current.addListener(this);
  }

  final DesktopUtilityWindowArguments arguments;
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
        // The child engine can start before its primary registry entry is
        // visible. Retry only this bounded local transport handshake.
      }
      if (response == null && attempt < 29) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (response == null) {
      throw StateError('Primary utility transport is unavailable');
    }
    final bootstrap = response['updates'];
    if (bootstrap is List) {
      for (final update in bootstrap) {
        final normalized = desktopUtilityNormalizeIpcMap(update);
        if (normalized != null) _updates.add(normalized);
      }
    }
  }

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    if (_closed) {
      return const {
        '@type': 'error',
        'code': 503,
        'message': 'Desktop utility transport is closed',
      };
    }
    final response = await MultiWindowManager.current
        .invokeMethodToWindow(0, _queryMethod, {
          ...arguments.toIpcJson(),
          'request': request,
        })
        .timeout(const Duration(seconds: 30));
    return desktopUtilityNormalizeIpcMap(response) ??
        const {
          '@type': 'error',
          'code': 500,
          'message': 'Invalid primary utility response',
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
      // The primary coalesces a frame's updates into one hop. A lone map is
      // still accepted: silently dropping one would stop the window updating
      // with nothing to show for it.
      final batch = eventArguments is List ? eventArguments : [eventArguments];
      for (final entry in batch) {
        final update = desktopUtilityNormalizeIpcMap(entry);
        if (!_closed && update != null) _updates.add(update);
      }
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
