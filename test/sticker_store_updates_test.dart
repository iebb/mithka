//
//  sticker_store_updates_test.dart
//
//  Installing a sticker set from the set detail page (or another device)
//  must reach the composer's sticker strip without a restart: the store
//  subscribes to TDLib's installed-set updates and reloads itself. A store
//  nobody has opened yet must stay lazy — an update alone never loads it.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/stickers/emoji_store.dart';
import 'package:mithka/chat/stickers/sticker_store.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _registry = _Registry();
late TdClient _client;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'mithka.api_credentials.enabled': true,
      'mithka.api_credentials.api_id': '2496',
      'mithka.api_credentials.api_hash': '0123456789abcdef0123456789abcdef',
    });
    final prefs = await SharedPreferences.getInstance();
    final supportDir = Directory.systemTemp.createTempSync('mithka_stickers');
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

  setUp(() {
    _registry.reset();
    StickerStore.shared.reset();
    EmojiStore.shared.reset();
  });

  test(
    'an installed-set update reloads a loaded store with the new pack',
    () async {
      final account = _addAccount(installed: const [3001]);
      _client.setActive(account.slot);

      // The store is loaded with only pack 3001, seeded as if a previous
      // load finished (loaded, but its pack list is not yet queried again).
      StickerStore.shared.replacePacksForTest([
        StickerPack(id: 3001, title: 'First', loaded: true),
      ]);
      _registry.clearCalls();

      // Telegram now reports two installed sets.
      _registry.accounts[account.clientId] = const _Account(
        installed: [3001, 3002],
      );
      _client.routeUpdateForTesting({
        '@type': 'updateInstalledStickerSets',
        '@client_id': account.clientId,
        'sticker_type': {'@type': 'stickerTypeRegular'},
        'sticker_set_ids': [3001, 3002],
      });

      await _waitFor(
        () => StickerStore.shared.packs.any((pack) => pack.id == 3002),
      );
      await _settle();

      expect(
        StickerStore.shared.packs
            .where((p) => p.id != StickerStore.recentPackId)
            .map((p) => p.id),
        containsAll([3001, 3002]),
        reason: 'the reload must carry the newly installed set',
      );
      expect(
        _registry.callsTo('getInstalledStickerSets', account.clientId),
        greaterThanOrEqualTo(1),
        reason: 'the update must have re-queried the installed sets',
      );
    },
  );

  test('a reset store stays lazy when the update arrives', () async {
    final account = _addAccount(installed: const [3001]);
    _client.setActive(account.slot);

    await _settle();
    final before = _registry.calls.length;

    _client.routeUpdateForTesting({
      '@type': 'updateInstalledStickerSets',
      '@client_id': account.clientId,
      'sticker_type': {'@type': 'stickerTypeRegular'},
      'sticker_set_ids': [3001, 3002],
    });
    await _settle();

    expect(
      _registry.calls.length,
      before,
      reason: 'a store nobody opened must not query on an update',
    );
    expect(StickerStore.shared.packs, isEmpty);
  });

  test(
    'an installed-set update re-queries the emoji packs of a loaded store',
    () async {
      final account = _addAccount(premium: true, customPacks: const [7001]);
      _client.setActive(account.slot);

      EmojiStore.shared.loadIfNeeded();
      await _waitFor(() => EmojiStore.shared.customPacks.isNotEmpty);
      final queries = _registry.callsTo(
        'getInstalledStickerSets',
        account.clientId,
      );

      _client.routeUpdateForTesting({
        '@type': 'updateInstalledStickerSets',
        '@client_id': account.clientId,
        'sticker_type': {'@type': 'stickerTypeCustomEmoji'},
        'sticker_set_ids': [7001],
      });
      await _waitFor(
        () =>
            _registry.callsTo('getInstalledStickerSets', account.clientId) >
            queries,
      );
      await _settle();

      expect(
        EmojiStore.shared.customPacks.map((pack) => pack.id),
        [7001],
        reason: 'the reload must repopulate the same packs',
      );
    },
  );
}

class _Account {
  const _Account({
    this.premium = false,
    this.installed = const [],
    this.customPacks = const [],
  });

  final bool premium;
  final List<int> installed;
  final List<int> customPacks;
}

class _Call {
  const _Call(this.clientId, this.request);

  final int clientId;
  final Map<String, dynamic> request;

  String get type => request['@type'] as String? ?? '';
}

/// The synthetic TDLib answers, keyed by the client that asked.
class _Registry {
  final Map<int, _Account> accounts = {};
  final List<_Call> calls = [];

  int callsTo(String type, int clientId) => calls
      .where((call) => call.type == type && call.clientId == clientId)
      .length;

  void clearCalls() => calls.clear();

  void reset() {
    accounts.clear();
    calls.clear();
  }

  Future<Map<String, dynamic>> respond(
    Map<String, dynamic> request,
    int clientId,
  ) async {
    final type = request['@type'] as String? ?? '';
    calls.add(_Call(clientId, request));
    switch (type) {
      case 'getOption':
        return {
          '@type': 'optionValue',
          'name': 'is_premium',
          'value': accounts[clientId]?.premium ?? false,
        };
      case 'getRecentStickers':
        return {
          '@type': 'stickers',
          'stickers': [_sticker(9101)],
        };
      case 'getInstalledStickerSets':
        final stickerType =
            (request['sticker_type'] as Map<String, dynamic>?)?['@type']
                as String? ??
            '';
        final ids = stickerType == 'stickerTypeCustomEmoji'
            ? (accounts[clientId]?.customPacks ?? const <int>[])
            : (accounts[clientId]?.installed ?? const <int>[]);
        return {
          '@type': 'stickerSets',
          'sets': [
            for (final id in ids)
              {
                '@type': 'stickerSetInfo',
                'id': id,
                'title': 'Set $id',
                'is_installed': true,
              },
          ],
        };
      case 'getStickerSet':
        final setId = request['set_id'] as int;
        return {
          '@type': 'stickerSet',
          'id': setId,
          'title': 'Set $setId',
          'is_installed': true,
          'stickers': [_sticker(setId * 100 + 1), _sticker(setId * 100 + 2)],
        };
      default:
        return {'@type': 'ok'};
    }
  }
}

Map<String, dynamic> _sticker(int fileId) => {
  '@type': 'sticker',
  'sticker': {'@type': 'file', 'id': fileId},
  'format': {'@type': 'stickerFormatWebp'},
  'width': 512,
  'height': 512,
  'emoji': '😀',
};

({int slot, int clientId}) _addAccount({
  List<int> installed = const [],
  bool premium = false,
  List<int> customPacks = const [],
}) {
  final slot = _client.addSlot();
  final clientId = _client.clientId(slot)!;
  _registry.accounts[clientId] = _Account(
    premium: premium,
    installed: installed,
    customPacks: customPacks,
  );
  return (slot: slot, clientId: clientId);
}

/// Stands in for tdjson: allocates the client ids the registry answers for.
class _FakeBindings implements TdBindings {
  int _nextClientId = 100;

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
