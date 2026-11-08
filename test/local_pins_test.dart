//
//  Device-only pins: with the unlimited-local-pins switch off the store, the
//  model's pin toggle and every prune/sync path must stay inert — no
//  preference write, no local band order, and the pin request the app sends
//  unchanged — and with it on, pinning past the server cap must work entirely
//  on the device: no `toggleChatIsPinned` request, the row on top, the entry
//  stored for this account only.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/chats/local_pin_store.dart';
import 'package:mithka/tdlib/json_helpers.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The account the fake transport's chats belong to.
const _accountUserId = 42;

/// The most recently pinned server pin has this order; the device-only pin has
/// to sort above it.
const _highestServerOrder = 500;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  late List<Map<String, dynamic>> requests;
  late _FakeBindings bindings;
  Object? pinFailure;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('mithka-local-pins');
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    // The model sends its toggle through the real client, so it needs a
    // registry the fake transport can answer (the recorded queryForTesting
    // transport only covers the model's own chat queries).
    bindings = _FakeBindings();
    TdClient.shared.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: bindings,
      queryOverride: (request, clientId) async {
        requests.add(Map<String, dynamic>.from(request));
        if (request['@type'] == 'toggleChatIsPinned' && pinFailure != null) {
          throw pinFailure!;
        }
        return {'@type': 'ok'};
      },
    );
    final slot = TdClient.shared.addSlot();
    final clientId = TdClient.shared.clientId(slot);
    TdClient.shared.debugSetActiveAccountForTesting(slot, clientId ?? 0);
    bindings.adopt(clientId ?? -1);
  });

  setUp(() async {
    pinFailure = null;
    requests = <Map<String, dynamic>>[];
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    // Every test starts from a store with nothing loaded and no account.
    final store = LocalPinStore.shared;
    store.initialize(prefs);
    await store.setUnlimitedEnabled(false);
    store.setActiveAccountUserId(null);
  });

  test('switch off: the store refuses a pin and writes nothing', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalPinStore();
    var notified = 0;
    store.addListener(() => notified++);

    store.initialize(prefs);
    store.setActiveAccountUserId(_accountUserId);
    expect(store.unlimitedEnabled, isFalse);

    // The switch is off: a pin is refused and leaves nothing behind.
    expect(notified, 0);
    expect(prefs.getKeys(), isEmpty);
    await store.pin(6, serverPinOrder: 600, pinnedAt: 1);

    expect(store.isLocallyPinned(6), isFalse);
    expect(store.entryFor(6), isNull);
    expect(store.pinnedChatIds, isEmpty);
    // A dormant store hands the live order straight back.
    expect(store.effectiveOrder(6, 600), 600);
    expect(prefs.getKeys(), isEmpty);
    expect(notified, 0);
  });

  test('entries are account-scoped', () async {
    final store = await _openStore();
    await store.pin(7, serverPinOrder: 100, pinnedAt: 1000);
    expect(store.isLocallyPinned(7), isTrue);

    store.setActiveAccountUserId(77);
    expect(store.isLocallyPinned(7), isFalse);
    expect(store.entryFor(7), isNull);

    store.setActiveAccountUserId(_accountUserId);
    expect(store.isLocallyPinned(7), isTrue);
    expect(store.entryFor(7)!.pinnedAt, 1000);
  });

  test('pinning past the server cap keeps the pin on the device', () async {
    final prefs = await _openStorePrefs();
    final store = LocalPinStore.shared;
    store.initialize(prefs);
    await store.setUnlimitedEnabled(true);
    store.setActiveAccountUserId(_accountUserId);

    final modelRequests = <Map<String, dynamic>>[];
    final model = ChatListViewModel(
      queryForTesting: (request) => _respond(modelRequests, request),
    );
    addTearDown(model.dispose);
    model.meId = _accountUserId;
    model.onAppear();
    model.loadMore();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final ids = model.chats.map((c) => c.id).toList();
    expect(ids, [1, 2, 3, 4, 5, _unpinnedChatId]);
    final target = model.chats.last;
    expect(target.id, _unpinnedChatId);
    expect(target.isPinned, isFalse);
    expect(target.order, _unpinnedChatId * 100);

    // The list's highest order, which a server pin would carry.
    expect(model.chats.first.order, _highestServerOrder);

    requests.clear();
    modelRequests.clear();
    model.togglePin(target);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The toggle went through the real client, which the fake transport
    // records: nothing may reach the server for a device-only pin.
    expect(
      requests.where((r) => r['@type'] == 'toggleChatIsPinned'),
      isEmpty,
      reason: 'a device-only pin must not reach the server',
    );
    expect(store.isLocallyPinned(_unpinnedChatId), isTrue);
    expect(store.entryFor(_unpinnedChatId)!.serverPinOrder, 600);
    expect(target.isPinned, isTrue);
    expect(target.order, 601);
    expect(model.chats.first.id, _unpinnedChatId);
    expect(model.notice, isNull);
    // Nothing was asked of TDLib for the device-only pin either.
    expect(modelRequests, isEmpty);

    // An update burst must not churn the band: the row keeps the order it
    // was given even after a newer last message lands.
    model.applyUpdateForTesting({
      '@type': 'updateChatLastMessage',
      'chat_id': _unpinnedChatId,
      'last_message': {
        '@type': 'message',
        'id': 6001,
        'chat_id': _unpinnedChatId,
        'date': 99999,
        'is_outgoing': false,
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'newest'},
        },
      },
      'positions': [
        {
          '@type': 'chatPosition',
          'list': {'@type': 'chatListMain'},
          'order': 600,
          'is_pinned': false,
        },
      ],
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(target.order, 601);
    expect(model.chats.first.id, _unpinnedChatId);

    // The same gesture again removes the device-only pin.
    requests.clear();
    model.togglePin(target);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(requests.where((r) => r['@type'] == 'toggleChatIsPinned'), isEmpty);
    expect(store.isLocallyPinned(_unpinnedChatId), isFalse);
    // The resort rebuilt the list, so re-read the row from it.
    final afterUnpin = model.chats.firstWhere((c) => c.id == _unpinnedChatId);
    expect(afterUnpin.isPinned, isFalse);
    // Releasing the device pin puts the row back on its own position —
    // the largest server order recorded for it — instead of leaving it on
    // the band order it carried while pinned.
    expect(afterUnpin.order, 600);
    expect(model.chats.map((c) => c.id).toList(), [
      1,
      2,
      3,
      4,
      5,
      _unpinnedChatId,
    ]);

    // Pin it again, then turn the switch off: every row a device pin was
    // holding has to be released, on the row's own position, even while
    // the stored entry stays dormant in the preference store.
    model.togglePin(model.chats.firstWhere((c) => c.id == _unpinnedChatId));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(store.isLocallyPinned(_unpinnedChatId), isTrue);

    await store.setUnlimitedEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(store.isLocallyPinned(_unpinnedChatId), isFalse);
    final released = model.chats.firstWhere((c) => c.id == _unpinnedChatId);
    expect(released.isPinned, isFalse);
    expect(released.order, 600);
    expect(model.chats.last.id, _unpinnedChatId);
    final dormantPrefs = await SharedPreferences.getInstance();
    expect(
      dormantPrefs.getKeys().where(
        (k) => k.startsWith('mithka.localPins.v1.user'),
      ),
      isNotEmpty,
      reason: 'the entry stays dormant for when the switch returns',
    );

    store.setActiveAccountUserId(null);
  });

  test(
    'a pin pass stops when the account changes under its awaited unpin',
    () async {
      // Two adopted entries: the server re-pinned both while device-only pins
      // were in place. The store is re-scoped to another account between the
      // first unpin and the second.
      final prefs = await _openStorePrefs();
      final store = LocalPinStore.shared;
      store.initialize(prefs);
      await store.setUnlimitedEnabled(true);
      store.setActiveAccountUserId(_accountUserId);
      // Two local pins whose chats Telegram subsequently pinned itself.
      await store.pin(101, serverPinOrder: 700, pinnedAt: 1);
      await store.pin(102, serverPinOrder: 800, pinnedAt: 2);
      final generationBefore = store.loadGeneration;

      // The replacement account shares the very same chat ids: the colliding
      // keys are what a stale write would touch.
      const replacementAccount = 4242;
      await prefs.setString(
        'mithka.localPins.v1.user$replacementAccount.101',
        '900:9',
      );
      await prefs.setString(
        'mithka.localPins.v1.user$replacementAccount.102',
        '901:10',
      );

      final modelRequests = <Map<String, dynamic>>[];
      final model = ChatListViewModel(
        queryForTesting: (request) => _respond(modelRequests, request),
      );
      addTearDown(model.dispose);
      model.meId = _accountUserId;
      model.onAppear();
      model.loadMore();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Both chats must exist as rows first; otherwise the pass adopts the
      // entry without anything to mutate and moves on.
      for (final id in const [101, 102]) {
        await model.ingestRawChatForTesting(_chat(id));
      }
      // Both are then reported server-pinned: the adoption branch of
      // _syncLocalPinState runs, unpinning the local entry.
      for (final id in const [101, 102]) {
        model.applyUpdateForTesting({
          '@type': 'updateChatPosition',
          'chat_id': id,
          'position': {
            '@type': 'chatPosition',
            'list': {'@type': 'chatListMain'},
            'order': 1200,
            'is_pinned': true,
          },
        });
      }

      // Hold the first unpin's preference write open, so the account switch
      // lands while that write is genuinely in flight.
      final barrier = Completer<void>();
      store.debugUnpinBarrier = barrier;
      // The sync runs 50ms after the position update; wait for the pass to
      // reach its first unpin, which then parks on the barrier.
      for (var i = 0; i < 40 && store.isLocallyPinned(101); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        store.isLocallyPinned(101),
        isFalse,
        reason: 'the first entry was adopted and its write is in flight',
      );

      // Switch the account mid-flight, exactly as `set meId` does on a
      // different account.
      store.setActiveAccountUserId(replacementAccount);
      model.meId = replacementAccount;
      store.debugUnpinBarrier = null;
      barrier.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // The replacement account's pins are untouched: both preference keys are
      // still there and the store still reports them as its own.
      for (final id in const [101, 102]) {
        expect(
          prefs.getString('mithka.localPins.v1.user$replacementAccount.$id'),
          isNotNull,
          reason: 'the stale pass must not remove the replacement keys',
        );
        expect(store.isLocallyPinned(id), isTrue);
      }
      expect(generationBefore, isNot(store.loadGeneration));

      await store.setUnlimitedEnabled(false);
      store.setActiveAccountUserId(null);
    },
  );

  test('disposal stops the pin pass before its next write', () async {
    final prefs = await _openStorePrefs();
    final store = LocalPinStore.shared;
    store.initialize(prefs);
    await store.setUnlimitedEnabled(true);
    store.setActiveAccountUserId(_accountUserId);
    await store.pin(201, serverPinOrder: 700, pinnedAt: 1);
    await store.pin(202, serverPinOrder: 800, pinnedAt: 2);

    final modelRequests = <Map<String, dynamic>>[];
    final model = ChatListViewModel(
      queryForTesting: (request) => _respond(modelRequests, request),
    );
    model.meId = _accountUserId;
    model.onAppear();
    for (final id in const [201, 202]) {
      await model.ingestRawChatForTesting(_chat(id));
    }
    final barrier = Completer<void>();
    store.debugUnpinBarrier = barrier;
    for (final id in const [201, 202]) {
      model.applyUpdateForTesting({
        '@type': 'updateChatPosition',
        'chat_id': id,
        'position': {
          '@type': 'chatPosition',
          'list': {'@type': 'chatListMain'},
          'order': 1200,
          'is_pinned': true,
        },
      });
    }
    // Wait until the pass has reached its first entry and parked there.
    for (var i = 0; i < 40 && store.isLocallyPinned(201); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(store.isLocallyPinned(201), isFalse);

    // Dispose while that write is in flight, then let it finish.
    model.dispose();
    store.debugUnpinBarrier = null;
    barrier.complete();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // The pass stopped: the entry it had not reached is still stored for the
    // list that owns this account next, and no row mutation was scheduled on
    // the disposed model.
    expect(
      store.isLocallyPinned(202),
      isTrue,
      reason: 'a disposed pass must not unpin what it had not reached',
    );

    await store.setUnlimitedEnabled(false);
    store.setActiveAccountUserId(null);
  });

  test('a delayed pin cap does not land on the replacement account', () async {
    final prefs = await _openStorePrefs();
    final store = LocalPinStore.shared;
    store.initialize(prefs);
    await store.setUnlimitedEnabled(true);
    store.setActiveAccountUserId(_accountUserId);

    // The first account's option answer is held; the replacement account's
    // answer arrives immediately.
    final oldCapResponse = Completer<Map<String, dynamic>>();
    var capRequested = 0;
    final modelRequests = <Map<String, dynamic>>[];
    final model = ChatListViewModel(
      queryForTesting: (request) {
        if (request['@type'] == 'getOption') {
          capRequested++;
          if (capRequested == 1) return oldCapResponse.future;
          return Future.value({'@type': 'optionValueInteger', 'value': 9});
        }
        return _respond(modelRequests, request);
      },
    );
    addTearDown(model.dispose);
    model.meId = _accountUserId;
    model.onAppear();
    // The first read is parked in flight.
    for (var i = 0; i < 40 && capRequested == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(capRequested, 1);

    // The account is replaced while the old answer is still in flight.
    const replacementAccount = 6161;
    store.setActiveAccountUserId(replacementAccount);
    model.meId = replacementAccount;
    // The replacement's own read answers 9.
    for (var i = 0; i < 40 && model.pinCapForTesting != 9; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(model.pinCapForTesting, 9);

    // The stale answer would price the replacement account's pins with the
    // old account's cap: it must be dropped.
    oldCapResponse.complete({'@type': 'optionValueInteger', 'value': 3});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      model.pinCapForTesting,
      9,
      reason: 'a delayed answer from the old account must not replace the cap',
    );

    await store.setUnlimitedEnabled(false);
    store.setActiveAccountUserId(null);
  });

  test('two live lists never sort by the other account local pins', () async {
    final prefs = await _openStorePrefs();
    final store = LocalPinStore.shared;
    store.initialize(prefs);
    await store.setUnlimitedEnabled(true);
    Future<Map<String, dynamic>> query(
      Map<String, dynamic> request, {
      required bool firstAccount,
    }) async {
      if (request['@type'] == 'getChats') {
        return {
          '@type': 'chats',
          'chat_ids': firstAccount ? [1, 2] : [2],
        };
      }
      if (!firstAccount && request['@type'] == 'getChat') {
        final chat = _chat(jsonInt(request['chat_id'])!);
        (chat['positions'] as List).single['is_pinned'] = false;
        return chat;
      }
      return _respond([], request);
    }

    final first = ChatListViewModel(
      queryForTesting: (request) => query(request, firstAccount: true),
    );
    final second = ChatListViewModel(
      queryForTesting: (request) => query(request, firstAccount: false),
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.meId = _accountUserId;
    first.onAppear();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(first.chats.map((chat) => chat.id), [1, 2]);

    // B has the same chat ID, unpinned on its server and pinned on-device.
    // A's two rows remain server pins in their original order.
    second.meId = 7272;
    second.onAppear();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await store.pin(2, serverPinOrder: 900, pinnedAt: 9);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(second.chats.single.isPinned, isTrue);
    expect(store.activeAccountUserId, 7272);
    expect(store.isLocallyPinned(2), isTrue);

    // Force the first live list through its real sorting path while B owns
    // the singleton. Reading B's pin here would incorrectly put A's row 2 first.
    first.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': 1,
      'position': {
        '@type': 'chatPosition',
        'list': {'@type': 'chatListMain'},
        'order': 500,
        'is_pinned': true,
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(first.chats.map((chat) => chat.id), [1, 2]);
    expect(store.isLocallyPinned(2), isTrue);
  });
}

/// The id of the chat the tests pin: the one that is not pinned on the server.
const _unpinnedChatId = 6;

/// Five server-pinned chats plus the unpinned one.
const _chatCount = 6;

/// Answers the model's requests like TDLib would.
Future<Map<String, dynamic>> _respond(
  List<Map<String, dynamic>> requests,
  Map<String, dynamic> request,
) async {
  requests.add(Map<String, dynamic>.from(request));
  switch (request['@type']) {
    case 'getChats':
      return {
        '@type': 'chats',
        'chat_ids': const [1, 2, 3, 4, 5, _unpinnedChatId],
      };
    case 'getChat':
      final id = jsonInt(request['chat_id']) ?? 0;
      return _chat(id);
    case 'getUser':
      return {
        '@type': 'user',
        'id': jsonInt(request['user_id']) ?? 0,
        'first_name': 'Peer',
        'last_name': '',
      };
    case 'getOption':
      // The server's pin cap; five chats are already pinned.
      return {'@type': 'optionValueInteger', 'value': 5};
    default:
      return {'@type': 'ok'};
  }
}

/// A main-list chat; the first five are pinned on the server.
Map<String, dynamic> _chat(int id) {
  final pinned = id < _unpinnedChatId;
  final order = pinned ? (_chatCount - id) * 100 : id * 100;
  return {
    '@type': 'chat',
    'id': id,
    'title': 'Chat $id',
    'type': {'@type': 'chatTypePrivate', 'user_id': 1000 + id},
    'last_message': {
      '@type': 'message',
      'id': id * 10,
      'chat_id': id,
      'date': order,
      'is_outgoing': false,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'message $id'},
      },
    },
    'positions': [
      {
        '@type': 'chatPosition',
        'list': {'@type': 'chatListMain'},
        'order': order,
        'is_pinned': pinned,
      },
    ],
  };
}

/// A store bound to the test account with the switch on.
Future<LocalPinStore> _openStore() async {
  final store = LocalPinStore();
  store.initialize(await _openStorePrefs());
  await store.setUnlimitedEnabled(true);
  store.setActiveAccountUserId(_accountUserId);
  addTearDown(() async {
    await store.setUnlimitedEnabled(false);
    store.setActiveAccountUserId(null);
    store.dispose();
  });
  return store;
}

/// Fresh mock preferences; every test starts from an empty store.
Future<SharedPreferences> _openStorePrefs() async {
  SharedPreferences.setMockInitialValues(const {});
  return SharedPreferences.getInstance();
}

/// Synthetic tdjson bindings: lets [TdClient.prepareForTesting] register a
/// client without loading the pinned shared library.
class _FakeBindings implements TdBindings {
  int _nextClientId = 100;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    if (clientId != _clientId) return;
    // Answers the requests the client sends directly (the `setTdlibParameters`
    // handshake). Everything the model asks for goes through queryOverride,
    // which is what the tests read.
    final decoded = jsonDecode(request);
    if (decoded is! Map<String, dynamic>) return;
    final extra = decoded.int64('@extra');
    if (extra == null) return;
    pending.add({'@client_id': clientId, '@extra': extra, '@type': 'ok'});
  }

  /// Registers the client id the test's account runs as.
  void adopt(int clientId) => _clientId = clientId;

  final List<Map<String, dynamic>> pending = [];
  int _clientId = -1;

  @override
  void importSessionString(String sessionString, String destinationPath) {
    File(destinationPath).writeAsBytesSync(Uint8List.fromList(const [1]));
  }

  @override
  bool get supportsSessionStringBackup => false;

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
