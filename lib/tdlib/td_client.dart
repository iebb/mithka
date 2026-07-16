//
//  td_client.dart
//
//  A thread-safe Dart wrapper around TDLib's `tdjson` JSON client, with
//  multi-account support — the Flutter port of the Swift `TDLibClient`.
//
//  TDLib lets one process host several independent clients (one per account),
//  each created via td_create_client_id() and bootstrapped with its own
//  database directory. A single background **isolate** pumps events for ALL
//  clients (each event carries "@client_id") back to the main isolate, which:
//   • resolves the matching `query` (responses tagged with our "@extra")
//   • bootstraps any client asking for parameters
//   • broadcasts the ACTIVE client's updates to UI subscribers
//
//  Accounts are identified by a stable integer "slot" persisted in
//  SharedPreferences; slot 0 uses the legacy "tdlib" directory so an existing
//  login keeps working. Client ids are per-process and recreated each launch.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/secrets.dart';
import '../settings/api_credentials_config.dart';
import '../settings/proxy_config.dart';
import 'avatar_animation_index.dart';
import 'json_helpers.dart';
import 'td_bindings.dart';

/// An error returned by TDLib (its "error" object).
class TdError implements Exception {
  TdError(Map<String, dynamic> object)
    : code = object.integer('code') ?? 0,
      message = object.str('message') ?? 'Unknown TDLib error';

  final int code;
  final String message;

  @override
  String toString() => 'TDLib error $code: $message';
}

class TdSessionRestoreException implements Exception {
  const TdSessionRestoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _TdSessionStringInfo {
  const _TdSessionStringInfo({
    required this.rawSize,
    required this.dcId,
    required this.apiId,
    required this.testMode,
    required this.userId,
    required this.isBot,
  });

  final int rawSize;
  final int dcId;
  final int apiId;
  final bool testMode;
  final int userId;
  final bool isBot;
}

@visibleForTesting
List<int> closeStaleDebugTdlibClients(
  Iterable<int> clientIds,
  void Function(int clientId, String request) send,
) {
  final staleClientIds = clientIds.where((id) => id > 0).toSet().toList();
  final closeRequest = jsonEncode({'@type': 'close'});
  for (final clientId in staleClientIds) {
    send(clientId, closeRequest);
  }
  return staleClientIds;
}

class TdClient {
  TdClient._();
  static final TdClient shared = TdClient._();

  // Lazy: only opened when first used, so demo/simulator builds (no tdjson) can
  // touch the singleton (e.g. read activeSlot) without resolving symbols.
  late final TdBindings _bindings = TdBindings.open();

  bool _isRunning = false;
  Timer? _debugReceiveTimer;

  // Receive isolate management — stored as fields so we can restart on resume.
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _receiveSub;
  bool _receiveIsolateDead = false;

  // Request/response correlation, keyed by the "@extra" we attach.
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final Map<int, Completer<void>> _clientClosedWaiters = {};
  int _extraCounter = 0;

  // Multicast of the ACTIVE account's updates.
  final StreamController<Map<String, dynamic>> _updates =
      StreamController.broadcast(sync: true);
  final StreamController<Map<String, dynamic>> _allUpdates =
      StreamController.broadcast(sync: true);
  final StreamController<int> _activeSlotChanges = StreamController.broadcast(
    sync: true,
  );
  final Map<int, Map<String, dynamic>> _latestChatFoldersByClient = {};
  final Map<int, Map<String, dynamic>> _latestEmojiChatThemesByClient = {};

  // Accounts
  final Map<int, int> _clientForSlot = {};
  final Map<int, int> _slotForClient = {};
  final Set<int> _proxyAppliedClients = {};
  int _activeClientId = 0;
  int _activeSlot = 0;
  List<int> _slots = [0];

  late SharedPreferences _prefs;
  String _supportDir = '';

  static const _slotsKey = 'drachma.accountSlots';
  static const _activeKey = 'drachma.activeSlot';
  static const _liveClientIdsKey = 'drachma.debugLiveClientIds';

  int get activeSlot => _activeSlot;
  int get activeClientId => _activeClientId;
  bool get hasActiveClient => _activeClientId != 0;
  List<int> get configuredSlots => List.unmodifiable(_slots);
  int? clientId(int slot) => _clientForSlot[slot];
  int? slotForClient(int clientId) => _slotForClient[clientId];
  Map<String, dynamic>? get latestChatFoldersUpdate =>
      _latestChatFoldersByClient[_activeClientId];
  Map<String, dynamic>? latestChatFoldersUpdateForClient(int clientId) =>
      _latestChatFoldersByClient[clientId];
  Map<String, dynamic>? get latestEmojiChatThemesUpdate =>
      _latestEmojiChatThemesByClient[_activeClientId];

  // MARK: - Lifecycle

  /// Creates a client for every known account and starts the receive isolate.
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    // Keep TDLib quiet in the console; raise while debugging if needed.
    _bindings.execute(
      jsonEncode({'@type': 'setLogVerbosityLevel', 'new_verbosity_level': 1}),
    );

