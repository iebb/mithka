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

import '../app/diagnostic_breadcrumbs.dart';
import '../bot_api/bot_api_account.dart';
import '../bot_api/bot_api_client.dart';
import '../bot_api/bot_api_endpoint_config.dart';
import '../bot_api/bot_api_td_backend.dart';
import '../config/secrets.dart';
import '../settings/api_credentials_config.dart';
import '../settings/proxy_config.dart';
import '../settings/transfer_boost_config.dart';
import 'avatar_animation_index.dart';
import 'json_helpers.dart';
import 'td_bindings.dart';
import 'td_user_index.dart';

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

/// An in-flight [TdClient.queryTo], remembered with the client it went to so a
/// closing or dead client can fail exactly its own requests.
class _PendingRequest {
  _PendingRequest(this.clientId, this.completer);

  final int clientId;
  final Completer<Map<String, dynamic>> completer;
  Timer? timeoutTimer;

  void cancelTimeout() {
    timeoutTimer?.cancel();
    timeoutTimer = null;
  }
}

@visibleForTesting
bool tdResponseMatchesRequestClient({
  required int responseClientId,
  required int requestClientId,
}) => responseClientId == requestClientId;

class TdSessionRestoreException implements Exception {
  const TdSessionRestoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Transport used by a secondary desktop Flutter engine.
///
/// The primary engine remains the sole TDLib/database owner. Secondary chat
/// windows send ordinary TDLib JSON requests over bounded local IPC and receive
/// the same update objects that the primary engine broadcasts.
class TdClientProxyTransport {
  const TdClientProxyTransport({
    required this.accountSlot,
    required this.query,
    required this.send,
    required this.updates,
    this.accountUserId,
  });

  final int accountSlot;
  final int? accountUserId;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) query;
  final Future<void> Function(Map<String, dynamic>) send;
  final Stream<Map<String, dynamic>> updates;
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

@visibleForTesting
Map<String, dynamic> quickAckTdlibOptionRequest() => <String, dynamic>{
  '@type': 'setOption',
  'name': 'use_quick_ack',
  'value': <String, dynamic>{'@type': 'optionValueBoolean', 'value': true},
};

@visibleForTesting
final class TdAccountLeaseReleasePlan {
  const TdAccountLeaseReleasePlan({
    this.closeClient = false,
    this.deleteData = false,
  });

  final bool closeClient;
  final bool deleteData;
}

/// Pure reference-count bookkeeping for long-lived account users.
///
/// Switching the foreground account never closes another slot, but desktop
/// windows and in-flight file work can outlive an explicit account cleanup or
/// session replacement. A requested close/delete is therefore held until the
/// last owner releases its lease.
@visibleForTesting
final class TdAccountLeaseBook {
  final Map<int, int> _counts = {};
  final Set<int> _pendingCloses = {};
  final Set<int> _pendingDeletes = {};

  int countFor(int accountSlot) => _counts[accountSlot] ?? 0;

  void retain(int accountSlot) {
    _counts.update(accountSlot, (count) => count + 1, ifAbsent: () => 1);
  }

  bool requestClose(int accountSlot) {
    if (countFor(accountSlot) == 0) return true;
    _pendingCloses.add(accountSlot);
    return false;
  }

  bool requestDelete(int accountSlot) {
    if (countFor(accountSlot) == 0 && !_pendingCloses.contains(accountSlot)) {
      return true;
    }
    _pendingDeletes.add(accountSlot);
    return false;
  }

  TdAccountLeaseReleasePlan release(int accountSlot) {
    final count = countFor(accountSlot);
    if (count <= 0) return const TdAccountLeaseReleasePlan();
    if (count > 1) {
      _counts[accountSlot] = count - 1;
      return const TdAccountLeaseReleasePlan();
    }
    _counts.remove(accountSlot);
    return TdAccountLeaseReleasePlan(
      closeClient: _pendingCloses.remove(accountSlot),
      deleteData: _pendingDeletes.remove(accountSlot),
    );
  }
}

/// Pins one concrete TDLib client for a long-lived video/file owner.
///
/// Queries never consult the current foreground account. Releasing is
/// idempotent so native window close/failure races cannot underflow the lease.
final class TdAccountLease {
  TdAccountLease._(this.accountSlot, this.clientId, this._query, this._release);

  final int accountSlot;
  final int clientId;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) _query;
  final Future<void> Function() _release;
  bool _released = false;

  bool get isReleased => _released;

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) {
    if (_released) {
      throw StateError('TDLib account lease for slot $accountSlot is released');
    }
    return _query(request);
  }

  Future<void> release() {
    if (_released) return Future<void>.value();
    _released = true;
    return _release();
  }
}

class TdClient {
  TdClient._();
  static final TdClient shared = TdClient._();
  static const defaultQueryTimeout = Duration(seconds: 30);

  // Lazy: only opened when first used, so demo/simulator builds (no tdjson) can
  // touch the singleton (e.g. read activeSlot) without resolving symbols.
  late final TdBindings _bindings = TdBindings.open();
  TdClientProxyTransport? _proxyTransport;
  StreamSubscription<Map<String, dynamic>>? _proxyUpdateSub;

  bool _isRunning = false;
  bool _isShuttingDown = false;
  bool _shutdownComplete = false;
  Future<void>? _startOperation;
  Future<bool>? _shutdownOperation;
  Timer? _debugReceiveTimer;

  // Receive isolate management — stored as fields so we can restart on resume.
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _receiveSub;
  Isolate? _receiveIsolate;
  Future<void>? _receiveIsolateExited;
  final Set<Future<void>> _receiveIsolateExitFutures = {};
  int _receiveIsolateGeneration = 0;
  bool _receiveIsolateDead = false;

  // Request/response correlation, keyed by the "@extra" we attach.
  final Map<String, _PendingRequest> _pending = {};
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
  final Map<int, Map<String, dynamic>> _latestTextCompositionStylesByClient =
      {};
  final Map<int, Map<int, Map<String, dynamic>>> _latestCommunitiesByClient =
      {};

  // Accounts
  final Map<int, int> _clientForSlot = {};
  final Map<int, int> _slotForClient = {};
  final Map<int, BotApiAccount> _botApiAccountForSlot = {};
  final Map<int, BotApiTdBackend> _botApiBackendForClient = {};
  final TdAccountLeaseBook _accountLeases = TdAccountLeaseBook();
  final Map<int, Future<bool>> _closingSlots = {};
  final Map<int, int> _unconfirmedSlotForClient = {};
  final Set<int> _proxyAppliedClients = {};
  int _activeClientId = 0;
  int _activeSlot = 0;
  List<int> _slots = [0];

