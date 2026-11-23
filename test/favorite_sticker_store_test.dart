//
//  favorite_sticker_store_test.dart
//
//  Unlimited sticker favorites: the server list is always the truth, and a
//  sticker the server's cap made it drop is kept on this device while the
//  Advanced switch is on. With the switch off nothing is read or written —
//  extras an earlier run left behind stay dormant.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/favorite_sticker_store.dart';
import 'package:mithka/chat/stickers/sticker_item.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The server cap: 5 favorites in these fixtures.
const _cap = 5;

final _registry = _Registry();
late TdClient _client;
const _userId = 4100;

StickerItem _item(int fileId) =>
    StickerItem(id: fileId, width: 512, height: 512, emoji: '😀');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'mithka.api_credentials.enabled': true,
      'mithka.api_credentials.api_id': '2496',
      'mithka.api_credentials.api_hash': '0123456789abcdef0123456789abcdef',
    });
    final prefs = await SharedPreferences.getInstance();
    final supportDir = Directory.systemTemp.createTempSync('mithka_faves');
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });
    _client = TdClient.shared;
    _client.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: _FakeBindings(),
      queryOverride: _registry.respond,
    );
  });

  setUp(() async {
    _registry.reset();
    SharedPreferences.setMockInitialValues({
      'mithka.api_credentials.enabled': true,
      'mithka.api_credentials.api_id': '2496',
      'mithka.api_credentials.api_hash': '0123456789abcdef0123456789abcdef',
    });
    final slot = _client.addSlot();
    _client.setActive(slot);
    final prefs = await SharedPreferences.getInstance();
    final store = FavoriteStickerStore.shared;
    store.initialize(prefs);
    store.setActiveAccountUserId(_userId);
    store.resetForTest();
    store.initialize(prefs);
    store.setActiveAccountUserId(_userId);
    // setMockInitialValues wiped the switch; re-read it from the fresh prefs.
    await store.setUnlimitedEnabled(false);
    _registry.favorites = [for (var i = 1; i <= _cap; i++) 9000 + i];
  });

  test('switch off: add() sends the request but persists nothing', () async {
    final store = FavoriteStickerStore.shared;
    expect(store.unlimitedEnabled, isFalse);

    store.loadIfNeeded();
    await _waitFor(() => store.items.length == _cap);

    await store.add(_item(9999));
    await _settle();

    expect(
      _registry.calls.where((call) => call.type == 'addFavoriteSticker'),
      isNotEmpty,
      reason: 'the server request must always be sent',
    );
    expect(store.items.map((item) => item.id), isNot(contains(9999)));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isNot(contains(_extrasKey(_userId))));
  });

  test('switch on at cap: add() keeps the overflow on this device', () async {
    final store = FavoriteStickerStore.shared;
    await store.setUnlimitedEnabled(true);

    store.loadIfNeeded();
    await _waitFor(() => store.items.length == _cap);

    await store.add(_item(9999));
    await _settle();

    expect(store.items.map((item) => item.id), contains(9999));
    expect(store.isFavorite(9999), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_extrasKey(_userId)), isNotNull);
    expect(prefs.getString(_extrasKey(_userId)), contains('9999'));
  });

  test('remove() drops the local entry and rewrites the store', () async {
    final store = FavoriteStickerStore.shared;
    await store.setUnlimitedEnabled(true);
    store.loadIfNeeded();
    await _waitFor(() => store.items.length == _cap);

    await store.add(_item(9999));
    await _settle();
    expect(store.isFavorite(9999), isTrue);

    await store.remove(_item(9999));
    await _settle();

    expect(
      _registry.calls.where((call) => call.type == 'removeFavoriteSticker'),
      isNotEmpty,
    );
    expect(store.isFavorite(9999), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_extrasKey(_userId)), isNot(contains('9999')));
  });

  test(
    'dormant: pre-seeded extras appear only while the switch is on',
    () async {
      // An earlier run left one extra behind.
      SharedPreferences.setMockInitialValues({
        'mithka.api_credentials.enabled': true,
        'mithka.api_credentials.api_id': '2496',
        'mithka.api_credentials.api_hash': '0123456789abcdef0123456789abcdef',
        _extrasKey(_userId): '[[7777,null,512,512,"😀",0,0,7778]]',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = FavoriteStickerStore.shared;
      store.initialize(prefs);
      store.setActiveAccountUserId(_userId);

      store.loadIfNeeded();
      await _waitFor(() => store.items.length == _cap);
      expect(
        store.items.map((item) => item.id),
        isNot(contains(7777)),
        reason: 'with the switch off the extra must be invisible',
      );
      expect(store.isFavorite(7777), isFalse);

      await store.setUnlimitedEnabled(true);
      expect(store.items.map((item) => item.id), contains(7777));
      expect(store.isFavorite(7777), isTrue);
    },
  );
}

String _extrasKey(int userId) => 'mithka.faveStickers.v1.user.$userId';

class _Call {
  const _Call(this.clientId, this.request);

  final int clientId;
  final Map<String, dynamic> request;

  String get type => request['@type'] as String? ?? '';
}

/// The synthetic TDLib answers. The favorites list is server truth: a cap is
/// enforced by keeping only the first [_cap] file ids after an add.
class _Registry {
  final List<_Call> calls = [];
  List<int> favorites = [];

  void reset() {
    calls.clear();
  }

  Future<Map<String, dynamic>> respond(
    Map<String, dynamic> request,
    int clientId,
  ) async {
    final type = request['@type'] as String? ?? '';
    calls.add(_Call(clientId, request));
    switch (type) {
      case 'getFavoriteStickers':
        return {
          '@type': 'stickers',
          'stickers': [for (final id in favorites) _stickerJson(id)],
        };
      case 'addFavoriteSticker':
        final id = (request['sticker'] as Map<String, dynamic>)['id'] as int;
        favorites = [...favorites, id].take(_cap).toList();
        return {'@type': 'ok'};
      case 'removeFavoriteSticker':
        final id = (request['sticker'] as Map<String, dynamic>)['id'] as int;
        favorites = favorites.where((f) => f != id).toList();
        return {'@type': 'ok'};
      default:
        return {'@type': 'ok'};
    }
  }
}

Map<String, dynamic> _stickerJson(int fileId) => {
  '@type': 'sticker',
  'sticker': {'@type': 'file', 'id': fileId},
  'format': {'@type': 'stickerFormatWebp'},
  'width': 512,
  'height': 512,
  'emoji': '😀',
};

/// Stands in for tdjson: allocates the client ids the registry answers for.
class _FakeBindings implements TdBindings {
  int _nextClientId = 200;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {}

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
  void importSessionString(String sessionString, String destinationPath) =>
      throw UnimplementedError();

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

Future<void> _settle() async {
  for (var turn = 0; turn < 40; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var turn = 0; turn < 200; turn++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition was not reached');
}