    _prefs = await SharedPreferences.getInstance();
    _supportDir = (await getApplicationSupportDirectory()).path;
    if (kDebugMode) await _closeStaleDebugClients();

    final stored =
        _prefs.getStringList(_slotsKey)?.map(int.parse).toList() ?? <int>[];
    var loaded = stored.isEmpty ? <int>[0] : stored;
    loaded = await _quarantineMalformedSessionStringSlots(loaded);
    final storedActive = _prefs.getInt(_activeKey);
    final active = (storedActive != null && loaded.contains(storedActive))
        ? storedActive
        : loaded.first;

    _slots = loaded;
    _activeSlot = active;
    for (final slot in loaded) {
      final cid = _bindings.createClientId();
      _clientForSlot[slot] = cid;
      _slotForClient[cid] = slot;
    }
    _activeClientId = _clientForSlot[active] ?? 0;
    if (kDebugMode) unawaited(_persistDebugLiveClientIds());

    // The first request "activates" each client; TDLib then emits its
    // updateAuthorizationState(authorizationStateWaitTdlibParameters).
    for (final cid in _clientForSlot.values) {
      _bindings.send(
        cid,
        jsonEncode({'@type': 'getOption', 'name': 'version'}),
      );
    }

    if (kDebugMode) {
      _startDebugReceivePump();
    } else {
      _spawnReceiveIsolate();
    }
  }

  void _spawnReceiveIsolate() {
    _receivePort?.close();
    _receiveSub?.cancel();

    final port = ReceivePort();
    _receivePort = port;
    _receiveIsolateDead = false;

    Isolate.spawn(_receiveEntry, port.sendPort, debugName: 'TDLibReceive');
    _receiveSub = port.listen((message) {
      if (message is Map<String, dynamic>) {
        _route(message);
      } else if (message is String) {
        _routeRaw(message);
      }
    });
  }

  /// Restarts the receive isolate if it died (e.g. after app background→foreground
  /// on Android where the FFI state became stale). Safe to call when healthy.
  void restartReceiveIsolate() {
    if (!_isRunning) return;
    if (kDebugMode) return;
    if (!_receiveIsolateDead) return;

    debugPrint('🔑 [Mithka] restarting receive isolate after resume');
    _spawnReceiveIsolate();
  }

  // MARK: - Account management

  /// Creates a fresh account slot (a new TDLib client + database directory)
  /// and returns its slot index. Does not change the active account.
  int addSlot() {
    final newSlot = _nextSlot();
    final cid = _bindings.createClientId();
    _slots.add(newSlot);
    _clientForSlot[newSlot] = cid;
    _slotForClient[cid] = newSlot;
    _persist();
    if (kDebugMode) unawaited(_persistDebugLiveClientIds());
    _bindings.send(cid, jsonEncode({'@type': 'getOption', 'name': 'version'}));
    return newSlot;
  }

  Future<int> restoreSessionSlot(
    String sessionString, {
    bool reuseExisting = true,
  }) async {
    final trimmedSessionString = sessionString.trim();
    if (trimmedSessionString.isEmpty) {
      throw ArgumentError.value(sessionString, 'sessionString', 'is empty');
    }
    final info = _decodeSessionString(trimmedSessionString);
    if (reuseExisting) {
      final existingSlot = await _readySlotForUserId(info.userId);
      if (existingSlot != null) {
        setActive(existingSlot);
        return existingSlot;
      }
    }
    return _restoreImportedSessionSlot(trimmedSessionString, info.userId);
  }

  Future<void> acceptLoginQrLink(String link) async {
    await query({
      '@type': 'confirmQrCodeAuthentication',
      'link': link,
    }).timeout(const Duration(seconds: 20));
  }

  /// Cancels an in-progress QR login and recreates the active unauthenticated
  /// client on a clean database. TDLib persists QR authorization state, and it
  /// rejects setAuthenticationPhoneNumber until the client returns to
  /// authorizationStateWaitPhoneNumber.
  Future<void> resetActiveQrLogin() async {
    final slot = _activeSlot;
    final oldClientId = _activeClientId;
    if (oldClientId == 0) {
      throw StateError('TDLib client is not active yet');
    }

    final state = await queryTo({
      '@type': 'getAuthorizationState',
    }, oldClientId).timeout(const Duration(seconds: 5));
    if (state.type == 'authorizationStateWaitPhoneNumber') return;
    if (state.type != 'authorizationStateWaitOtherDeviceConfirmation') {
      throw StateError('Cannot cancel QR login from ${state.type}');
    }

    final closed = Completer<void>();
    _clientClosedWaiters[oldClientId] = closed;
    _activeClientId = 0;
    _bindings.send(oldClientId, jsonEncode({'@type': 'close'}));
    try {
      await closed.future.timeout(const Duration(seconds: 15));
    } finally {
      if (identical(_clientClosedWaiters[oldClientId], closed)) {
        _clientClosedWaiters.remove(oldClientId);
      }
    }

    if (_clientForSlot[slot] == oldClientId) {
      _clientForSlot.remove(slot);
    }
    _slotForClient.remove(oldClientId);
    _latestChatFoldersByClient.remove(oldClientId);
    _latestEmojiChatThemesByClient.remove(oldClientId);
    _proxyAppliedClients.remove(oldClientId);
    await deleteSlotData(slot);

    final newClientId = _bindings.createClientId();
    _clientForSlot[slot] = newClientId;
    _slotForClient[newClientId] = slot;
    _activeSlot = slot;
    _activeClientId = newClientId;
    _persist();
    if (kDebugMode) unawaited(_persistDebugLiveClientIds());

    final waitForPhoneNumber = _updates.stream
        .where((update) => update.type == 'updateAuthorizationState')
        .map((update) => update.obj('authorization_state'))
        .where((authorizationState) => authorizationState != null)
        .map((authorizationState) => authorizationState!)
        .firstWhere(
          (authorizationState) =>
              authorizationState.type == 'authorizationStateWaitPhoneNumber',
        )
        .timeout(const Duration(seconds: 20));
    _bindings.send(
      newClientId,
      jsonEncode({'@type': 'getOption', 'name': 'version'}),
    );
    await waitForPhoneNumber;
  }