  late SharedPreferences _prefs;
  String _supportDir = '';
  Uri _botApiEndpoint = BotApiEndpointConfig.defaultEndpoint;

  static const _slotsKey = 'drachma.accountSlots';
  static const _activeKey = 'drachma.activeSlot';
  static const _liveClientIdsKey = 'drachma.debugLiveClientIds';

  int get activeSlot => _activeSlot;
  int get activeClientId => _activeClientId;
  bool get hasActiveClient => _activeClientId != 0;
  int? get proxyAccountUserId => _proxyTransport?.accountUserId;
  List<int> get configuredSlots => List.unmodifiable(_slots);
  int? clientId(int slot) => _clientForSlot[slot];
  int? slotForClient(int clientId) => _slotForClient[clientId];
  bool isBotApiSlot(int slot) => _botApiAccountForSlot.containsKey(slot);
  bool get activeIsBotApi => isBotApiSlot(_activeSlot);

  /// Returns whether the active account is backed by the Bot API.
  ///
  /// Detached desktop windows proxy requests to the primary engine and don't
  /// own its account registry, so they ask the compatible backend directly.
  Future<bool> activeAccountUsesBotApi() async {
    if (activeIsBotApi) return true;
    if (_proxyTransport == null) return false;
    try {
      final info = await query({'@type': 'getBotApiAccountInfo'});
      return info.type == 'botApiAccountInfo';
    } on TdError {
      return false;
    }
  }

  /// Reads the one Bot API server root shared by every bot account.
  Future<Uri> configuredBotApiEndpoint() async {
    if (_proxyTransport == null) {
      if (!_isRunning) await start();
      return _botApiEndpoint;
    }
    final result = await query({'@type': 'getBotApiEndpointConfiguration'});
    return normalizeBotApiEndpoint(result.str('endpoint') ?? '');
  }

  /// Validates and applies a Bot API server root to every bot account.
  Future<Uri> setBotApiEndpoint(String endpoint) async {
    final normalized = normalizeBotApiEndpoint(endpoint);
    if (_proxyTransport != null) {
      final result = await query({
        '@type': 'setBotApiEndpointConfiguration',
        'endpoint': normalized.toString(),
      });
      return normalizeBotApiEndpoint(result.str('endpoint') ?? '');
    }
    if (!_isRunning) await start();
    await _replaceGlobalBotApiEndpoint(normalized);
    return _botApiEndpoint;
  }

  BotApiAccount? botApiAccount(int slot) => _botApiAccountForSlot[slot];
  Uri? get activeBotApiEndpoint => botApiAccount(_activeSlot)?.endpoint;
  Uri get botApiEndpoint => _botApiEndpoint;

  /// Every client currently registered, for callers that need to ask each
  /// account something rather than only the active one.
  Iterable<int> get registeredClientIds => _slotForClient.keys;
  Map<String, dynamic>? get latestChatFoldersUpdate =>
      _latestChatFoldersByClient[_activeClientId];
  Map<String, dynamic>? latestChatFoldersUpdateForClient(int clientId) =>
      _latestChatFoldersByClient[clientId];
  Map<String, dynamic>? get latestEmojiChatThemesUpdate =>
      _latestEmojiChatThemesByClient[_activeClientId];
  Map<String, dynamic>? latestEmojiChatThemesUpdateForClient(int clientId) =>
      _latestEmojiChatThemesByClient[clientId];
  Map<String, dynamic>? get latestTextCompositionStylesUpdate =>
      _latestTextCompositionStylesByClient[_activeClientId];
  Map<String, dynamic>? latestTextCompositionStylesUpdateForClient(
    int clientId,
  ) => _latestTextCompositionStylesByClient[clientId];
  Iterable<Map<String, dynamic>> get latestCommunityUpdates =>
      _latestCommunitiesByClient[_activeClientId]?.values ?? const [];
  Iterable<Map<String, dynamic>> latestCommunityUpdatesForClient(
    int clientId,
  ) => _latestCommunitiesByClient[clientId]?.values ?? const [];

  /// Configures this isolate as a read/write view onto the primary engine.
  /// Must be called before any native TDLib lifecycle is started.
  void configureProxy(TdClientProxyTransport transport) {
    if (_isRunning || _proxyTransport != null) {
      throw StateError(
        'TDLib proxy must be configured exactly once at startup',
      );
    }
    const proxyClientId = 1;
    _proxyTransport = transport;
    _activeSlot = transport.accountSlot;
    _activeClientId = proxyClientId;
    _slots = [transport.accountSlot];
    _clientForSlot
      ..clear()
      ..[transport.accountSlot] = proxyClientId;
    _slotForClient
      ..clear()
      ..[proxyClientId] = transport.accountSlot;
    _proxyUpdateSub = transport.updates.listen(_routeProxyUpdate);
  }

  /// Releases a secondary-engine transport when its native window exits.
  Future<void> closeProxy() async {
    await _proxyUpdateSub?.cancel();
    _proxyUpdateSub = null;
  }

  void _routeProxyUpdate(Map<String, dynamic> source) {
    final object = <String, dynamic>{...source, '@client_id': _activeClientId};
    AvatarAnimationIndex.shared.observe(_activeSlot, object);
    TdUserIndex.shared.observe(_activeSlot, object);
    if (object.type == 'updateChatFolders') {
      _latestChatFoldersByClient[_activeClientId] = object;
    }
    if (object.type == 'updateEmojiChatThemes') {
      _latestEmojiChatThemesByClient[_activeClientId] = object;
    }
    if (object.type == 'updateTextCompositionStyles') {
      _latestTextCompositionStylesByClient[_activeClientId] = object;
    }
    if (object.type == 'updateCommunity') {
      final community = object.obj('community');
      final communityId = community?.int64('id');
      if (community != null && communityId != null) {
        _latestCommunitiesByClient.putIfAbsent(
          _activeClientId,
          () => {},
        )[communityId] = object;
      }
    }
    _allUpdates.add(object);
    // Same fan-out as the primary engine, so a secondary window's typed
    // `updatesOf` listeners are fed too and not just `subscribe()`.
    _dispatchToActiveSubscribers(object);
  }

  // MARK: - Lifecycle

  /// Creates a client for every known account and starts the receive isolate.
  Future<void> start() {
    if (_proxyTransport != null) return Future<void>.value();
    if (_isShuttingDown || _shutdownComplete) return Future<void>.value();
    if (_isRunning) return _startOperation ?? Future<void>.value();
    _isRunning = true;

    late final Future<void> operation;
    operation = _startGuarded().whenComplete(() {
      if (identical(_startOperation, operation)) _startOperation = null;
    });
    _startOperation = operation;
    return operation;
  }

