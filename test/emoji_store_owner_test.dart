//
//  emoji_store_owner_test.dart
//
//  Installed custom-emoji pack ids and sticker ids are account-scoped, so a
//  pack load that outlives an account switch must never publish the account it
//  started for into the account the user is now looking at. These tests drive
//  the real TDLib registry (clients created by `addSlot`, queries answered per
//  client) and the production topic-icon picker.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/custom_emoji.dart';
import 'package:mithka/chat/emoji_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_icon_picker_view.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alpha = _Pack(3101, 'Alpha', [7301, 7302]);
const _beta = _Pack(3201, 'Beta', [8301]);

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
    final supportDir = Directory.systemTemp.createTempSync('mithka_emoji');
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });
    _client = TdClient.shared;
    _client.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: _FakeBindings(_client),
      queryOverride: _registry.respond,
    );
  });

  setUp(() {
    _registry.reset();
    EmojiStore.shared.reset();
    CustomEmojiCenter.shared.reset();
  });

  test('an ownerless load stays lazy until an account is available', () async {
    _client.debugSetActiveAccountForTesting(0, 0);
    EmojiStore.shared.loadIfNeeded();
    await _settleStore();
    expect(_registry.calls, isEmpty);

    final only = _addAccount(premium: true, packs: const [_alpha]);
    _client.setActive(only.slot);
    EmojiStore.shared.loadIfNeeded();
    await _settleStore();

    expect(EmojiStore.shared.customPacks.map((pack) => pack.id), [_alpha.id]);
    expect(_registry.callsTo('getOption', only.clientId), 1);
  });

  testWidgets('a stale pack completion never replaces the new account picker', (
    tester,
  ) async {
    final first = _addAccount(premium: true, packs: const [_alpha]);
    _client.setActive(first.slot);
    final second = _addAccount(premium: true, packs: const [_beta]);

    // The old account's load is already past getInstalledStickerSets and is
    // waiting for its Alpha pack when the user switches accounts.
    final heldSet = _registry.gate('set', first.clientId);
    EmojiStore.shared.loadIfNeeded();
    await _pumpUntil(tester, () => heldSet.started);
    expect(EmojiStore.shared.customPacks, isEmpty);

    // Exactly what AccountStore does on a switch, then the new account's
    // picker mounts and finishes its own load.
    _client.setActive(second.slot);
    EmojiStore.shared.reset();
    await _pumpPicker(tester);
    expect(find.text('Beta'), findsOneWidget);
    expect(
      EmojiStore.shared.customPacks.map((pack) => pack.id),
      [_beta.id],
      reason: 'the new account must finish loading before the stale response',
    );

    heldSet.release();
    await _settle(tester);

    expect(
      find.text('Beta'),
      findsOneWidget,
      reason: 'the new account picker keeps its own pack',
    );
    expect(
      find.text('Alpha'),
      findsNothing,
      reason: 'the previous account response must not reach this picker',
    );
    expect(
      find.byKey(const ValueKey('profile-icon-pack-3201')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profile-icon-pack-3101')), findsNothing);
    expect(EmojiStore.shared.customPacks.map((pack) => pack.id), [_beta.id]);
    // The stale completion only ever asked the old client for Alpha.
    expect(
      [
        for (final call in _registry.calls)
          if (call.type == 'getStickerSet' && call.clientId == second.clientId)
            call.request['set_id'],
      ],
      [_beta.id],
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'a load that started for the previous account cannot replace the new packs',
    () async {
      final first = _addAccount(premium: true, packs: const [_alpha]);
      _client.setActive(first.slot);
      final second = _addAccount(premium: true, packs: const [_beta]);

      final heldSets = _registry.gate('sets', first.clientId);
      EmojiStore.shared.loadIfNeeded();
      await _waitFor(() => heldSets.started);

      _client.setActive(second.slot);
      EmojiStore.shared.reset();
      EmojiStore.shared.loadIfNeeded();
      await _waitFor(() => EmojiStore.shared.customPacks.isNotEmpty);
      expect(EmojiStore.shared.customPacks.map((pack) => pack.id), [_beta.id]);

      // The old account's slow answer arrives after the new account finished.
      heldSets.release();
      await _settleStore();

      expect(
        EmojiStore.shared.customPacks.map((pack) => pack.id),
        [_beta.id],
        reason: 'the finished load for the old account lost its ownership',
      );
      expect(
        [
          for (final call in _registry.calls)
            if (call.type == 'getStickerSet')
              (call.clientId, call.request['set_id']),
        ],
        [(second.clientId, _beta.id)],
        reason: 'the stale load must not fetch packs after the switch',
      );
    },
  );

  test(
    'a stale failure neither clears the new packs nor re-arms the store',
    () async {
      final first = _addAccount(premium: true, packs: const [_alpha]);
      _client.setActive(first.slot);
      final second = _addAccount(premium: true, packs: const [_beta]);

      final heldSets = _registry.gate('sets', first.clientId);
      _registry.fail('sets', first.clientId);
      EmojiStore.shared.loadIfNeeded();
      await _waitFor(() => heldSets.started);

      _client.setActive(second.slot);
      EmojiStore.shared.reset();
      EmojiStore.shared.loadIfNeeded();
      await _waitFor(() => EmojiStore.shared.customPacks.isNotEmpty);
      expect(EmojiStore.shared.customPacks.map((pack) => pack.id), [_beta.id]);
      final optionCalls = _registry.callsTo('getOption', second.clientId);

      // The stranded request for the old account now fails.
      heldSets.release();
      await _settleStore();

      expect(
        EmojiStore.shared.customPacks.map((pack) => pack.id),
        [_beta.id],
        reason: 'a stale failure must not touch the new account packs',
      );
      expect(EmojiStore.shared.isPremium, isTrue);

      // If the stale failure cleared `_loaded`, this would fetch everything again.
      EmojiStore.shared.loadIfNeeded();
      await _settleStore();
      expect(
        _registry.callsTo('getOption', second.clientId),
        optionCalls,
        reason: 'the new account load must stay loaded after the stale failure',
      );
      expect(EmojiStore.shared.customPacks.map((pack) => pack.id), [_beta.id]);
    },
  );

  test('a single account still loads its packs from its own client', () async {
    final only = _addAccount(premium: true, packs: const [_alpha]);
    _client.setActive(only.slot);

    final heldOption = _registry.gate('option', only.clientId);
    final heldSets = _registry.gate('sets', only.clientId);
    EmojiStore.shared.loadIfNeeded();
    await _waitFor(() => heldOption.started);
    expect(EmojiStore.shared.customPacks, isEmpty);

    heldOption.release();
    await _waitFor(() => heldSets.started);
    expect(EmojiStore.shared.isPremium, isTrue);

    heldSets.release();
    await _waitFor(() => EmojiStore.shared.customPacks.isNotEmpty);
    expect(EmojiStore.shared.customPacks.map((pack) => pack.id), [_alpha.id]);
    expect(
      EmojiStore.shared.customPacks.single.title,
      'Alpha',
      reason: 'the pack title and cover come back unchanged for one account',
    );
    expect(
      _registry.calls.map((call) => call.clientId).toSet(),
      {only.clientId},
      reason: 'an unchanged owner must never query a second client',
    );
  });

  test(
    'a newer load for the same account wins over the one it replaced',
    () async {
      final only = _addAccount(premium: true, packs: const [_alpha]);
      _client.setActive(only.slot);

      // The first load is still waiting for the installed sets when the user
      // installs another pack, which invalidates the store from elsewhere.
      final heldSets = _registry.gate('sets', only.clientId);
      EmojiStore.shared.loadIfNeeded();
      await _waitFor(() => heldSets.started);

      _registry.accounts[only.clientId] = const _Account(
        premium: true,
        packs: [_beta],
      );
      EmojiStore.shared.invalidate();
      await _waitFor(() => EmojiStore.shared.customPacks.isNotEmpty);
      expect(EmojiStore.shared.customPacks.map((pack) => pack.id), [_beta.id]);

      // The superseded load answers with the pack list it started from.
      heldSets.release();
      await _settleStore();

      expect(
        EmojiStore.shared.customPacks.map((pack) => pack.id),
        [_beta.id],
        reason: 'the newer load owns the store even for the same account',
      );
    },
  );

  test(
    'a held premium check cannot set isPremium for the new account',
    () async {
      final first = _addAccount(premium: true, packs: const [_alpha]);
      _client.setActive(first.slot);
      final second = _addAccount(premium: false, packs: const []);

      final heldOption = _registry.gate('option', first.clientId);
      EmojiStore.shared.loadIfNeeded();
      await _waitFor(() => heldOption.started);

      _client.setActive(second.slot);
      EmojiStore.shared.reset();
      EmojiStore.shared.loadIfNeeded();
      await _settleStore();
      expect(EmojiStore.shared.isPremium, isFalse);
      expect(EmojiStore.shared.customPacks, isEmpty);

      // The old account was premium; its late answer belongs to nobody now.
      heldOption.release();
      await _settleStore();

      expect(
        EmojiStore.shared.isPremium,
        isFalse,
        reason: 'the previous account premium flag must not leak forward',
      );
      expect(EmojiStore.shared.customPacks, isEmpty);
    },
  );
}

class _Pack {
  const _Pack(this.id, this.title, this.emojiIds);

  final int id;
  final String title;
  final List<int> emojiIds;
}

class _Account {
  const _Account({required this.premium, required this.packs});

  final bool premium;
  final List<_Pack> packs;
}

/// Holds the first request of a kind open until the test releases it. Later
/// requests pass straight through, so a reload can finish while the original
/// answer is still stranded.
class _Gate {
  final Completer<void> _arrived = Completer<void>();
  final Completer<void> _released = Completer<void>();
  bool _held = false;

  bool get started => _arrived.isCompleted;

  Future<void> arrive() {
    if (_held) return Future<void>.value();
    _held = true;
    if (!_arrived.isCompleted) _arrived.complete();
    return _released.future;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class _Call {
  const _Call(this.clientId, this.request);

  final int clientId;
  final Map<String, dynamic> request;

  String get type => request['@type'] as String? ?? '';
}

/// The synthetic TDLib answers, keyed by the client that asked. Two accounts
/// answer differently so a response can be traced back to its owner.
class _Registry {
  final Map<int, _Account> accounts = {};
  final List<_Call> calls = [];
  final Map<String, _Gate> _gates = {};
  final Set<String> _failures = {};

  _Gate gate(String kind, int clientId) =>
      _gates.putIfAbsent('$kind:$clientId', _Gate.new);

  void fail(String kind, int clientId) => _failures.add('$kind:$clientId');

  int callsTo(String type, int clientId) => calls
      .where((call) => call.type == type && call.clientId == clientId)
      .length;

  void reset() {
    accounts.clear();
    calls.clear();
    _gates.clear();
    _failures.clear();
  }

  Future<Map<String, dynamic>> respond(
    Map<String, dynamic> request,
    int clientId,
  ) async {
    final type = request['@type'] as String? ?? '';
    calls.add(_Call(clientId, request));
    switch (type) {
      case 'getOption':
        if (request['name'] != 'is_premium') {
          return {
            '@type': 'optionValue',
            'name': request['name'],
            'value': false,
          };
        }
        // Snapshot before the gate: the answer was prepared for the client
        // that asked, whenever the test lets it through.
        final premium = accounts[clientId]?.premium ?? false;
        await _pass('option', clientId);
        return {'@type': 'optionValue', 'name': 'is_premium', 'value': premium};
      case 'getInstalledStickerSets':
        if ((request['sticker_type'] as Map<String, dynamic>?)?['@type'] !=
            'stickerTypeCustomEmoji') {
          return {'@type': 'stickerSets', 'sets': <Map<String, dynamic>>[]};
        }
        final installed = accounts[clientId]?.packs ?? const <_Pack>[];
        await _pass('sets', clientId);
        return {
          '@type': 'stickerSets',
          'sets': [
            for (final pack in installed)
              {
                '@type': 'stickerSetInfo',
                'id': pack.id,
                'title': pack.title,
                'is_installed': true,
              },
          ],
        };
      case 'getStickerSet':
        final setId = request['set_id'] as int;
        final pack = (accounts[clientId]?.packs ?? const <_Pack>[]).firstWhere(
          (candidate) => candidate.id == setId,
          orElse: () =>
              throw StateError('client $clientId has no installed pack $setId'),
        );
        await _pass('set', clientId);
        return _stickerSet(pack);
      case 'getDefaultChatEmojiStatuses':
      case 'getDefaultEmojiStatuses':
        return {
          '@type': 'emojiStatuses',
          'emoji_statuses': [
            for (final id in [9001, 9002])
              {
                '@type': 'emojiStatus',
                'custom_emoji_id': id,
                'expiration_date': 0,
              },
          ],
        };
      case 'getCustomEmojiStickers':
        return {'@type': 'stickers', 'stickers': <Map<String, dynamic>>[]};
      default:
        return {'@type': 'ok'};
    }
  }

  Future<void> _pass(String kind, int clientId) async {
    final gate = _gates['$kind:$clientId'];
    if (gate != null) await gate.arrive();
    if (_failures.remove('$kind:$clientId')) {
      throw TdError({
        '@type': 'error',
        'code': 400,
        'message': '$kind unavailable for client $clientId',
      });
    }
  }
}

Map<String, dynamic> _stickerSet(_Pack pack) => {
  '@type': 'stickerSet',
  'id': pack.id,
  'title': pack.title,
  'stickers': [
    for (var index = 0; index < pack.emojiIds.length; index++)
      {
        '@type': 'sticker',
        'sticker': {'@type': 'file', 'id': pack.id * 100 + index},
        'format': {'@type': 'stickerFormatWebp'},
        'width': 512,
        'height': 512,
        'emoji': '',
        'full_type': {
          '@type': 'stickerFullTypeCustomEmoji',
          'custom_emoji_id': pack.emojiIds[index],
          'needs_repainting': false,
        },
      },
  ],
};

({int slot, int clientId}) _addAccount({
  required bool premium,
  required List<_Pack> packs,
}) {
  final slot = _client.addSlot();
  final clientId = _client.clientId(slot)!;
  _registry.accounts[clientId] = _Account(premium: premium, packs: packs);
  return (slot: slot, clientId: clientId);
}

/// Stands in for tdjson: allocates the client ids the registry answers for.
class _FakeBindings implements TdBindings {
  _FakeBindings(this._client);

  final TdClient _client;
  int _nextClientId = 100;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    final decoded = jsonDecode(request) as Map<String, dynamic>;
    if (decoded['@type'] == 'close') {
      _client.debugCompleteClientClosed(clientId);
    }
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

Future<void> _settleStore() async {
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

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var turn = 0; turn < 100 && !condition(); turn++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'widget condition was not reached');
}

Future<void> _pumpPicker(WidgetTester tester) async {
  final theme = await _theme();
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: const ProfileIconPickerView(
          selectedId: 0,
          title: 'Topic icon',
          source: ProfileIconSource.status,
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<ThemeController> _theme() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return ThemeController(preferences);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);