  Future<TdFreshSessionResult> createFreshSessionFromSlot(
    int sourceSlot,
  ) async {
    final sourceClientId = clientId(sourceSlot);
    if (sourceClientId == null) {
      throw ArgumentError.value(sourceSlot, 'sourceSlot', 'is not configured');
    }
    final me = await queryTo({
      '@type': 'getMe',
    }, sourceClientId).timeout(const Duration(seconds: 5));
    final expectedUserId = me.int64('id');
    if (expectedUserId == null) {
      throw StateError('Source session did not return a user id');
    }
    return _createFreshSessionWithQrLogin(
      sourceClientId: sourceClientId,
      expectedUserId: expectedUserId,
    );
  }

  Future<int> _restoreImportedSessionSlot(
    String sessionString,
    int expectedUserId,
  ) async {
    final newSlot = _nextSlot();
    final dbDir = Directory(_databaseDirectory(newSlot));
    if (await dbDir.exists()) {
      await dbDir.delete(recursive: true);
    }
    await dbDir.create(recursive: true);
    final sessionFile = File('${dbDir.path}/td.binlog');
    _bindings.importSessionString(sessionString, sessionFile.path);

    final cid = _bindings.createClientId();
    if (!_slots.contains(newSlot)) _slots.add(newSlot);
    _clientForSlot[newSlot] = cid;
    _slotForClient[cid] = newSlot;
    if (kDebugMode) unawaited(_persistDebugLiveClientIds());
    _bindings.send(cid, jsonEncode({'@type': 'getOption', 'name': 'version'}));
    try {
      await _waitForRestoredSessionReady(newSlot, cid, expectedUserId);
      setActive(newSlot);
      _persist();
      return newSlot;
    } catch (error) {
      _closeAndForgetSlot(newSlot);
      await _deleteDirectoryIfPresent(dbDir);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _deleteDirectoryIfPresent(dbDir);
      if (kDebugMode) unawaited(_persistDebugLiveClientIds());
      if (_isRequestAborted(error)) {
        throw const TdSessionRestoreException(
          'Saved account session is invalid or has been revoked',
        );
      }
      rethrow;
    }
  }

  Future<TdFreshSessionResult> _createFreshSessionWithQrLogin({
    required int sourceClientId,
    required int expectedUserId,
  }) async {
    final newSlot = _nextSlot();
    final dbDir = Directory(_databaseDirectory(newSlot));
    if (await dbDir.exists()) {
      await dbDir.delete(recursive: true);
    }
    await dbDir.create(recursive: true);

    final cid = _bindings.createClientId();
    if (!_slots.contains(newSlot)) _slots.add(newSlot);
    _clientForSlot[newSlot] = cid;
    _slotForClient[cid] = newSlot;
    if (kDebugMode) unawaited(_persistDebugLiveClientIds());
    _bindings.send(cid, jsonEncode({'@type': 'getOption', 'name': 'version'}));
    try {
      await _waitForQrLoginReady(cid);
      await queryTo({
        '@type': 'requestQrCodeAuthentication',
        'other_user_ids': const <int>[],
      }, cid).timeout(const Duration(seconds: 10));
      final link = await _waitForQrLoginLink(cid);
      await queryTo({
        '@type': 'confirmQrCodeAuthentication',
        'link': link,
      }, sourceClientId).timeout(const Duration(seconds: 20));
      final ready = await _waitForFreshSessionReadyOrInteractive(
        newSlot,
        cid,
        expectedUserId,
      );
      setActive(newSlot);
      _persist();
      return TdFreshSessionResult(slot: newSlot, needsInteractiveLogin: !ready);
    } catch (error) {
      _closeAndForgetSlot(newSlot);
      await _deleteDirectoryIfPresent(dbDir);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _deleteDirectoryIfPresent(dbDir);
      if (kDebugMode) unawaited(_persistDebugLiveClientIds());
      if (_isRequestAborted(error)) {
        throw const TdSessionRestoreException(
          'Saved account session is invalid or has been revoked',
        );
      }
      rethrow;
    }
  }