  Future<void> _startGuarded() async {
    try {
      await _start();
    } catch (_) {
      _isRunning = false;
      rethrow;
    }
  }

  Future<void> _start() async {
    // Keep TDLib quiet in the console; raise while debugging if needed.
    _bindings.execute(
      jsonEncode({'@type': 'setLogVerbosityLevel', 'new_verbosity_level': 1}),
    );

    // Prefs and the support directory are independent platform channels;
    // resolving them serially costs a full round trip on the launch path.
    final (prefs, supportDir) = await (
      SharedPreferences.getInstance(),
      getApplicationSupportDirectory(),
    ).wait;
    if (_isShuttingDown) {
      _isRunning = false;
      return;
    }
    _prefs = prefs;
    final transferBoost = TransferBoostConfig.fromPrefs(_prefs);
    _bindings.configureTransferBoost(
      downloadChunkSize: transferBoost.downloadEnabled
          ? transferBoost.downloadChunkSizeBytes
          : 0,
      downloadParallelism: transferBoost.downloadEnabled
          ? transferBoost.downloadParallelism
          : 0,
      uploadChunkSize: transferBoost.uploadEnabled
          ? transferBoost.uploadChunkSizeBytes
          : 0,
      uploadParallelism: transferBoost.uploadEnabled
          ? transferBoost.uploadParallelism
          : 0,
    );
    _supportDir = supportDir.path;
    if (kDebugMode) await _closeStaleDebugClients();

    final storedBotApiAccounts = BotApiAccountRegistry.load(_prefs);
    _botApiEndpoint = BotApiEndpointConfig.load(
      _prefs,
      legacyFallback: storedBotApiAccounts.firstOrNull?.endpoint,
    );
    final botApiAccounts = [
      for (final account in storedBotApiAccounts)
        account.copyWith(endpoint: _botApiEndpoint),
    ];
    if (_prefs.getString(BotApiEndpointConfig.preferenceKey) == null) {
      await BotApiEndpointConfig.save(_prefs, _botApiEndpoint.toString());
    }
    if (botApiAccounts.any(
      (account) =>
          storedBotApiAccounts
              .firstWhere((stored) => stored.slot == account.slot)
              .endpoint !=
          account.endpoint,
    )) {
      await BotApiAccountRegistry.replaceMetadata(_prefs, botApiAccounts);
    }
    final botApiMetadataSlots = botApiAccounts
        .map((account) => account.slot)
        .toSet();
    final botTokens = <int, String>{};
    for (final account in botApiAccounts) {
      final token = await BotApiAccountRegistry.readToken(account.slot);
      if (token != null) botTokens[account.slot] = token;
    }
    _botApiAccountForSlot
      ..clear()
      ..addEntries(
        botApiAccounts
            .where((account) => botTokens.containsKey(account.slot))
            .map((account) => MapEntry(account.slot, account)),
      );

    final stored =
        _prefs.getStringList(_slotsKey)?.map(int.parse).toList() ?? <int>[];
    var loaded = stored.isEmpty
        ? (botTokens.isEmpty ? <int>[0] : botTokens.keys.toList())
        : <int>[
            ...stored,
            for (final slot in botTokens.keys)
              if (!stored.contains(slot)) slot,
          ];
    final nativeSlots = loaded
        .where((slot) => !botApiMetadataSlots.contains(slot))
        .toList();
    final validNativeSlots = nativeSlots.isEmpty
        ? <int>[]
        : await _quarantineMalformedSessionStringSlots(nativeSlots);
    loaded = loaded
        .where(
          (slot) =>
              validNativeSlots.contains(slot) || botTokens.containsKey(slot),
        )
        .toList();
    if (loaded.isEmpty) {
      var fallbackSlot = 0;
      while (botApiMetadataSlots.contains(fallbackSlot)) {
        fallbackSlot += 1;
      }
      loaded = <int>[fallbackSlot];
    }
    final storedActive = _prefs.getInt(_activeKey);
    final active = (storedActive != null && loaded.contains(storedActive))
        ? storedActive
        : loaded.first;

    // Quit can be requested while secure storage or session repair is still
    // resolving. Never create a native client after shutdown has taken
    // ownership of the process lifecycle.
    if (_isShuttingDown) {
      _isRunning = false;
      return;
    }

    _slots = loaded;
    _activeSlot = active;
    for (final slot in loaded) {
      final account = _botApiAccountForSlot[slot];
      final token = botTokens[slot];
      final cid = account != null && token != null
          ? _syntheticBotApiClientId(slot)
          : _bindings.createClientId();
      _clientForSlot[slot] = cid;
      _slotForClient[cid] = slot;
      if (account != null && token != null) {
        _botApiBackendForClient[cid] = _createBotApiBackend(
          account,
          token,
          cid,
        );
      }
    }
    _activeClientId = _clientForSlot[active] ?? 0;
    if (kDebugMode) unawaited(_persistDebugLiveClientIds());

    // Start receiving before the first asynchronous backend startup. If Quit
    // lands in that window, shutdown must still receive every native
    // authorizationStateClosed acknowledgement before AppKit exits.
    if (kDebugMode) {
      _startDebugReceivePump();
    } else {
      _spawnReceiveIsolate();
    }

    // The first request "activates" each client; TDLib then emits its
    // updateAuthorizationState(authorizationStateWaitTdlibParameters).
    for (final cid in _clientForSlot.values.where((id) => id > 0)) {
      _bindings.send(
        cid,
        jsonEncode({'@type': 'getOption', 'name': 'version'}),
      );
    }

    for (final backend in _botApiBackendForClient.values) {
      if (_isShuttingDown) break;
      await backend.start();
    }
  }

