import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/tdlib/gram_js_session.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_session_string.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synthetic credentials only: every auth key here is generated from a seed,
/// every user id is made up, and no TDLib binary is ever loaded.
Uint8List _syntheticAuthKey(int seed) {
  final key = Uint8List(TdSessionString.authKeyLength);
  for (var i = 0; i < key.length; i++) {
    key[i] = ((seed + i * 7) % 251) + 1;
  }
  return key;
}

String _syntheticSession({int userId = 777, int seed = 1}) =>
    TdSessionString.encode(
      TdSessionStringData(
        dcId: 2,
        apiId: 2496,
        testMode: false,
        authKey: _syntheticAuthKey(seed),
        userId: userId,
        isBot: false,
      ),
    );

Map<String, dynamic> _ready() => const {'@type': 'authorizationStateReady'};
Map<String, dynamic> _waitParameters() => const {
  '@type': 'authorizationStateWaitTdlibParameters',
};
Map<String, dynamic> _waitPhoneNumber() => const {
  '@type': 'authorizationStateWaitPhoneNumber',
};
Map<String, dynamic> _waitCode() => const {
  '@type': 'authorizationStateWaitCode',
};
Map<String, dynamic> _me(int userId) => {
  '@type': 'user',
  'id': userId,
  'first_name': 'Synthetic',
};

/// Stands in for tdjson. Records every request the restore path sends and
/// writes a placeholder binlog where the real importer would.
class _FakeBindings implements TdBindings {
  _FakeBindings(this._client);

  final TdClient _client;
  final List<(int, Map<String, dynamic>)> sent = [];
  final List<(String, String)> imported = [];
  int _nextClientId = 100;

  List<Map<String, dynamic>> sentTo(int clientId, String type) => [
    for (final (id, request) in sent)
      if (id == clientId && request['@type'] == type) request,
  ];

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    final decoded = jsonDecode(request) as Map<String, dynamic>;
    sent.add((clientId, decoded));
    if (decoded['@type'] == 'close') {
      // Answer the close handshake the way the receive isolate would, so slot
      // cleanup does not sit on the real 15-second timeout.
      _client.debugCompleteClientClosed(clientId);
    }
  }

  @override
  void importSessionString(String sessionString, String destinationPath) {
    imported.add((sessionString, destinationPath));
    File(
      destinationPath,
    ).writeAsBytesSync(Uint8List.fromList(const [1, 2, 3, 4]));
  }

  @override
  bool get supportsSessionStringBackup => true;

  @override
  bool get supportsTransferBoost => false;

  @override
  String? receive(double timeout) => throw UnimplementedError();

  @override
  Object? receiveJson(double timeout) => throw UnimplementedError();

  @override
  String? execute(String request) => throw UnimplementedError();

  @override
  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => throw UnimplementedError();

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

class _Harness {
  _Harness(this.client, this.bindings, this.supportDir, this.prefs);

  final TdClient client;
  final _FakeBindings bindings;
  final Directory supportDir;
  final SharedPreferences prefs;

  Directory slotDir(int slot) =>
      Directory('${supportDir.path}/tdlib/account-$slot');

  List<int> persistedSlots() => [
    for (final raw in prefs.getStringList('drachma.accountSlots') ?? const [])
      int.parse(raw),
  ];
}

typedef _Respond =
    FutureOr<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int clientId,
    );