  Future<bool> _waitForFreshSessionReadyOrInteractive(
    int slot,
    int clientId,
    int expectedUserId,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final state = await queryTo({
        '@type': 'getAuthorizationState',
      }, clientId).timeout(const Duration(seconds: 3));
      switch (state.type) {
        case 'authorizationStateWaitTdlibParameters':
          _sendParameters(clientId);
        case 'authorizationStateReady':
          await _verifyRestoredSessionStable(slot, clientId, expectedUserId);
          return true;
        case 'authorizationStateWaitCode':
        case 'authorizationStateWaitPassword':
        case 'authorizationStateWaitRegistration':
          return false;
        case 'authorizationStateWaitPhoneNumber':
          throw StateError(
            'Fresh account session is not authorized for slot $slot',
          );
        case 'authorizationStateWaitOtherDeviceConfirmation':
          // The target client can briefly keep reporting the QR confirmation
          // state after the source session has accepted the login token. Keep
          // waiting for the real interactive state, otherwise the login UI
          // exposes a QR code that has already been handled internally.
          break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException(
      'Timed out creating fresh account session for slot $slot',
    );
  }

  Future<void> _waitForQrLoginReady(int clientId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final state = await queryTo({
        '@type': 'getAuthorizationState',
      }, clientId).timeout(const Duration(seconds: 3));
      switch (state.type) {
        case 'authorizationStateWaitTdlibParameters':
          _sendParameters(clientId);
        case 'authorizationStateWaitPhoneNumber':
        case 'authorizationStateWaitOtherDeviceConfirmation':
          return;
        case 'authorizationStateReady':
          throw StateError('New account slot is already authorized');
        case 'authorizationStateWaitCode':
        case 'authorizationStateWaitPassword':
        case 'authorizationStateWaitRegistration':
          throw StateError(
            'New account slot is already in an interactive login state: ${state.type}',
          );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('Timed out preparing QR login client');
  }

  Future<String> _waitForQrLoginLink(int clientId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final state = await queryTo({
        '@type': 'getAuthorizationState',
      }, clientId).timeout(const Duration(seconds: 3));
      switch (state.type) {
        case 'authorizationStateWaitTdlibParameters':
          _sendParameters(clientId);
        case 'authorizationStateWaitOtherDeviceConfirmation':
          final link = state.str('link') ?? '';
          if (link.isNotEmpty) return link;
        case 'authorizationStateReady':
          throw StateError('QR login target became ready before token relay');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('Timed out waiting for QR login token');
  }

  Future<void> _waitForRestoredSessionReady(
    int slot,
    int clientId,
    int expectedUserId,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final state = await queryTo({
        '@type': 'getAuthorizationState',
      }, clientId).timeout(const Duration(seconds: 3));
      switch (state.type) {
        case 'authorizationStateWaitTdlibParameters':
          _sendParameters(clientId);
        case 'authorizationStateReady':
          await _verifyRestoredSessionStable(slot, clientId, expectedUserId);
          return;
        case 'authorizationStateWaitPhoneNumber':
          throw StateError(
            'Restored account session is not authorized for slot $slot',
          );
        case 'authorizationStateWaitCode':
        case 'authorizationStateWaitPassword':
        case 'authorizationStateWaitRegistration':
        case 'authorizationStateWaitOtherDeviceConfirmation':
          throw const TdSessionRestoreException(
            'Saved account session requires reauthorization',
          );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException(
      'Timed out restoring account session for slot $slot',
    );
  }

  Future<void> _verifyRestoredSessionStable(
    int slot,
    int clientId,
    int expectedUserId,
  ) async {
    final me = await queryTo({
      '@type': 'getMe',
    }, clientId).timeout(const Duration(seconds: 5));
    final restoredUserId = me.int64('id');
    if (restoredUserId != expectedUserId) {
      throw TdSessionRestoreException(
        'Restored account user mismatch for slot $slot: expected $expectedUserId, got $restoredUserId',
      );
    }

    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final state = await queryTo({
        '@type': 'getAuthorizationState',
      }, clientId).timeout(const Duration(seconds: 2));
      if (state.type == 'authorizationStateReady') continue;
      throw TdSessionRestoreException(
        'Restored account session closed during verification for slot $slot: ${state.type}',
      );
    }
  }

  Future<File> sessionFileForSlot(int slot) async {
    if (_supportDir.isEmpty) {
      _supportDir = (await getApplicationSupportDirectory()).path;
    }
    return File('${_databaseDirectory(slot)}/td.binlog');
  }

  Future<List<int>> _quarantineMalformedSessionStringSlots(
    List<int> slots,
  ) async {
    final kept = <int>[];
    var changed = false;
    for (final slot in slots) {
      final dbDir = Directory(_databaseDirectory(slot));
      final sessionFile = File('${dbDir.path}/td.binlog');
      if (slot != 0 && !await sessionFile.exists()) {
        changed = true;
        debugPrint('🔑 [Mithka] removing incomplete account slot $slot');
        await _deleteDirectoryIfPresent(dbDir);
        continue;
      }
      if (!await _isMalformedSessionStringBinlog(sessionFile)) {
        kept.add(slot);
        continue;
      }
      changed = true;
      debugPrint(
        '🔑 [Mithka] quarantining malformed restored session slot $slot',
      );
      if (slot == 0) {
        await sessionFile.rename(
          '${sessionFile.path}.malformed-session-string',
        );
      } else {
        await _deleteDirectoryIfPresent(dbDir);
      }
    }
    final normalized = kept.isEmpty ? <int>[0] : kept;
    if (changed) {
      await _prefs.setStringList(
        _slotsKey,
        normalized.map((slot) => slot.toString()).toList(),
      );
      final active = _prefs.getInt(_activeKey);
      if (active == null || !normalized.contains(active)) {
        await _prefs.setInt(_activeKey, normalized.first);
      }
    }
    return normalized;
  }

  Future<void> _deleteDirectoryIfPresent(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2) rethrow;
    }
  }

  bool _isRequestAborted(Object error) =>
      error is TdError &&
      error.code == 500 &&
      error.message.toLowerCase().contains('request aborted');

  Future<bool> _isMalformedSessionStringBinlog(File file) async {
    if (!await file.exists()) return false;
    final input = await file.open();
    try {
      final bytes = await input.read(64);
      if (bytes.length < 32) return false;
      final hasDefaultPmcMagic = bytes[14] == 0x28 && bytes[15] == 0x2a;
      final hasAuthKey =
          bytes[29] == 0x61 &&
          bytes[30] == 0x75 &&
          bytes[31] == 0x74 &&
          bytes[32] == 0x68;
      return hasDefaultPmcMagic && hasAuthKey;
    } finally {
      await input.close();
    }
  }

  Future<String> exportSessionStringForSlot(
    int slot, {
    required int userId,
  }) async {
    final source = await sessionFileForSlot(slot);
    if (!await source.exists()) {
      throw StateError('No TDLib session file found for account slot $slot');
    }

    if (!_bindings.supportsSessionStringBackup) {
      throw UnsupportedError('TDLib session string backup is unavailable');
    }

    final api = ApiCredentialsConfig.fromPrefs(_prefs);
    final useCustomApi = api.isUsable;
    final apiId = useCustomApi ? api.apiId : Secrets.apiId;
    final sessionString = _bindings.exportSessionString(
      source.path,
      apiId: apiId,
      testMode: false,
      userId: userId,
    );
    if (sessionString.trim().isEmpty) {
      throw StateError('TDLib session string backup is empty');
    }
    final info = _decodeSessionString(sessionString);
    if (info.apiId != apiId) {
      throw StateError(
        'TDLib session string API id mismatch: expected $apiId, got ${info.apiId}',
      );
    }
    if (info.userId != userId) {
      throw StateError(
        'TDLib session string user mismatch: expected $userId, got ${info.userId}',
      );
    }
    return sessionString;
  }

  void validateSessionString(String sessionString, {int? expectedUserId}) {
    final info = _decodeSessionString(sessionString);
    if (expectedUserId != null && info.userId != expectedUserId) {
      throw StateError(
        'TDLib session string user mismatch: expected $expectedUserId, got ${info.userId}',
      );
    }
  }

  Future<int?> _readySlotForUserId(int userId) async {
    for (final entry in _clientForSlot.entries) {
      try {
        final state = await queryTo({
          '@type': 'getAuthorizationState',
        }, entry.value).timeout(const Duration(seconds: 2));
        if (state.type != 'authorizationStateReady') continue;
        final me = await queryTo({
          '@type': 'getMe',
        }, entry.value).timeout(const Duration(seconds: 3));
        if (me.int64('id') == userId) return entry.key;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static _TdSessionStringInfo _decodeSessionString(String sessionString) {
    final normalized = sessionString.trim();
    if (normalized.isEmpty) {
      throw const FormatException('TDLib session string is empty');
    }

    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(normalized));
    } on FormatException catch (error) {
      throw FormatException(
        'TDLib session string is not valid base64url',
        error,
      );
    }

    const rawLength = 271;
    if (bytes.length != rawLength) {
      throw FormatException(
        'TDLib session string decoded size is ${bytes.length}, expected $rawLength',
      );
    }

    final dcId = bytes[0];
    final apiId = ByteData.sublistView(bytes, 1, 5).getUint32(0);
    final testMode = bytes[5] != 0;
    final authKey = bytes.sublist(6, 262);
    final userId = ByteData.sublistView(bytes, 262, 270).getUint64(0);
    final isBot = bytes[270] != 0;

    if (dcId == 0) {
      throw const FormatException('TDLib session string has invalid DC id');
    }
    if (apiId == 0) {
      throw const FormatException('TDLib session string has invalid API id');
    }
    if (userId == 0) {
      throw const FormatException('TDLib session string has invalid user id');
    }
    if (authKey.every((byte) => byte == 0)) {
      throw const FormatException('TDLib session string has an empty auth key');
    }

    return _TdSessionStringInfo(
      rawSize: bytes.length,
      dcId: dcId,
      apiId: apiId,
      testMode: testMode,
      userId: userId,
      isBot: isBot,
    );
  }

  /// Routes future query/send/broadcast to the given account slot.
  void setActive(int slot) {
    final cid = _clientForSlot[slot];
    if (cid == null) return;
    final changed = slot != _activeSlot;
    _activeSlot = slot;
    _activeClientId = cid;
    _persist();
    _applySavedProxyToClientOnce(cid);
    if (changed) _activeSlotChanges.add(slot);
  }

  /// Discards an account slot: closes its TDLib client and forgets it, so it
  /// no longer appears in the switcher. Used to drop a freshly-added account
  /// whose login was aborted. Refuses to remove the active slot (switch away
  /// first) to avoid leaving the UI pointed at a dead client.
  void removeSlot(int slot) {
    if (slot == _activeSlot || !_slots.contains(slot)) return;
    _closeAndForgetSlot(slot);
    _persist();
    if (kDebugMode) unawaited(_persistDebugLiveClientIds());
  }

  /// Deletes the local TDLib data for a forgotten slot without contacting
  /// Telegram. Slot 0 is the legacy base directory, so keep account-* child
  /// directories for other slots while removing slot-0 files.
  Future<void> deleteSlotData(int slot) async {
    final dbDir = Directory(_databaseDirectory(slot));
    if (!await dbDir.exists()) return;
    if (slot != 0) {
      await _deleteDirectoryIfPresent(dbDir);
      return;
    }

    await for (final entity in dbDir.list(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('account-')) continue;
      if (entity is Directory) {
        await _deleteDirectoryIfPresent(entity);
      } else {
        try {
          await entity.delete();
        } on FileSystemException catch (error) {
          if (error.osError?.errorCode != 2) rethrow;
        }
      }
    }
  }

  /// Drops the current active slot and replaces it with a clean login client.
  /// Used when the last account is cancelled/logged out: internally TDLib still
  /// needs one active client, but the account switcher can remain empty.
  int replaceActiveWithFreshLoginSlot() {
    final oldSlot = _activeSlot;
    final newSlot = addSlot();
    setActive(newSlot);
    if (_slots.contains(oldSlot)) {
      _closeAndForgetSlot(oldSlot);
      _persist();
      if (kDebugMode) unawaited(_persistDebugLiveClientIds());
    }
    return newSlot;
  }

  void _closeAndForgetSlot(int slot) {
    _closeClientForSlot(slot);
    _slots.remove(slot);
  }

  void _closeClientForSlot(int slot) {
    final cid = _clientForSlot.remove(slot);
    if (cid != null) {
      _bindings.send(cid, jsonEncode({'@type': 'close'}));
      _slotForClient.remove(cid);
      _latestChatFoldersByClient.remove(cid);
      _latestEmojiChatThemesByClient.remove(cid);
      _proxyAppliedClients.remove(cid);
    }
  }

  void _persist() {
    _prefs.setStringList(_slotsKey, _slots.map((s) => s.toString()).toList());
    _prefs.setInt(_activeKey, _activeSlot);
  }

  int _nextSlot() =>
      (_slots.isEmpty ? -1 : _slots.reduce((a, b) => a > b ? a : b)) + 1;

  /// The database directory for a slot. Slot 0 keeps the legacy path so an
  /// existing single-account login is preserved.
  String _databaseDirectory(int slot) {
    final base = '$_supportDir/tdlib';
    return slot == 0 ? base : '$base/account-$slot';
  }

  // MARK: - Routing (on the main isolate)

  void _route(Map<String, dynamic> object) {
    final clientId = object.integer('@client_id') ?? -1;
    final slot = _slotForClient[clientId] ?? _activeSlot;
    AvatarAnimationIndex.shared.observe(slot, object);

    // Responses to our requests carry the "@extra" we attached (any client).
    final extra = object.str('@extra');
    if (extra != null) {
      final completer = _pending.remove(extra);
      if (completer != null) {
        if (object.type == 'error') {
          completer.completeError(TdError(object));
        } else {
          completer.complete(object);
        }
        return;
      }
    }

    if (object.type == 'updateAuthorizationState' &&
        object.obj('authorization_state')?.type == 'authorizationStateClosed') {
      final waiter = _clientClosedWaiters.remove(clientId);
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }
    // Bootstrap ANY client that asks for parameters, so every account
    // initializes and stays logged in (not just the active one).
    if (object.type == 'updateAuthorizationState' &&
        object.obj('authorization_state')?.type ==
            'authorizationStateWaitTdlibParameters') {
      _sendParameters(clientId);
    }

    if (object.type == 'updateChatFolders') {
      _latestChatFoldersByClient[clientId] = object;
    }
    if (object.type == 'updateEmojiChatThemes') {
      _latestEmojiChatThemesByClient[clientId] = object;
    }

    _allUpdates.add(object);
    // Most UI consumers only need the active account's updates.
    if (clientId == _activeClientId) _updates.add(object);

    // Internal: receive isolate reported a fatal error (e.g. td_receive threw
    // after Android background→foreground). Mark it dead so a later resume
    // restarts it.
    if (object.type == '_tdReceiveFatal') {
      _receiveIsolateDead = true;
      debugPrint(
        '🔑 [Mithka] receive isolate died: ${object['error'] ?? 'unknown'}',
      );
    }
  }

  void _routeRaw(String message) {
    final object = jsonDecode(message);
    if (object is Map<String, dynamic>) _route(object);
  }

  void _startDebugReceivePump() {
    _debugReceiveTimer?.cancel();
    _debugReceiveTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      for (var i = 0; i < 40; i++) {
        final event = _bindings.receive(0.0);
        if (event == null) break;
        _routeRaw(event);
      }
    });
  }