  void _spawnReceiveIsolate() {
    final generation = ++_receiveIsolateGeneration;
    _receiveIsolate?.kill(priority: Isolate.immediate);
    _receiveIsolate = null;
    _receivePort?.close();
    unawaited(_receiveSub?.cancel());

    final port = ReceivePort();
    final exitPort = ReceivePort();
    _receivePort = port;
    _receiveIsolateDead = false;
    final exited = Completer<void>();
    late final Future<void> exitFuture;
    exitFuture = exited.future.whenComplete(() {
      _receiveIsolateExitFutures.remove(exitFuture);
      if (identical(_receiveIsolateExited, exitFuture)) {
        _receiveIsolateExited = null;
        _receiveIsolate = null;
      }
    });
    _receiveIsolateExitFutures.add(exitFuture);
    _receiveIsolateExited = exitFuture;
    late final StreamSubscription<dynamic> exitSubscription;
    exitSubscription = exitPort.listen((_) {
      if (!exited.isCompleted) exited.complete();
      unawaited(exitSubscription.cancel());
      exitPort.close();
    });

    unawaited(
      Isolate.spawn(
            _receiveEntry,
            port.sendPort,
            debugName: 'TDLibReceive',
            onExit: exitPort.sendPort,
          )
          .then<void>((isolate) {
            if (generation != _receiveIsolateGeneration ||
                (!_isRunning && !_isShuttingDown)) {
              isolate.kill(priority: Isolate.immediate);
              return;
            }
            _receiveIsolate = isolate;
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (generation == _receiveIsolateGeneration) {
              _receiveIsolateDead = true;
              _failPending('TDLib receive isolate failed to start');
              debugPrint('🔑 [Mithka] receive isolate failed to start: $error');
            }
            if (!exited.isCompleted) exited.complete();
            unawaited(exitSubscription.cancel());
            exitPort.close();
          }),
    );
    _receiveSub = port.listen((message) {
      // The isolate batches events into one list; the terminal fatal notice is
      // still sent on its own so it can't sit behind a partial batch.
      if (message is List) {
        for (final event in message) {
          if (event is Map<String, dynamic>) {
            _route(event);
          } else if (event is String) {
            _routeRaw(event);
          }
        }
      } else if (message is Map<String, dynamic>) {
        _route(message);
      } else if (message is String) {
        _routeRaw(message);
      }
    });
  }

  /// Restarts the receive isolate if it died (e.g. after app background→foreground
  /// on Android where the FFI state became stale). Safe to call when healthy.
  void restartReceiveIsolate() {
    if (!_isRunning || _isShuttingDown) return;
    for (final backend in _botApiBackendForClient.values) {
      unawaited(backend.resume());
    }
    if (kDebugMode) return;
    if (!_receiveIsolateDead) return;

    debugPrint('🔑 [Mithka] restarting receive isolate after resume');
    _spawnReceiveIsolate();
  }

  /// Closes every process-owned Telegram client before the desktop host exits.
  ///
  /// macOS unloads `libtdjson` during normal AppKit termination. Letting that
  /// happen while its receive isolate or native workers are still active can
  /// abort inside the library's static destructors. This latch keeps normal
  /// Quit cancelable until every native client confirms
  /// authorizationStateClosed and the receive isolate itself has exited.
  /// Persisted accounts, tokens, sessions, and local databases are untouched.
  Future<bool> shutdown() {
    if (_proxyTransport != null) {
      return closeProxy().then((_) => true);
    }
    if (_shutdownComplete) return Future<bool>.value(true);
    final existing = _shutdownOperation;
    if (existing != null) return existing;

    _isShuttingDown = true;
    late final Future<bool> operation;
    operation = _runShutdown().whenComplete(() {
      if (identical(_shutdownOperation, operation)) {
        _shutdownOperation = null;
      }
    });
    _shutdownOperation = operation;
    return operation;
  }

  Future<bool> _runShutdown() async {
    try {
      final closed = await _shutdownOwnedClients();
      if (closed) {
        _shutdownComplete = true;
      }
      return closed;
    } catch (_) {
      // Shutdown is a process-terminal latch. If Quit is cancelled because a
      // native client failed to close, do not resume ordinary traffic or let a
      // still-running startup operation create replacement clients. A later
      // Quit request can retry the remaining close operation safely.
      rethrow;
    }
  }

  Future<bool> _shutdownOwnedClients() async {
    final starting = _startOperation;
    if (starting != null) {
      try {
        await starting.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // Startup checks the shutdown latch before creating clients, and Bot
        // API startup checks it again after opening its store. Continue with
        // the clients that already exist instead of hanging AppKit forever.
      } catch (error) {
        debugPrint('🔑 [Mithka] startup ended during Quit: $error');
      }
    }

    _ensureReceivePumpForShutdown();
    final slots = <int>{
      ..._clientForSlot.keys,
      ..._closingSlots.keys,
      ..._unconfirmedSlotForClient.values,
    };
    final results = await Future.wait<bool>([
      for (final slot in slots) _closeSlotForApplicationShutdown(slot),
    ]);
    if (results.any((closed) => !closed)) {
      debugPrint(
        '🔑 [Mithka] Quit cancelled: a TDLib client did not close in time',
      );
      return false;
    }

    final receiverStopped = await _stopReceivePump();
    if (!receiverStopped) {
      debugPrint(
        '🔑 [Mithka] Quit cancelled: the TDLib receive isolate did not exit',
      );
      return false;
    }

    _failPending('Application is shutting down');
    for (final waiter in _clientClosedWaiters.values) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _clientClosedWaiters.clear();
    _clientForSlot.clear();
    _slotForClient.clear();
    _botApiBackendForClient.clear();
    _unconfirmedSlotForClient.clear();
    _activeClientId = 0;
    _isRunning = false;
    return true;
  }

  void _ensureReceivePumpForShutdown() {
    final hasNativeClient = _clientForSlot.values.any(
      (clientId) => !_botApiBackendForClient.containsKey(clientId),
    );
    if (!hasNativeClient && _unconfirmedSlotForClient.isEmpty) return;
    if (kDebugMode) {
      if (_debugReceiveTimer == null) _startDebugReceivePump();
      return;
    }
    if (_receiveIsolateDead || _receiveIsolateExited == null) {
      _spawnReceiveIsolate();
    }
  }

  Future<bool> _closeSlotForApplicationShutdown(int slot) async {
    try {
      final closing =
          _closingSlots[slot] ??
          _startClosingSlotResult(slot, preserveBotApiAccount: true);
      return await closing.timeout(const Duration(seconds: 16));
    } on TimeoutException {
      return false;
    } catch (error) {
      debugPrint('🔑 [Mithka] failed to close account slot $slot: $error');
      return false;
    }
  }

  Future<bool> _stopReceivePump() async {
    _debugReceiveTimer?.cancel();
    _debugReceiveTimer = null;

    final receiveSubscription = _receiveSub;
    _receiveSub = null;
    await receiveSubscription?.cancel();
    _receivePort?.close();
    _receivePort = null;

    final exits = Set<Future<void>>.of(_receiveIsolateExitFutures);
    final isolate = _receiveIsolate;
    ++_receiveIsolateGeneration;
    isolate?.kill(priority: Isolate.immediate);
    if (exits.isEmpty) {
      _receiveIsolate = null;
      return true;
    }
    try {
      await Future.wait(exits).timeout(const Duration(seconds: 3));
      _receiveIsolate = null;
      _receiveIsolateExited = null;
      return true;
    } on TimeoutException {
      return false;
    }
  }

  // MARK: - Account management

  void _ensureAcceptingNewClients() {
    if (_isShuttingDown || _shutdownComplete) {
      throw StateError('TDLib is shutting down');
    }
  }

