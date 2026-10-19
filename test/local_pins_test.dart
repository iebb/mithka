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
        return {'@type': 'ok'};
      },
    );
    final slot = TdClient.shared.addSlot();
    final clientId = TdClient.shared.clientId(slot);
    TdClient.shared.debugSetActiveAccountForTesting(slot, clientId ?? 0);
    bindings.adopt(clientId ?? -1);
  });

  setUp(() async {
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

  test(
    'switch off: a pin toggle is a plain server pin and leaves no local state',
    () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final modelRequests = <Map<String, dynamic>>[];

      final model = ChatListViewModel(
        queryForTesting: (request) => _respond(modelRequests, request),
      );
      addTearDown(model.dispose);
      model.onAppear();
      model.loadMore();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(model.chats, hasLength(_chatCount));
      final target = model.chats.last;
      expect(target.id, _unpinnedChatId);
      final liveOrder = target.order;

      requests.clear();
      model.togglePin(target);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(model.notice, isNull);
      expect(
        target.isPinned,
        isTrue,
        reason: 'the gesture still flips the row',
      );
      final reRead = model.chats.firstWhere((c) => c.id == _unpinnedChatId);
      expect(reRead.isPinned, isTrue);
      expect(
        reRead.order,
        liveOrder,
        reason: 'no band order may be assigned while the switch is off',
      );
      expect(
        model.chats.first.id,
        _unpinnedChatId,
        reason: 'the pin gesture still works while the switch is off',
      );
      // The list the user is looking at is the plain main list, and the pin
      // request the client received is the one the pre-feature code sent,
      // byte for byte.
      expect(requests, [
        {
          '@type': 'toggleChatIsPinned',
          'chat_list': {'@type': 'chatListMain'},
          'chat_id': _unpinnedChatId,
          'is_pinned': true,
        },
      ]);

      // The prune and sync paths run off list-membership updates; with the
      // switch off they must not touch the preference store either, and the
      // transport must stay quiet.
      requests.clear();
      model.applyUpdateForTesting({
        '@type': 'updateChatRemovedFromList',
        'chat_id': _unpinnedChatId,
        'chat_list': {'@type': 'chatListMain'},
      });
      model.applyUpdateForTesting({
        '@type': 'mithkaChatLeft',
        'chat_id': _unpinnedChatId,
      });
      model.applyUpdateForTesting({
        '@type': 'updateChatPosition',
        'chat_id': _unpinnedChatId,
        'position': {
          '@type': 'chatPosition',
          'list': {'@type': 'chatListMain'},
          'order': liveOrder,
          'is_pinned': false,
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(prefs.getKeys(), isEmpty);
      // The client transport saw nothing either: no pin request, and no
      // option read for a limit the disabled feature never consults.
      expect(requests, isEmpty);
    },
  );

  test('the switch persists and the store pins and unpins', () async {
    final store = await _openStore();
    var notified = 0;
    store.addListener(() => notified++);

    expect(store.unlimitedEnabled, isTrue);
    expect(store.isLocallyPinned(7), isFalse);

    await store.pin(7, serverPinOrder: 100, pinnedAt: 1000);
    expect(store.isLocallyPinned(7), isTrue);
    expect(store.entryFor(7)!.serverPinOrder, 100);
    expect(notified, 1);

    // Re-pinning with the identical snapshot changes nothing.
    await store.pin(7, serverPinOrder: 100, pinnedAt: 1000);
    expect(notified, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('mithka.localPins.v1.user$_accountUserId.7'),
      '100:1000',
    );

    await store.unpin(7);
    expect(store.isLocallyPinned(7), isFalse);
    expect(store.effectiveOrder(7, 700), 700);
    expect(prefs.getKeys(), isNot(contains('mithka.localPins.v1.user42.7')));
    expect(notified, 2);
  });

  test('a pin without a positive order or account is refused', () async {
    final store = await _openStore();
    await store.pin(7, serverPinOrder: 0, pinnedAt: 1000);
    expect(store.isLocallyPinned(7), isFalse);

    store.setActiveAccountUserId(null);
    await store.pin(7, serverPinOrder: 100, pinnedAt: 1000);
    expect(store.isLocallyPinned(7), isFalse);
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

  test('prune drops pins whose chat left the list', () async {
    final store = await _openStore();
    await store.pin(7, serverPinOrder: 100, pinnedAt: 1000);
    await store.pin(8, serverPinOrder: 200, pinnedAt: 2000);
    await store.pin(9, serverPinOrder: 300, pinnedAt: 3000);

    await store.pruneTo(const [7, 8]);

    expect(store.isLocallyPinned(9), isFalse);
    expect(store.isLocallyPinned(7), isTrue);
    expect(store.effectiveOrder(9, 900), 900);
    expect(store.effectiveOrder(7, 700), 301);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys(),
      unorderedEquals([
        'mithka.localPins.unlimited.v1',
        'mithka.localPins.v1.user42.7',
        'mithka.localPins.v1.user42.8',
      ]),
    );
  });

  test(
    'store invariant: every local sorts above the list\'s maximum server order',
    () async {
      final store = await _openStore();
      await store.pin(7, serverPinOrder: 100, pinnedAt: 1000);
      await store.pin(8, serverPinOrder: 250, pinnedAt: 2000);
      await store.pin(9, serverPinOrder: 100, pinnedAt: 3000);

      // Server orders the device knows about, all below the band.
      expect(store.maxServerPinOrder, 250);
      for (final chatId in const [7, 8, 9]) {
        final order = store.effectiveOrder(chatId, 10);
        expect(
          order,
          greaterThan(store.maxServerPinOrder),
          reason: 'chat $chatId must outrank every server pin',
        );
      }
      // A chat without an entry keeps its live order.
      expect(store.effectiveOrder(10, 999), 999);
    },
  );

  test(
    'store invariant: among locals the most recently pinned comes first',
    () async {
      final store = await _openStore();
      await store.pin(7, serverPinOrder: 100, pinnedAt: 1000);
      await store.pin(8, serverPinOrder: 250, pinnedAt: 2000);
      await store.pin(9, serverPinOrder: 100, pinnedAt: 3000);

      final oldest = store.effectiveOrder(7, 700);
      final middle = store.effectiveOrder(8, 800);
      final newest = store.effectiveOrder(9, 900);
      expect(newest, greaterThan(middle));
      expect(middle, greaterThan(oldest));

      // Same server snapshot (nothing moved between the two pins): the pin
      // time is what decides.
      final tieStore = await _openStore();
      await tieStore.pin(1, serverPinOrder: 400, pinnedAt: 1000);
      await tieStore.pin(2, serverPinOrder: 400, pinnedAt: 2000);
      expect(
        tieStore.effectiveOrder(2, 1),
        greaterThan(tieStore.effectiveOrder(1, 1)),
      );
    },
  );

  test('store invariant: recomputing the band is idempotent', () async {
    final store = await _openStore();
    await store.pin(7, serverPinOrder: 100, pinnedAt: 1000);
    await store.pin(8, serverPinOrder: 250, pinnedAt: 2000);

    final first = {
      for (final id in const [7, 8]) id: store.effectiveOrder(id, 1),
    };
    // Reading the entries, re-reading the band and running a no-op prune all
    // leave the mapping alone.
    expect(store.entries, hasLength(2));
    await store.pruneTo(const [7, 8]);
    final second = {
      for (final id in const [7, 8]) id: store.effectiveOrder(id, 1),
    };
    expect(second, first);

    // A third pin raises the base to the largest snapshot any pin has seen
    // (300), so the whole band moves above it — the locals keep their
    // relative order and stay above every server position.
    await store.pin(9, serverPinOrder: 300, pinnedAt: 3000);
    expect(store.effectiveOrder(7, 1), first[7]! + 50);
    expect(store.effectiveOrder(8, 1), first[8]! + 50);
    expect(store.effectiveOrder(9, 1), 303);
    expect(store.effectiveOrder(9, 1), greaterThan(300));
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

  test('a server position that pins the chat drops the local entry', () async {
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

    final target = model.chats.last;
    model.togglePin(target);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(store.isLocallyPinned(_unpinnedChatId), isTrue);

    // Telegram pinned the chat itself while the local pin was in place:
    // its position is authoritative and the local entry is obsolete.
    model.applyUpdateForTesting({
      '@type': 'updateChatPosition',
      'chat_id': _unpinnedChatId,
      'position': {
        '@type': 'chatPosition',
        'list': {'@type': 'chatListMain'},
        'order': 700,
        'is_pinned': true,
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(store.isLocallyPinned(_unpinnedChatId), isFalse);
    expect(store.entryFor(_unpinnedChatId), isNull);
    expect(target.isPinned, isTrue);
    expect(target.order, 700);
    expect(model.chats.first.id, _unpinnedChatId);

    await store.setUnlimitedEnabled(false);
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