  Future<void> _closeStaleDebugClients() async {
    final ids = _prefs
        .getStringList(_liveClientIdsKey)
        ?.map(int.tryParse)
        .whereType<int>()
        .toList();
    if (ids == null || ids.isEmpty) return;
    final closedIds = closeStaleDebugTdlibClients(ids, _bindings.send);
    if (closedIds.isNotEmpty) {
      debugPrint(
        '🔑 [Mithka] closing stale TDLib clients after hot restart: '
        '${closedIds.join(', ')}',
      );
      // `close` is asynchronous inside TDLib. Give the native clients time to
      // release their database handles before creating replacements that use
      // the same account directories.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await _prefs.remove(_liveClientIdsKey);
  }

  Future<void> _persistDebugLiveClientIds() {
    return _prefs.setStringList(
      _liveClientIdsKey,
      _clientForSlot.values.map((id) => id.toString()).toList(),
    );
  }

  void _sendParameters(int clientId) {
    final slot = _slotForClient[clientId];
    if (slot == null) return;

    final dbDir = _databaseDirectory(slot);
    final filesDir = '$dbDir/files';
    final api = ApiCredentialsConfig.fromPrefs(_prefs);
    final useCustomApi = api.isUsable;

    _bindings.send(
      clientId,
      jsonEncode({
        '@type': 'setTdlibParameters',
        'use_test_dc': false,
        'database_directory': dbDir,
        'files_directory': filesDir,
        'use_file_database': true,
        'use_chat_info_database': true,
        'use_message_database': true,
        'use_secret_chats': true,
        'api_id': useCustomApi ? api.apiId : Secrets.apiId,
        'api_hash': useCustomApi ? api.apiHash.trim() : Secrets.apiHash,
        'system_language_code': _safeSystemLanguageCode(),
        'device_model': Platform.isIOS ? 'iPhone' : 'Android',
        'system_version': _safeSystemVersion(),
        'application_version': '1.0',
      }),
    );
    if (clientId == _activeClientId) {
      _applySavedProxyToClientOnce(clientId);
    }
  }

  /// Re-sends TDLib parameters for the active client. This is intentionally
  /// idempotent for development hot restart, where Dart state restarts while
  /// tdjson can still be waiting on the bootstrap request.
  void sendParametersForActiveClient() {
    final clientId = _activeClientId;
    if (clientId == 0) return;
    _sendParameters(clientId);
  }

  Future<void> applySavedProxyToActive() async {
    final clientId = _activeClientId;
    if (clientId == 0) return;
    _proxyAppliedClients.add(clientId);
    await _applySavedProxyToClient(clientId);
  }

  Future<void> applyProxyConfig(ProxyConfig config) async {
    final clientId = _activeClientId;
    if (clientId == 0) {
      throw StateError('TDLib client is not active yet');
    }
    _proxyAppliedClients.add(clientId);
    await _applyProxyConfigToClient(config, clientId);
  }

  void _applySavedProxyToClientOnce(int clientId) {
    if (!_proxyAppliedClients.add(clientId)) return;
    unawaited(_applySavedProxyToClient(clientId));
  }

  Future<void> _applySavedProxyToClient(int clientId) async {
    final config = await ProxyConfig.load();
    await _applyProxyConfigToClient(config, clientId);
  }

  Future<void> _applyProxyConfigToClient(
    ProxyConfig config,
    int clientId,
  ) async {
    if (!config.configured) return;
    if (!config.isUsable) {
      try {
        await queryTo({
          '@type': 'disableProxy',
        }, clientId).timeout(const Duration(seconds: 8));
        debugPrint('🌐 [Mithka] proxy disabled for client $clientId');
      } catch (error) {
        debugPrint('🌐 [Mithka] failed to disable proxy: $error');
      }
      return;
    }

    try {
      final proxies = await queryTo({
        '@type': 'getProxies',
      }, clientId).timeout(const Duration(seconds: 8));
      Map<String, dynamic>? existing;
      for (final proxy
          in proxies.objects('proxies') ?? const <Map<String, dynamic>>[]) {
        if (config.matchesTdProxy(proxy)) {
          existing = proxy;
          break;
        }
      }
      final added = existing == null
          ? await queryTo(
              config.addProxyRequest,
              clientId,
            ).timeout(const Duration(seconds: 8))
          : null;
      final id = existing?.integer('id') ?? added?.integer('id');
      if (id != null) {
        await queryTo({
          '@type': 'enableProxy',
          'proxy_id': id,
        }, clientId).timeout(const Duration(seconds: 8));
        unawaited(
          queryTo({'@type': 'pingProxy', 'proxy_id': id}, clientId)
              .then((result) {
                debugPrint('🌐 [Mithka] proxy ping result: $result');
              })
              .catchError((Object error) {
                debugPrint('🌐 [Mithka] proxy ping failed: $error');
              }),
        );
        debugPrint(
          '🌐 [Mithka] proxy enabled: ${config.label} '
          '${config.server}:${config.port} for client $clientId',
        );
        return;
      }
      throw StateError('TDLib did not return a proxy id');
    } catch (error) {
      debugPrint(
        '🌐 [Mithka] proxy apply failed: ${config.label} '
        '${config.server}:${config.port}: $error',
      );
      rethrow;
    }
  }

  // MARK: - Sending

  /// Fire-and-forget request to the active account.
  void send(Map<String, dynamic> request) {
    _bindings.send(_activeClientId, jsonEncode(request));
  }

  /// Sends a request to the active account and awaits its response.
  Future<Map<String, dynamic>> query(Map<String, dynamic> request) {
    return queryTo(request, _activeClientId);
  }

  /// Sends a request to a SPECIFIC client and awaits its response (used to read
  /// each account's identity for the switcher).
  Future<Map<String, dynamic>> queryTo(
    Map<String, dynamic> request,
    int clientId,
  ) {
    final extra = _nextExtra();
    final tagged = {...request, '@extra': extra};
    final completer = Completer<Map<String, dynamic>>();
    _pending[extra] = completer;
    _bindings.send(clientId, jsonEncode(tagged));
    return completer.future;
  }

  /// Synchronous, network-free request (e.g. log level). Returns parsed JSON.
  Map<String, dynamic>? execute(Map<String, dynamic> request) {
    final result = _bindings.execute(jsonEncode(request));
    if (result == null) return null;
    final decoded = jsonDecode(result);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  String _nextExtra() {
    _extraCounter += 1;
    return 'drachma_$_extraCounter';
  }

  // MARK: - Updates (multicast)

  /// A fresh stream of the ACTIVE account's TDLib updates.
  Stream<Map<String, dynamic>> subscribe() => _updates.stream;

  /// Updates from every configured account. Consumers must use @client_id to
  /// keep account-scoped identifiers separate.
  Stream<Map<String, dynamic>> subscribeAll() => _allUpdates.stream;

  Stream<int> subscribeActiveSlotChanges() => _activeSlotChanges.stream;

  /// Broadcasts a local state correction to the same subscribers as TDLib
  /// updates. Use this only after sending the corresponding TDLib request, so
  /// list and badge UI can converge immediately while waiting for TDLib's
  /// eventual aggregate updates.
  void emitLocalUpdate(Map<String, dynamic> update) => _updates.add(update);

  String _safeSystemLanguageCode() {
    try {
      final code = Platform.localeName.split('_').first.trim();
      return code.isEmpty ? 'en' : code;
    } catch (_) {
      return 'en';
    }
  }

  String _safeSystemVersion() {
    try {
      final version = Platform.operatingSystemVersion.trim();
      return version.isEmpty ? Platform.operatingSystem : version;
    } catch (_) {
      return Platform.operatingSystem;
    }
  }
}

class TdFreshSessionResult {
  const TdFreshSessionResult({
    required this.slot,
    required this.needsInteractiveLogin,
  });

  final int slot;
  final bool needsInteractiveLogin;
}

// MARK: - Receive isolate

/// Runs on its own isolate: opens its own handle to the (process-global)
/// tdjson library and pumps every incoming event back to the main isolate.
/// Events are decoded here so the main isolate never pays for JSON parsing
/// during TDLib bursts (login sync, file progress, …).
///
/// On Android, the OS may freeze the process when the app goes to background.
/// After thaw, the native FFI state can be stale and td_receive may throw or
/// crash. We catch the error, notify the main isolate, and exit gracefully —
/// the main isolate will restart us on the next foreground transition.
void _receiveEntry(SendPort toMain) {
  TdBindings bindings;
  try {
    bindings = TdBindings.open();
  } catch (e) {
    toMain.send({'@type': '_tdReceiveFatal', 'error': e.toString()});
    return;
  }

  while (true) {
    String? event;
    try {
      event = bindings.receive(1.0);
    } catch (e) {
      toMain.send({'@type': '_tdReceiveFatal', 'error': e.toString()});
      return;
    }
    if (event == null) continue;
    try {
      final decoded = jsonDecode(event);
      if (decoded is Map<String, dynamic>) toMain.send(decoded);
    } catch (_) {
      // Malformed event; let the main isolate decide (it logs via _routeRaw).
      toMain.send(event);
    }
  }
}