  /// Creates a fresh account slot (a new TDLib client + database directory)
  /// and returns its slot index. Does not change the active account.
  int addSlot() {
    _ensureAcceptingNewClients();
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

  /// Validates and adds a Bot API account without creating a native TDLib
  /// database. The bot token is persisted only after getMe succeeds.
  Future<int> addBotApiAccount({
    required String token,
    String endpoint = 'https://api.telegram.org',
  }) async {
    _ensureAcceptingNewClients();
    if (_proxyTransport != null) {
      throw StateError('Bot accounts must be added from the main app window.');
    }
    if (!_isRunning) await start();
    _ensureAcceptingNewClients();
    final normalizedToken = normalizeBotToken(token);
    final normalizedEndpoint = normalizeBotApiEndpoint(endpoint);
    final validationClient = BotApiClient(
      token: normalizedToken,
      endpoint: normalizedEndpoint,
    );
    late final Map<String, dynamic> bot;
    try {
      final result = await validationClient.call('getMe');
      if (result is! Map) {
        throw const BotApiException(
          502,
          'The Bot API endpoint returned an invalid bot.',
        );
      }
      bot = Map<String, dynamic>.from(result);
      if (bot.boolean('is_bot') != true || (bot.int64('id') ?? 0) <= 0) {
        throw const BotApiException(
          401,
          'The token does not identify a Telegram bot.',
        );
      }
      final botId = bot.int64('id')!;
      if (_botApiAccountForSlot.values.any(
        (account) => account.botId == botId,
      )) {
        throw const BotApiException(409, 'This bot account is already added.');
      }
    } finally {
      validationClient.close();
    }

    _ensureAcceptingNewClients();
    await _replaceGlobalBotApiEndpoint(normalizedEndpoint);
    _ensureAcceptingNewClients();

    final previousSlot = _activeSlot;
    final slot = _nextSlot();
    final account = BotApiAccount(
      slot: slot,
      endpoint: normalizedEndpoint,
      bot: bot,
    );
    await BotApiAccountRegistry.save(_prefs, account, normalizedToken);
    _ensureAcceptingNewClients();
    final clientId = _syntheticBotApiClientId(slot);
    final backend = _createBotApiBackend(account, normalizedToken, clientId);
    _slots.add(slot);
    _clientForSlot[slot] = clientId;
    _slotForClient[clientId] = slot;
    _botApiAccountForSlot[slot] = account;
    _botApiBackendForClient[clientId] = backend;
    setActive(slot);
    try {
      await backend.start();
      return slot;
    } catch (_) {
      _slots.remove(slot);
      _clientForSlot.remove(slot);
      _slotForClient.remove(clientId);
      _botApiAccountForSlot.remove(slot);
      _botApiBackendForClient.remove(clientId);
      await backend.close();
      await BotApiAccountRegistry.remove(_prefs, slot);
      if (_clientForSlot.containsKey(previousSlot)) setActive(previousSlot);
      _persist();
      rethrow;
    }
  }

  BotApiTdBackend _createBotApiBackend(
    BotApiAccount account,
    String token,
    int clientId,
  ) {
    final directory = _botApiDataDirectory(account.slot);
    return BotApiTdBackend(
      account: account,
      token: token,
      databasePath: '$directory/history.sqlite3',
      mediaDirectory: '$directory/files',
      emit: (update) => _route({...update, '@client_id': clientId}),
    );
  }

  Future<void> _replaceGlobalBotApiEndpoint(Uri endpoint) async {
    _ensureAcceptingNewClients();
    if (endpoint == _botApiEndpoint) return;
    final replacementAccounts = <int, BotApiAccount>{};
    final replacementBackends = <int, BotApiTdBackend>{};

    // Validate every existing token against the proposed root before changing
    // any live account. A typo must not disconnect already-working bots.
    for (final entry in _botApiAccountForSlot.entries) {
      final token = await BotApiAccountRegistry.readToken(entry.key);
      final clientId = _clientForSlot[entry.key];
      if (token == null || clientId == null) continue;
      final validation = BotApiClient(token: token, endpoint: endpoint);
      try {
        final result = await validation.call('getMe');
        final returnedId = result is Map
            ? Map<String, dynamic>.from(result).int64('id')
            : null;
        if (returnedId != entry.value.botId) {
          throw const BotApiException(
            409,
            'The Bot API endpoint returned a different bot account.',
          );
        }
      } finally {
        validation.close();
      }
      _ensureAcceptingNewClients();
      final account = entry.value.copyWith(endpoint: endpoint);
      replacementAccounts[entry.key] = account;
      replacementBackends[clientId] = _createBotApiBackend(
        account,
        token,
        clientId,
      );
    }

    _ensureAcceptingNewClients();
    await BotApiEndpointConfig.save(_prefs, endpoint.toString());
    _ensureAcceptingNewClients();
    final metadata = [
      for (final account in _botApiAccountForSlot.values)
        replacementAccounts[account.slot] ??
            account.copyWith(endpoint: endpoint),
    ];
    await BotApiAccountRegistry.replaceMetadata(_prefs, metadata);
    _ensureAcceptingNewClients();

    for (final entry in replacementBackends.entries) {
      await _botApiBackendForClient[entry.key]?.close();
    }
    _ensureAcceptingNewClients();
    _botApiEndpoint = endpoint;
    _botApiAccountForSlot.addAll(replacementAccounts);
    _botApiBackendForClient.addAll(replacementBackends);
    for (final backend in replacementBackends.values) {
      _ensureAcceptingNewClients();
      await backend.start();
    }
  }

  int _syntheticBotApiClientId(int slot) => -1000000 - slot;

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
    _latestCommunitiesByClient.remove(oldClientId);
    _proxyAppliedClients.remove(oldClientId);
    await deleteSlotData(slot);

    _ensureAcceptingNewClients();
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
    _ensureAcceptingNewClients();
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
      await _closeAndForgetSlot(newSlot);
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

    _ensureAcceptingNewClients();
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
      await _closeAndForgetSlot(newSlot);
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

    _ensureAcceptingNewClients();
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

  /// Returns a locally authorized slot for [userId], if this device has one.
  ///
  /// Handoff uses the Telegram user id instead of a slot because slot numbers
  /// are installation-local and have no meaning on the receiving device.
  Future<int?> readySlotForUserId(int userId) => _readySlotForUserId(userId);

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
    if (cid == null || !_slots.contains(slot)) return;
    final changed = slot != _activeSlot;
    _activeSlot = slot;
    _activeClientId = cid;
    _persist();
    if (!_botApiBackendForClient.containsKey(cid)) {
      _applySavedProxyToClientOnce(cid);
    }
    if (changed) _activeSlotChanges.add(slot);
  }

