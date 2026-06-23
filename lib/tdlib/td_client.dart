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

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/secrets.dart';
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

class TdClient {
  TdClient._();
  static final TdClient shared = TdClient._();

  // Lazy: only opened when first used, so demo/simulator builds (no tdjson) can
  // touch the singleton (e.g. read activeSlot) without resolving symbols.
  late final TdBindings _bindings = TdBindings.open();

  bool _isRunning = false;

  // Request/response correlation, keyed by the "@extra" we attach.
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  int _extraCounter = 0;

  // Multicast of the ACTIVE account's updates.
  final StreamController<Map<String, dynamic>> _updates =
      StreamController.broadcast(sync: true);

  // Accounts
  final Map<int, int> _clientForSlot = {};
  final Map<int, int> _slotForClient = {};
  int _activeClientId = 0;
  int _activeSlot = 0;
  List<int> _slots = [0];

  late SharedPreferences _prefs;
  String _supportDir = '';

  static const _slotsKey = 'drachma.accountSlots';
  static const _activeKey = 'drachma.activeSlot';

  int get activeSlot => _activeSlot;
  List<int> get configuredSlots => List.unmodifiable(_slots);
  int? clientId(int slot) => _clientForSlot[slot];

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

    final stored =
        _prefs.getStringList(_slotsKey)?.map(int.parse).toList() ?? <int>[];
    var loaded = stored.isEmpty ? <int>[0] : stored;
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

    // The first request "activates" each client; TDLib then emits its
    // updateAuthorizationState(authorizationStateWaitTdlibParameters).
    for (final cid in _clientForSlot.values) {
      _bindings.send(
        cid,
        jsonEncode({'@type': 'getOption', 'name': 'version'}),
      );
    }

    // Spawn the dedicated receive isolate.
    final fromIsolate = ReceivePort();
    await Isolate.spawn(
      _receiveEntry,
      fromIsolate.sendPort,
      debugName: 'TDLibReceive',
    );
    fromIsolate.listen((message) {
      if (message is String) {
        final object = jsonDecode(message);
        if (object is Map<String, dynamic>) _route(object);
      }
    });
  }

  // MARK: - Account management

  /// Creates a fresh account slot (a new TDLib client + database directory)
  /// and returns its slot index. Does not change the active account.
  int addSlot() {
    final newSlot =
        (_slots.isEmpty ? -1 : _slots.reduce((a, b) => a > b ? a : b)) + 1;
    _slots.add(newSlot);
    final cid = _bindings.createClientId();
    _clientForSlot[newSlot] = cid;
    _slotForClient[cid] = newSlot;
    _persist();
    _bindings.send(cid, jsonEncode({'@type': 'getOption', 'name': 'version'}));
    return newSlot;
  }

  /// Routes future query/send/broadcast to the given account slot.
  void setActive(int slot) {
    final cid = _clientForSlot[slot];
    if (cid == null) return;
    _activeSlot = slot;
    _activeClientId = cid;
    _persist();
  }

  /// Discards an account slot: closes its TDLib client and forgets it, so it
  /// no longer appears in the switcher. Used to drop a freshly-added account
  /// whose login was aborted. Refuses to remove the active slot (switch away
  /// first) to avoid leaving the UI pointed at a dead client.
  void removeSlot(int slot) {
    if (slot == _activeSlot || !_slots.contains(slot)) return;
    final cid = _clientForSlot.remove(slot);
    if (cid != null) {
      _bindings.send(cid, jsonEncode({'@type': 'close'}));
      _slotForClient.remove(cid);
    }
    _slots.remove(slot);
    _persist();
  }

  void _persist() {
    _prefs.setStringList(_slotsKey, _slots.map((s) => s.toString()).toList());
    _prefs.setInt(_activeKey, _activeSlot);
  }

  /// The database directory for a slot. Slot 0 keeps the legacy path so an
  /// existing single-account login is preserved.
  String _databaseDirectory(int slot) {
    final base = '$_supportDir/tdlib';
    return slot == 0 ? base : '$base/account-$slot';
  }

  // MARK: - Routing (on the main isolate)

  void _route(Map<String, dynamic> object) {
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

    final clientId = object.integer('@client_id') ?? -1;

    // Bootstrap ANY client that asks for parameters, so every account
    // initializes and stays logged in (not just the active one).
    if (object.type == 'updateAuthorizationState' &&
        object.obj('authorization_state')?.type ==
            'authorizationStateWaitTdlibParameters') {
      _sendParameters(clientId);
    }

    // Only surface the active account's updates to the UI.
    if (clientId == _activeClientId) _updates.add(object);
  }

  void _sendParameters(int clientId) {
    final slot = _slotForClient[clientId];
    if (slot == null) return;

    final dbDir = _databaseDirectory(slot);
    final filesDir = '$dbDir/files';

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
        'use_secret_chats': false,
        'api_id': Secrets.apiId,
        'api_hash': Secrets.apiHash,
        'system_language_code': Platform.localeName.split('_').first,
        'device_model': Platform.isIOS ? 'iPhone' : 'Android',
        'system_version': Platform.operatingSystemVersion,
        'application_version': '1.0',
      }),
    );
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
}

// MARK: - Receive isolate

/// Runs on its own isolate: opens its own handle to the (process-global)
/// tdjson library and pumps every incoming event back to the main isolate.
void _receiveEntry(SendPort toMain) {
  final bindings = TdBindings.open();
  while (true) {
    final event = bindings.receive(1.0);
    if (event != null) toMain.send(event);
  }
}