/// One private [TdClient] per test, wired to fake bindings, mock preferences
/// and a scratch support directory, answering TDLib from [respond].
Future<_Harness> _prepare({
  required _Respond respond,
  bool isShuttingDown = false,
  Map<String, Object> initialPreferences = const {
    // Usable custom api credentials, so neither the GramJS converter nor
    // setTdlibParameters falls back to the placeholder Secrets values.
    'mithka.api_credentials.enabled': true,
    'mithka.api_credentials.api_id': '2496',
    'mithka.api_credentials.api_hash': '0123456789abcdef0123456789abcdef',
  },
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(initialPreferences);
  final prefs = await SharedPreferences.getInstance();
  final supportDir = Directory.systemTemp.createTempSync('mithka_import');
  addTearDown(() {
    if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
  });
  final client = TdClient.forTesting();
  final bindings = _FakeBindings(client);
  client.prepareForTesting(
    prefs: prefs,
    supportDir: supportDir.path,
    bindings: bindings,
    isShuttingDown: isShuttingDown,
    queryOverride: (request, clientId) async => respond(request, clientId),
  );
  return _Harness(client, bindings, supportDir, prefs);
}

/// Each client reports WaitTdlibParameters exactly once — the state that
/// makes the restore loop send its single setTdlibParameters — and stays
/// ready afterwards, reporting [userId] from getMe.
_Respond _steadyResponder(int userId) {
  final seen = <int>{};
  return (request, clientId) {
    switch (request['@type']) {
      case 'getAuthorizationState':
        return seen.add(clientId) ? _waitParameters() : _ready();
      case 'getMe':
        return _me(userId);
      default:
        return const {'@type': 'ok'};
    }
  };
}

void main() {
  test('restoring a packed session walks the real import lifecycle', () async {
    final harness = await _prepare(respond: _steadyResponder(777));
    // The default synthetic session names account 777.
    final session = _syntheticSession();

    final slot = await harness.client.restoreSessionSlot(session);

    expect(slot, 1);
    expect(harness.client.activeSlot, 1);
    expect(harness.slotDir(1).existsSync(), isTrue);
    expect(File('${harness.slotDir(1).path}/td.binlog').existsSync(), isTrue);

    // The importer received exactly this session string at this slot's binlog.
    expect(harness.bindings.imported, [
      (session, '${harness.slotDir(1).path}/td.binlog'),
    ]);

    // The bootstrap asks the version once and sends parameters exactly once:
    // TDLib reopens its database for every setTdlibParameters it accepts
    // before initialization.
    expect(harness.bindings.sentTo(100, 'getOption'), hasLength(1));
    final parameters = harness.bindings
        .sentTo(100, 'setTdlibParameters')
        .single;
    expect(parameters['database_directory'], harness.slotDir(1).path);
    expect(parameters['api_id'], 2496);

    // The slot is persisted and active.
    expect(harness.persistedSlots(), [0, 1]);
    expect(harness.prefs.getInt('drachma.activeSlot'), 1);
  });

  test(
    'an unauthorized restored session is refused and its slot discarded',
    () async {
      final harness = await _prepare(
        respond: (request, clientId) => switch (request['@type']) {
          'getAuthorizationState' => _waitPhoneNumber(),
          _ => const {'@type': 'ok'},
        },
      );

      await expectLater(
        harness.client.restoreSessionSlot(_syntheticSession()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('not authorized'),
          ),
        ),
      );

      // Cleanup closed the client and removed the database directory.
      expect(harness.bindings.sentTo(100, 'close'), hasLength(1));
      expect(harness.slotDir(1).existsSync(), isFalse);
      expect(harness.client.activeSlot, 0);
      expect(harness.persistedSlots(), isEmpty);
    },
  );

  test(
    'a restored session needing reauthorization is refused and cleaned up',
    () async {
      final harness = await _prepare(
        respond: (request, clientId) => switch (request['@type']) {
          'getAuthorizationState' => _waitCode(),
          _ => const {'@type': 'ok'},
        },
      );

      await expectLater(
        harness.client.restoreSessionSlot(_syntheticSession()),
        throwsA(
          isA<TdSessionRestoreException>().having(
            (error) => error.toString(),
            'toString',
            contains('requires reauthorization'),
          ),
        ),
      );

      expect(harness.bindings.sentTo(100, 'close'), hasLength(1));
      expect(harness.slotDir(1).existsSync(), isFalse);
      expect(harness.client.activeSlot, 0);
    },
  );

  test(
    'a slow account resolution keeps polling and sends parameters once',
    () async {
      // While TDLib resolves an unnamed account it queues getAuthorizationState,
      // so the wait loop treats a timeout as "still importing", re-sends the
      // parameters once, and keeps polling instead of failing.
      var timeoutsThrown = 0;
      final harness = await _prepare(
        respond: (request, clientId) {
          switch (request['@type']) {
            case 'getAuthorizationState':
              if (timeoutsThrown == 0) {
                timeoutsThrown += 1;
                throw TimeoutException('queued behind account resolution');
              }
              return _ready();
            case 'getMe':
              return _me(777);
            default:
              return const {'@type': 'ok'};
          }
        },
      );

      final slot = await harness.client.restoreSessionSlot(
        _syntheticSession(seed: 2),
      );

      expect(slot, 1);
      // The timeout path sent the parameters; the later Ready must not send
      // them a second time.
      expect(harness.bindings.sentTo(100, 'setTdlibParameters'), hasLength(1));
    },
  );

  test('a restored account that is not the expected one is refused', () async {
    final harness = await _prepare(respond: _steadyResponder(999));

    await expectLater(
      // The session names 777 while the client below reports 999.
      harness.client.restoreSessionSlot(_syntheticSession()),
      throwsA(
        isA<TdSessionRestoreException>().having(
          (error) => error.toString(),
          'toString',
          contains('user mismatch'),
        ),
      ),
    );

    expect(harness.bindings.sentTo(100, 'close'), hasLength(1));
    expect(harness.slotDir(1).existsSync(), isFalse);
    expect(harness.client.activeSlot, 0);
  });

  test(
    'a GramJS import resolves its account and reuses the existing slot',
    () async {
      final harness = await _prepare(respond: _steadyResponder(777));

      // First: a plain packed import claims slot 1.
      final first = await harness.client.restoreSessionSlot(
        _syntheticSession(),
      );
      expect(first, 1);

      // Then: the same account arrives as a GramJS string, which names no user
      // id. The import must resolve the account, find slot 1 already holding
      // it, discard the duplicate and hand back the existing slot.
      final gramJs = gramJsSessionFromTdSessionString(
        _syntheticSession(seed: 3),
      );
      final reused = await harness.client.restoreGramJsSessionSlot(gramJs);

      expect(reused, 1);
      expect(harness.client.activeSlot, 1);
      // The duplicate slot was closed and its database removed.
      expect(harness.bindings.sentTo(101, 'close'), hasLength(1));
      expect(harness.slotDir(2).existsSync(), isFalse);
      // The original slot is untouched.
      expect(harness.slotDir(1).existsSync(), isTrue);
      expect(harness.persistedSlots(), [0, 1]);
    },
  );

  test('concurrent imports land in separate slots and directories', () async {
    final harness = await _prepare(respond: _steadyResponder(777));

    final slots = await Future.wait([
      harness.client.restoreSessionSlot(_syntheticSession(seed: 4)),
      harness.client.restoreSessionSlot(_syntheticSession(seed: 5)),
    ]);

    // Two imports racing must not share one slot number or one database.
    expect(slots.toSet(), hasLength(2));
    expect(slots, containsAll([1, 2]));
    expect(harness.slotDir(1).existsSync(), isTrue);
    expect(harness.slotDir(2).existsSync(), isTrue);
    expect(harness.bindings.imported, hasLength(2));
    final destinations = harness.bindings.imported
        .map((entry) => entry.$2)
        .toSet();
    expect(destinations, hasLength(2));
    expect(harness.persistedSlots(), [0, 1, 2]);
  });

  test('an aborted import reports a revoked session and cleans up', () async {
    final harness = await _prepare(
      respond: (request, clientId) => switch (request['@type']) {
        'getAuthorizationState' => {
          '@type': 'error',
          'code': 500,
          'message': 'Request aborted',
        },
        _ => const {'@type': 'ok'},
      },
    );

    await expectLater(
      harness.client.restoreSessionSlot(_syntheticSession(seed: 6)),
      throwsA(
        isA<TdSessionRestoreException>().having(
          (error) => error.toString(),
          'toString',
          contains('invalid or has been revoked'),
        ),
      ),
    );

    expect(harness.slotDir(1).existsSync(), isFalse);
    expect(harness.client.activeSlot, 0);
  });

  test(
    'an import started while shutting down is refused and leaves no slot',
    () async {
      final harness = await _prepare(
        isShuttingDown: true,
        respond: _steadyResponder(777),
      );

      await expectLater(
        harness.client.restoreSessionSlot(_syntheticSession(seed: 7)),
        throwsA(isA<StateError>()),
      );

      // The claimed slot is given back and no database directory survives.
      expect(harness.slotDir(1).existsSync(), isFalse);
      expect(harness.client.activeSlot, 0);
      expect(harness.persistedSlots(), isEmpty);
    },
  );
}