  /// Discards an account slot: closes its TDLib client and forgets it, so it
  /// no longer appears in the switcher. Used to drop a freshly-added account
  /// whose login was aborted. Refuses to remove the active slot (switch away
  /// first) to avoid leaving the UI pointed at a dead client.
  void removeSlot(int slot) {
    if (slot == _activeSlot || !_slots.contains(slot)) return;
    unawaited(_closeAndForgetSlot(slot));
    _persist();
    if (kDebugMode) unawaited(_persistDebugLiveClientIds());
  }

  /// Deletes the local TDLib data for a forgotten slot without contacting
  /// Telegram. Slot 0 is the legacy base directory, so keep account-* child
  /// directories for other slots while removing slot-0 files.
  Future<void> deleteSlotData(int slot) async {
    if (!_accountLeases.requestDelete(slot)) return;
    final closing = _closingSlots[slot];
    if (closing != null) await closing;
    await _deleteSlotDataNow(slot);
  }

  Future<void> _deleteSlotDataNow(int slot) async {
    final botApiDirectory = Directory(_botApiDataDirectory(slot));
    if (await botApiDirectory.exists()) {
      await _deleteDirectoryIfPresent(botApiDirectory);
    }
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
      unawaited(_closeAndForgetSlot(oldSlot));
      _persist();
      if (kDebugMode) unawaited(_persistDebugLiveClientIds());
    }
    return newSlot;
  }

  Future<void> _closeAndForgetSlot(int slot) {
    _slots.remove(slot);
    if (_accountLeases.requestClose(slot)) {
      return _startClosingSlot(slot);
    }
    return Future<void>.value();
  }

  /// Fails every stranded request, optionally only the ones sent to [clientId].
  void _failPending(String reason, {int? clientId}) {
    if (_pending.isEmpty) return;
    final stranded = [
      for (final entry in _pending.entries)
        if (clientId == null || entry.value.clientId == clientId) entry.key,
    ];
    for (final extra in stranded) {
      final pending = _pending.remove(extra);
      if (pending == null || pending.completer.isCompleted) continue;
      pending.cancelTimeout();
      pending.completer.completeError(
        TdError(<String, dynamic>{'code': 500, 'message': reason}),
      );
    }
  }

  Future<void> _startClosingSlot(int slot) {
    return _startClosingSlotResult(slot).then<void>((_) {});
  }

  Future<bool> _startClosingSlotResult(
    int slot, {
    bool preserveBotApiAccount = false,
  }) {
    final existing = _closingSlots[slot];
    if (existing != null) return existing;
    late final Future<bool> closing;
    closing =
        _closeClientForSlot(
          slot,
          preserveBotApiAccount: preserveBotApiAccount,
        ).whenComplete(() {
          if (identical(_closingSlots[slot], closing)) {
            _closingSlots.remove(slot);
          }
        });
    _closingSlots[slot] = closing;
    return closing;
  }

  Future<bool> _closeClientForSlot(
    int slot, {
    bool preserveBotApiAccount = false,
  }) async {
    final cid =
        _clientForSlot.remove(slot) ??
        _unconfirmedSlotForClient.entries
            .where((entry) => entry.value == slot)
            .map((entry) => entry.key)
            .firstOrNull;
    if (cid == null) return true;
    final botApiBackend = _botApiBackendForClient.remove(cid);
    if (botApiBackend != null) {
      await botApiBackend.close();
      if (!preserveBotApiAccount) {
        await BotApiAccountRegistry.remove(_prefs, slot);
        _botApiAccountForSlot.remove(slot);
      }
      _slotForClient.remove(cid);
      TdUserIndex.shared.clearSlot(slot);
      _latestChatFoldersByClient.remove(cid);
      _latestEmojiChatThemesByClient.remove(cid);
      _latestTextCompositionStylesByClient.remove(cid);
      _latestCommunitiesByClient.remove(cid);
      _proxyAppliedClients.remove(cid);
      return true;
    }
    final existingWaiter = _clientClosedWaiters[cid];
    final closed = existingWaiter ?? Completer<void>();
    if (existingWaiter == null) {
      _clientClosedWaiters[cid] = closed;
      _bindings.send(cid, jsonEncode({'@type': 'close'}));
    }
    var didClose = true;
    try {
      await closed.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      didClose = false;
      _unconfirmedSlotForClient[cid] = slot;
    } finally {
      if (identical(_clientClosedWaiters[cid], closed)) {
        _clientClosedWaiters.remove(cid);
      }
      // A completer nothing will answer keeps its awaiting frame suspended
      // forever, retaining everything that frame captured — the State, the view
      // model, decoded bytes. This client is gone, so fail its requests.
      _failPending('TDLib client closed', clientId: cid);
      _slotForClient.remove(cid);
      TdUserIndex.shared.clearSlot(slot);
      _latestChatFoldersByClient.remove(cid);
      _latestEmojiChatThemesByClient.remove(cid);
      _latestTextCompositionStylesByClient.remove(cid);
      _latestCommunitiesByClient.remove(cid);
      _proxyAppliedClients.remove(cid);
      if (kDebugMode) unawaited(_persistDebugLiveClientIds());
    }
    if (didClose) _unconfirmedSlotForClient.remove(cid);
    return didClose;
  }

  Future<void> _releaseAccountLease(int slot) async {
    final plan = _accountLeases.release(slot);
    Future<void>? closing;
    if (plan.closeClient) closing = _startClosingSlot(slot);
    if (plan.deleteData && !_slots.contains(slot)) {
      closing ??= _closingSlots[slot]?.then<void>((_) {});
      if (closing != null) await closing;
      await _deleteSlotDataNow(slot);
    }
  }

  void _persist() {
    _prefs.setStringList(_slotsKey, _slots.map((s) => s.toString()).toList());
    _prefs.setInt(_activeKey, _activeSlot);
  }

  int _nextSlot() {
    final occupied = <int>{..._slots, ..._clientForSlot.keys};
    return (occupied.isEmpty ? -1 : occupied.reduce((a, b) => a > b ? a : b)) +
        1;
  }

  /// The database directory for a slot. Slot 0 keeps the legacy path so an
  /// existing single-account login is preserved.
  String _databaseDirectory(int slot) {
    final base = '$_supportDir/tdlib';
    return slot == 0 ? base : '$base/account-$slot';
  }

  String _botApiDataDirectory(int slot) => '$_supportDir/bot-api/account-$slot';

  // MARK: - Routing (on the main isolate)

  void _route(Map<String, dynamic> object) {
    final clientId = object.integer('@client_id') ?? -1;
    final slot =
        _slotForClient[clientId] ??
        _unconfirmedSlotForClient[clientId] ??
        _activeSlot;
    AvatarAnimationIndex.shared.observe(slot, object);
    TdUserIndex.shared.observe(slot, object);

    // Responses to our requests carry the "@extra" we attached (any client).
    final extra = object.str('@extra');
    if (extra != null) {
      final pending = _pending[extra];
      // Timed-out replies must not escape into the update stream. Likewise, a
      // response carrying another client's id must never complete this query.
      if (pending == null ||
          !tdResponseMatchesRequestClient(
            responseClientId: clientId,
            requestClientId: pending.clientId,
          )) {
        return;
      }
      _pending.remove(extra);
      pending.cancelTimeout();
      if (object.type == 'error') {
        pending.completer.completeError(TdError(object));
      } else {
        pending.completer.complete(object);
      }
      return;
    }

    if (object.type == 'updateAuthorizationState' &&
        object.obj('authorization_state')?.type == 'authorizationStateClosed') {
      TdUserIndex.shared.clearSlot(slot);
      _unconfirmedSlotForClient.remove(clientId);
      final waiter = _clientClosedWaiters.remove(clientId);
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }
    // Bootstrap ANY client that asks for parameters, so every account
    // initializes and stays logged in (not just the active one).
    if (!_isShuttingDown &&
        object.type == 'updateAuthorizationState' &&
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
    if (object.type == 'updateTextCompositionStyles') {
      _latestTextCompositionStylesByClient[clientId] = object;
    }
    if (object.type == 'updateCommunity') {
      final community = object.obj('community');
      final communityId = community?.int64('id');
      if (community != null && communityId != null) {
        _latestCommunitiesByClient.putIfAbsent(
          clientId,
          () => {},
        )[communityId] = object;
      }
    }

    _allUpdates.add(object);
    // Most UI consumers only need the active account's updates.
    if (clientId == _activeClientId) _dispatchToActiveSubscribers(object);

    // Internal: receive isolate reported a fatal error (e.g. td_receive threw
    // after Android background→foreground). Mark it dead so a later resume
    // restarts it.
    if (object.type == '_tdReceiveFatal') {
      _receiveIsolateDead = true;
      // No response can arrive until the isolate is restarted, and a restart
      // does not replay: everything in flight is stranded.
      _failPending('TDLib receive isolate died');
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
      _clientForSlot.values
          .where((id) => id > 0)
          .map((id) => id.toString())
          .toList(),
    );
  }

  void _sendParameters(int clientId) {
    if (_isShuttingDown || _shutdownComplete) return;
    if (_botApiBackendForClient.containsKey(clientId)) return;
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
        'device_model': api.resolvedDeviceModel(
          Platform.isIOS ? 'iPhone' : 'Android',
        ),
        'system_version': api.resolvedSystemVersion(_safeSystemVersion()),
        'application_version': api.resolvedApplicationVersion('1.0'),
      }),
    );
    // Ask Telegram's transport for an early server acknowledgement. TDLib
    // emits updateMessageSendAcknowledged only while this option is enabled;
    // without it the delivery indicator must wait for the slower final result.
    _bindings.send(clientId, jsonEncode(quickAckTdlibOptionRequest()));
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
    sendTo(request, _activeClientId);
  }

  /// Fire-and-forget request to a specific account client.
  void sendTo(Map<String, dynamic> request, int clientId) {
    if (_isShuttingDown || _shutdownComplete) return;
    if (!_slotForClient.containsKey(clientId)) return;
    final proxy = _proxyTransport;
    if (proxy != null) {
      unawaited(proxy.send(Map<String, dynamic>.from(request)));
      return;
    }
    final botApiBackend = _botApiBackendForClient[clientId];
    if (botApiBackend != null) {
      unawaited(botApiBackend.send(Map<String, dynamic>.from(request)));
      return;
    }
    _bindings.send(clientId, jsonEncode(request));
  }

  /// Sends a request to the active account and awaits its response.
  Future<Map<String, dynamic>> query(
    Map<String, dynamic> request, {
    Duration timeout = defaultQueryTimeout,
  }) {
    return queryTo(request, _activeClientId, timeout: timeout);
  }

  /// Sends a request to the client that owns [accountSlot].
  ///
  /// File ids and chat ids are account-scoped. Long-lived views must keep
  /// using the account that supplied those ids even if the user switches the
  /// app's active account while the request is in flight.
  Future<Map<String, dynamic>> queryForSlot(
    Map<String, dynamic> request,
    int accountSlot, {
    Duration timeout = defaultQueryTimeout,
  }) {
    final clientId = _clientForSlot[accountSlot];
    if (clientId == null) {
      throw StateError('No TDLib client for account slot $accountSlot');
    }
    return queryTo(request, clientId, timeout: timeout);
  }

  /// Retains the concrete client currently registered for [accountSlot].
  ///
  /// The returned query stays pinned to that client when another account is
  /// selected. Explicit slot removal and local-data deletion are deferred
  /// until every detached window/file owner releases its lease.
  TdAccountLease? retainAccountSlot(int accountSlot) {
    if (_isShuttingDown || _shutdownComplete) return null;
    final clientId = _clientForSlot[accountSlot];
    if (clientId == null || !_slots.contains(accountSlot)) return null;
    _accountLeases.retain(accountSlot);
    return TdAccountLease._(
      accountSlot,
      clientId,
      (request) => queryTo(request, clientId),
      () => _releaseAccountLease(accountSlot),
    );
  }

  /// Sends a request to a SPECIFIC client and awaits its response (used to read
  /// each account's identity for the switcher).
  Future<Map<String, dynamic>> queryTo(
    Map<String, dynamic> request,
    int clientId, {
    Duration timeout = defaultQueryTimeout,
  }) async {
    if (_isShuttingDown || _shutdownComplete) {
      throw StateError('TDLib is shutting down');
    }
    if (!_slotForClient.containsKey(clientId)) {
      throw StateError('TDLib client $clientId is not registered');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    final proxy = _proxyTransport;
    if (proxy != null) {
      final result = await proxy
          .query(Map<String, dynamic>.from(request))
          .timeout(timeout);
      if (result.type == 'error') throw TdError(result);
      return result;
    }
    final requestType = request.type ?? 'unknown';
    if (requestType == 'getBotApiEndpointConfiguration') {
      return {
        '@type': 'botApiEndpointConfiguration',
        'endpoint': _botApiEndpoint.toString(),
      };
    }
    if (requestType == 'setBotApiEndpointConfiguration') {
      final endpoint = normalizeBotApiEndpoint(request.str('endpoint') ?? '');
      await _replaceGlobalBotApiEndpoint(endpoint);
      return {
        '@type': 'botApiEndpointConfiguration',
        'endpoint': _botApiEndpoint.toString(),
      };
    }
    final stopwatch = Stopwatch()..start();
    final botApiBackend = _botApiBackendForClient[clientId];
    if (botApiBackend != null) {
      try {
        final result = await botApiBackend
            .query(Map<String, dynamic>.from(request))
            .timeout(timeout);
        if (result.type == 'error') throw TdError(result);
        stopwatch.stop();
        DiagnosticBreadcrumbs.tdlibRequestFinished(
          requestType: requestType,
          elapsed: stopwatch.elapsed,
          resultType: result.type,
        );
        return result;
      } catch (error, stackTrace) {
        stopwatch.stop();
        DiagnosticBreadcrumbs.tdlibRequestFinished(
          requestType: requestType,
          elapsed: stopwatch.elapsed,
          failed: true,
          errorCode: error is TdError ? error.code : null,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    final extra = _nextExtra();
    final tagged = {...request, '@extra': extra};
    final completer = Completer<Map<String, dynamic>>();
    final pending = _PendingRequest(clientId, completer);
    _pending[extra] = pending;
    pending.timeoutTimer = Timer(timeout, () {
      if (!identical(_pending[extra], pending)) return;
      _pending.remove(extra);
      pending.timeoutTimer = null;
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          TimeoutException('TDLib $requestType request timed out', timeout),
        );
      }
    });
    try {
      _bindings.send(clientId, jsonEncode(tagged));
      final result = await completer.future;
      stopwatch.stop();
      DiagnosticBreadcrumbs.tdlibRequestFinished(
        requestType: requestType,
        elapsed: stopwatch.elapsed,
        resultType: result.type,
      );
      return result;
    } catch (error, stackTrace) {
      if (identical(_pending[extra], pending)) _pending.remove(extra);
      pending.cancelTimeout();
      stopwatch.stop();
      DiagnosticBreadcrumbs.tdlibRequestFinished(
        requestType: requestType,
        elapsed: stopwatch.elapsed,
        failed: true,
        errorCode: error is TdError ? error.code : null,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Synchronous, network-free request (e.g. log level). Returns parsed JSON.
  Map<String, dynamic>? execute(Map<String, dynamic> request) {
    if (_isShuttingDown || _shutdownComplete) return null;
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

  /// Updates of exactly one @type from the active account. Prefer this over
  /// [subscribe] + a type filter: during TDLib bursts (login sync, file
  /// progress) every [subscribe] listener runs for every event, while typed
  /// listeners run only for their own type.
  Stream<Map<String, dynamic>> updatesOf(String type) =>
      (_typedUpdates[type] ??= StreamController<Map<String, dynamic>>.broadcast(
        sync: true,
      )).stream;

  /// Updates of any of [types] from the active account, in arrival order.
  ///
  /// The same win as [updatesOf] for a consumer that needs several types: a
  /// [subscribe] listener is woken for every event in the app — including the
  /// highest-rate ones, `updateFile` during a chunked download and the login
  /// sync burst — only to walk its own `switch` and return.
  ///
  /// Order is preserved because every controller on this path is synchronous,
  /// so an event is forwarded and delivered before the next one is dispatched.
  Stream<Map<String, dynamic>> updatesOfAny(Iterable<String> types) {
    final wanted = types.toSet();
    final subscriptions = <StreamSubscription<Map<String, dynamic>>>[];
    // Lives exactly as long as the stream it hands back; the source
    // subscriptions are dropped in onCancel, so nothing is retained after the
    // consumer lets go.
    // ignore: close_sinks
    late final StreamController<Map<String, dynamic>> merged;
    merged = StreamController<Map<String, dynamic>>.broadcast(
      sync: true,
      onListen: () {
        for (final type in wanted) {
          subscriptions.add(updatesOf(type).listen(merged.add));
        }
      },
      onCancel: () {
        for (final subscription in subscriptions) {
          unawaited(subscription.cancel());
        }
        subscriptions.clear();
      },
    );
    return merged.stream;
  }

  final Map<String, StreamController<Map<String, dynamic>>> _typedUpdates = {};

  void _dispatchToActiveSubscribers(Map<String, dynamic> update) {
    _updates.add(update);
    final type = update['@type'];
    if (type is! String) return;
    // Session-lifetime like _updates itself; never closed by design.
    // ignore: close_sinks
    final typed = _typedUpdates[type];
    if (typed != null && typed.hasListener) typed.add(update);
  }

  /// Updates from every configured account. Consumers must use @client_id to
  /// keep account-scoped identifiers separate.
  Stream<Map<String, dynamic>> subscribeAll() => _allUpdates.stream;

  Stream<int> subscribeActiveSlotChanges() => _activeSlotChanges.stream;

  /// Broadcasts a local state correction to the same subscribers as TDLib
  /// updates. Use this only after sending the corresponding TDLib request, so
  /// list and badge UI can converge immediately while waiting for TDLib's
  /// eventual aggregate updates.
  void emitLocalUpdate(Map<String, dynamic> update) =>
      _dispatchToActiveSubscribers(update);

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

  // One port message per event costs the main isolate one event-loop turn each,
  // and a login sync emits thousands back to back. Batching removes that fixed
  // overhead. The batch is deliberately SMALL: a large one only converts cost
  // spread over many turns into a single uninterruptible chunk, which drops a
  // frame instead of saving one.
  const batchLimit = 16;
  const batchWindowMicroseconds = 2000;
  var batch = <Object>[];
  final buffered = Stopwatch();

  void flush() {
    if (batch.isEmpty) return;
    toMain.send(batch);
    batch = <Object>[];
    buffered
      ..stop()
      ..reset();
  }

  while (true) {
    Object? event;
    try {
      // Only block when nothing is buffered — a partial batch must not wait a
      // second for the next event before the UI sees it.
      event = bindings.receiveJson(batch.isEmpty ? 1.0 : 0.0);
    } catch (e) {
      flush();
      toMain.send({'@type': '_tdReceiveFatal', 'error': e.toString()});
      return;
    }
    if (event == null) {
      flush();
      continue;
    }
    // Malformed events arrive as raw text; the main isolate decides via
    // _routeRaw, so the batch is mixed-type and order carries the meaning.
    if (event is Map<String, dynamic> || event is String) {
      batch.add(event);
    }
    if (batch.isEmpty) continue;
    if (!buffered.isRunning) buffered.start();
    if (batch.length >= batchLimit ||
        buffered.elapsedMicroseconds >= batchWindowMicroseconds) {
      flush();
    }
  }
}
