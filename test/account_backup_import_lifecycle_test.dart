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

  test(
    'concurrent GramJS imports of one account share a slot and keep its data',
    () async {
      final harness = await _prepare(respond: _steadyResponder(777));

      // Two imports of the same account whose session string names no user
      // id: without serialization each resolves the other's fresh client as
      // "the existing account" and both returned slots lose their database.
      final slots = await Future.wait([
        harness.client.restoreGramJsSessionSlot(
          gramJsSessionFromTdSessionString(_syntheticSession(seed: 10)),
        ),
        harness.client.restoreGramJsSessionSlot(
          gramJsSessionFromTdSessionString(_syntheticSession(seed: 11)),
        ),
      ]);

      // Both callers are handed the same registered account slot.
      expect(slots.toSet(), hasLength(1));
      final kept = slots.first;
      expect(harness.slotDir(kept).existsSync(), isTrue);
      expect(
        File('${harness.slotDir(kept).path}/td.binlog').existsSync(),
        isTrue,
        reason: 'the returned slot lost its database',
      );
      expect(harness.client.activeSlot, kept);
      expect(harness.persistedSlots(), containsAll([0, kept]));
      // The duplicate's directory is gone and exactly one client was closed.
      // Client ids are assigned after asynchronous directory preparation, so
      // they must be observed, not derived from slot numbers: assert that the
      // closed client is the one whose parameters pointed at the discarded
      // slot's database directory — the wrong live database must never be the
      // deleted one.
      final discarded = kept == 1 ? 2 : 1;
      expect(harness.slotDir(discarded).existsSync(), isFalse);
      final closedClients = [
        for (final (id, request) in harness.bindings.sent)
          if (request['@type'] == 'close') id,
      ];
      expect(closedClients, hasLength(1));
      final parameters = harness.bindings.sentTo(
        closedClients.single,
        'setTdlibParameters',
      );
      expect(parameters, hasLength(1));
      expect(
        parameters.single['database_directory'],
        harness.slotDir(discarded).path,
        reason: 'the closed client must belong to the discarded slot',
      );
    },
  );
}
