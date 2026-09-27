import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_sticker_packs_service.dart';
import 'package:mithka/chat/chat_sticker_packs_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

Map<String, dynamic> _from(int userId) => {
  '@type': 'messageSenderUser',
  'user_id': userId,
};

Map<String, dynamic> _sticker(int id, int date, int setId, {int from = 1}) => {
  '@type': 'message',
  'id': id,
  'date': date,
  'sender_id': _from(from),
  'content': {
    '@type': 'messageSticker',
    'sticker': {'@type': 'sticker', 'set_id': '$setId'},
  },
};

Map<String, dynamic> _text(
  int id,
  int date,
  List<int> emojiIds, {
  int? reactionEmojiId,
  int from = 1,
}) => {
  '@type': 'message',
  'id': id,
  'date': date,
  'sender_id': _from(from),
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'x',
      'entities': [
        for (final emojiId in emojiIds)
          {
            '@type': 'textEntity',
            'type': {
              '@type': 'textEntityTypeCustomEmoji',
              'custom_emoji_id': '$emojiId',
            },
          },
      ],
    },
  },
  if (reactionEmojiId != null)
    'interaction_info': {
      'reactions': {
        'reactions': [
          {
            'type': {
              '@type': 'reactionTypeCustomEmoji',
              'custom_emoji_id': '$reactionEmojiId',
            },
            // Three reactors, of whom TDLib names the two most recent.
            'total_count': 3,
            'recent_sender_ids': [_from(5), _from(6)],
          },
        ],
      },
    },
};

/// A fake TDLib. Chats 1 and 2 are in the main list, chat 3 in the archive;
/// histories are newest first, sent by users 1–4. Custom emoji 501/502 belong to set 50, 601 to
/// set 60. Set N has N % 17 items, so sizes differ between sets.
class _FakeTd {
  _FakeTd({Map<int, List<Map<String, dynamic>>>? history})
    : history =
          history ??
          {
            1: [
              _sticker(30, 900, 10),
              _sticker(20, 500, 10, from: 2),
              _text(10, 100, [501, 502]),
            ],
            2: [
              _sticker(31, 800, 20, from: 3),
              _text(21, 600, [601], reactionEmojiId: 501, from: 3),
            ],
            3: [_sticker(5, 700, 30, from: 4)],
          },
      archive = history == null ? {3} : const {};

  final Map<int, List<Map<String, dynamic>>> history;
  final Set<int> archive;
  var userId = 777;
  final requests = <Map<String, dynamic>>[];
  final installed = <int>{20};

  /// Every message id getChatHistory handed out, per chat, in order.
  final delivered = <int, List<int>>{};

  /// Errors getStickerSet raises, once each, keyed by set id.
  final setErrors = <int, List<Map<String, dynamic>>>{};

  // Round-trip through JSON so nested maps are typed like real TDLib output.
  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async =>
      jsonDecode(jsonEncode(_respond(request))) as Map<String, dynamic>;

  Map<String, dynamic> _respond(Map<String, dynamic> request) {
    requests.add(request);
    switch (request['@type']) {
      case 'getMe':
        return {'@type': 'user', 'id': userId};
      case 'getChats':
        final archived = request['chat_list']['@type'] == 'chatListArchive';
        final ids = [
          for (final id in history.keys)
            if (archive.contains(id) == archived) id,
        ];
        return {'chat_ids': ids.take(request['limit'] as int).toList()};
      case 'getChat':
        final messages = history[request['chat_id']]!;
        return {
          'id': request['chat_id'],
          if (messages.isNotEmpty) 'last_message': messages.first,
        };
      case 'getChatHistory':
        final from = request['from_message_id'] as int;
        final older = history[request['chat_id']]!.where(
          (m) => from == 0 || (m['id'] as int) < from,
        );
        // Like TDLib, an uncached first read returns only the newest message.
        final limit = from == 0 ? 1 : request['limit'] as int;
        final page = older.take(limit).toList();
        (delivered[request['chat_id'] as int] ??= []).addAll(
          page.map((m) => m['id'] as int),
        );
        return {'messages': page};
      case 'getCustomEmojiStickers':
        final ids = (request['custom_emoji_ids'] as List).cast<String>();
        return {
          'stickers': [
            for (final id in ids)
              {
                'set_id': id.startsWith('5') ? '50' : '60',
                'full_type': {
                  '@type': 'stickerFullTypeCustomEmoji',
                  'custom_emoji_id': id,
                },
              },
          ],
        };
      case 'getStickerSet':
        final id = request['set_id'] as int;
        final errors = setErrors[id];
        if (errors != null && errors.isNotEmpty) {
          throw TdError(errors.removeAt(0));
        }
        return {
          'id': '$id',
          'title': 'Pack $id',
          'is_installed': installed.contains(id),
          'sticker_type': {
            '@type': id >= 50 && id < 100
                ? 'stickerTypeCustomEmoji'
                : 'stickerTypeRegular',
          },
          // Animated with no thumbnail: previews fall back to the emoji glyph,
          // so widget tests never start file downloads.
          'stickers': [
            for (var i = 0; i < id % 17; i++)
              {
                'sticker': {'id': id * 100 + i},
                'format': {'@type': 'stickerFormatTgs'},
                'emoji': '😀',
              },
          ],
        };
      case 'changeStickerSet':
        installed.add(request['set_id'] as int);
        return {'@type': 'ok'};
    }
    throw StateError('unexpected ${request['@type']}');
  }
}

/// One chat of [count] messages; message i uses set 1000 + i ~/ 4, or none
/// when [withPacks] is false.
_FakeTd _longChat(int count, {bool withPacks = true}) => _FakeTd(
  history: {
    9: [
      for (var i = 0; i < count; i++)
        withPacks
            ? _sticker(count - i, 100000 - i, 1000 + i ~/ 4)
            : _text(count - i, 100000 - i, const []),
    ],
  },
);

ChatUsedPack _pack(
  int id,
  String title, {
  int uses = 1,
  int lastUsed = 0,
  int items = 1,
  bool installed = false,
}) => ChatUsedPack(
  id: id,
  title: title,
  isCustomEmoji: false,
  itemCount: items,
  uses: uses,
  lastUsed: lastUsed,
  installed: installed,
);

Map<int, int> _uses(List<ChatUsedPack> packs) => {
  for (final p in packs) p.id: p.uses,
};

Map<int, int> _users(List<ChatUsedPack> packs) => {
  for (final p in packs) p.id: p.users,
};

int _setLookups(_FakeTd td) =>
    td.requests.where((r) => r['@type'] == 'getStickerSet').length;

int _historyReads(_FakeTd td) =>
    td.requests.where((r) => r['@type'] == 'getChatHistory').length;

/// Keeps saved scans in memory, round-tripped through JSON like the file.
class _MemoryStore extends ChatPackScanStore {
  final saved = <int, String>{};

  @override
  Future<Map<String, dynamic>?> read(int userId) async {
    final json = saved[userId];
    return json == null ? null : jsonDecode(json) as Map<String, dynamic>;
  }

  @override
  Future<void> write(int userId, Map<String, dynamic> state) async {
    saved[userId] = jsonEncode(state);
  }
}

/// A store whose writes wait for [release], to catch overlapping saves.
class _SlowStore extends ChatPackScanStore {
  final written = <Map<String, dynamic>>[];
  final _gate = Completer<void>();
  var _running = 0;
  var maxConcurrent = 0;

  void release() => _gate.complete();

  @override
  Future<Map<String, dynamic>?> read(int userId) async => null;

  @override
  Future<void> write(int userId, Map<String, dynamic> state) async {
    _running += 1;
    maxConcurrent = _running > maxConcurrent ? _running : maxConcurrent;
    await _gate.future;
    written.add(state);
    _running -= 1;
  }
}

ChatStickerPacksService _service(
  _FakeTd td, {
  ChatPackScanStore? store,
  int now = 10000,
}) => ChatStickerPacksService(
  query: td.call,
  store: store ?? _MemoryStore(),
  now: () => now,
);

void main() {
  final fixtures = L10nFixtures.load();

  setUp(() {
    fixtures.install();
    AppStrings.setLocale(const Locale('en'));
  });

  test('one chat: dedupes packs by set and counts uses', () async {
    final td = _FakeTd();
    final scanner = ChatStickerPacksService(query: td.call).chatScanner(1);
    await scanner.loadMore();
    await scanner.settle();

    expect(scanner.scannedMessages, 3);
    expect(scanner.exhausted, isTrue);
    expect(_uses(scanner.stickers), {10: 2});
    expect(_users(scanner.stickers), {10: 2}, reason: 'users 1 and 2');
    expect(scanner.stickers.single.lastUsed, 900);
    expect(scanner.stickers.single.itemCount, 10);
    expect(scanner.stickers.single.previews, hasLength(10));
    expect(_uses(scanner.emoji), {50: 2});
    expect(_users(scanner.emoji), {50: 1}, reason: 'one message, one sender');
  });

  test(
    'global scan merges every chat by message date, batch by batch',
    () async {
      final td = _FakeTd();
      final scanner = await _service(td).openGlobalScanner();

      // The two newest messages overall: chat 1 at 900, chat 2 at 800.
      await scanner.loadMore(messages: 2);
      await scanner.settle();
      expect(scanner.scannedMessages, 2);
      expect(_uses(scanner.stickers), {10: 1, 20: 1});
      expect(scanner.emoji, isEmpty);
      expect(scanner.exhausted, isFalse);

      // Next: the archived chat 3 at 700, then chat 2 at 600, whose custom
      // emoji reaction had three reactors.
      await scanner.loadMore(messages: 2);
      await scanner.settle();
      expect(_uses(scanner.stickers), {10: 1, 20: 1, 30: 1});
      expect(_uses(scanner.emoji), {60: 1, 50: 3});

      await scanner.loadMore();

      await scanner.settle();
      expect(scanner.scannedMessages, 6);
      expect(scanner.exhausted, isTrue);
      expect(_uses(scanner.stickers), {10: 2, 20: 1, 30: 1});
      // 501 (three reactors, then text) and 502 all land on set 50.
      expect(_uses(scanner.emoji), {60: 1, 50: 5});
      // Set 50: user 1's text plus the two named reactors, 5 and 6.
      expect(_users(scanner.emoji), {60: 1, 50: 3});
      expect(_users(scanner.stickers), {10: 2, 20: 1, 30: 1});
      expect(scanner.stickers.firstWhere((p) => p.id == 20).installed, isTrue);
      expect(
        td.requests.where((r) => r['@type'] == 'getStickerSet').length,
        5,
        reason: 'each set is looked up once across batches',
      );
    },
  );

  test(
    'a reopened scan resumes where it stopped, counting nothing twice',
    () async {
      final store = _MemoryStore();
      final td = _FakeTd();
      final first = await _service(td, store: store).openGlobalScanner();
      await first.loadMore(messages: 3);
      await first.settle();
      await first.save(force: true);
      expect(first.exhausted, isFalse);

      final lookups = _setLookups(td);

      final reopened = await _service(td, store: store).openGlobalScanner();

      await reopened.resolveKnown();

      await reopened.settle();

      // What the first opening found is back before anything new is read,

      // and without asking Telegram for a single pack again.

      expect(_setLookups(td), lookups);
      expect(reopened.scannedMessages, 3);
      expect(_uses(reopened.stickers), {10: 1, 20: 1, 30: 1});

      await reopened.loadMore();

      await reopened.settle();
      expect(reopened.exhausted, isTrue);
      expect(reopened.scannedMessages, 6);
      // Exactly the totals of one uninterrupted scan.
      expect(_uses(reopened.stickers), {10: 2, 20: 1, 30: 1});
      expect(_uses(reopened.emoji), {60: 1, 50: 5});
      expect(_users(reopened.emoji), {60: 1, 50: 3});
    },
  );

  test('a reopened scan catches up on messages sent since', () async {
    final store = _MemoryStore();
    final td = _FakeTd();
    final first = await _service(
      td,
      store: store,
      now: 1000,
    ).openGlobalScanner();
    await first.loadMore();
    await first.settle();
    await first.save(force: true);
    expect(first.exhausted, isTrue);

    // A new sticker in chat 1, after the first scan began.
    td.history[1]!.insert(0, _sticker(40, 1500, 10));
    final reopened = await _service(
      td,
      store: store,
      now: 2000,
    ).openGlobalScanner();
    await reopened.resolveKnown();
    await reopened.settle();
    expect(reopened.exhausted, isFalse, reason: 'the new window is unread');
    await reopened.loadMore();
    await reopened.settle();
    expect(reopened.exhausted, isTrue);
    expect(reopened.scannedMessages, 7);
    expect(_uses(reopened.stickers), {10: 3, 20: 1, 30: 1});
    expect(reopened.stickers.firstWhere((p) => p.id == 10).lastUsed, 1500);
  });

  test('a rate-limited pack waits and is looked up again', () async {
    final td = _FakeTd()
      ..setErrors[20] = [
        {'code': 429, 'message': 'Too Many Requests: retry after 1'},
      ];
    final scanner = await _service(td).openGlobalScanner();
    await scanner.loadMore();
    await scanner.settle();
    expect(_uses(scanner.stickers), {10: 2, 20: 1, 30: 1});
    expect(scanner.toJson()['unresolvableSets'], isEmpty);
  });

  test('only a 400 marks a pack as gone for good', () async {
    final store = _MemoryStore();
    final td = _FakeTd()
      ..setErrors[20] = [
        for (var i = 0; i < 3; i++) {'code': 500, 'message': 'Timeout'},
      ]
      ..setErrors[30] = [
        {'code': 400, 'message': 'STICKERSET_INVALID'},
      ];
    final scanner = await _service(td, store: store).openGlobalScanner();
    await scanner.loadMore();
    await scanner.settle();
    expect(scanner.stickers.map((p) => p.id), [10]);
    expect(scanner.toJson()['unresolvableSets'], [30]);
    await scanner.save(force: true);

    // Next opening: the failed one is asked again, the gone one is not.
    final reopened = await _service(td, store: store).openGlobalScanner();
    await reopened.resolveKnown();
    await reopened.settle();
    expect(reopened.stickers.map((p) => p.id), unorderedEquals([10, 20]));
  });

  test('a version 1 save looks every pack up again', () async {
    final store = _MemoryStore();
    final td = _FakeTd();
    final first = await _service(td, store: store).openGlobalScanner();
    await first.loadMore();
    await first.settle();
    final state = first.toJson()
      ..['version'] = 1
      ..['unresolvableSets'] = [20]
      ..remove('packs');
    await store.write(777, state);

    final reopened = await _service(td, store: store).openGlobalScanner();
    await reopened.resolveKnown();
    await reopened.settle();
    expect(_uses(reopened.stickers), {10: 2, 20: 1, 30: 1});
  });

  test('rate limits are read from either TDLib wording', () {
    expect(
      rateLimitRetryAfter(
        TdError({'code': 429, 'message': 'Too Many Requests: retry after 7'}),
      ),
      const Duration(seconds: 7),
    );
    expect(
      rateLimitRetryAfter(TdError({'code': 420, 'message': 'FLOOD_WAIT_12'})),
      const Duration(seconds: 12),
    );
    expect(
      rateLimitRetryAfter(TdError({'code': 400, 'message': 'BAD'})),
      isNull,
    );
  });

  test('saves never overlap, and the newest state is written last', () async {
    final store = _SlowStore();
    final td = _FakeTd();
    final scanner = await _service(td, store: store).openGlobalScanner();
    final first = scanner.save(force: true);
    await scanner.loadMore();
    await scanner.settle();
    final second = scanner.save(force: true);
    store.release();
    await Future.wait([first, second]);
    expect(store.maxConcurrent, 1);
    expect(store.written.last['scannedMessages'], 6);
  });

  test('a resumed older walk skips what a newer walk already read', () async {
    final store = _MemoryStore();
    final td = _FakeTd();
    // Session one: stop after chat 1's newest message, before chat 2 is
    // read (its first page may be fetched ahead, but nothing is counted).
    final first = await _service(
      td,
      store: store,
      now: 1000,
    ).openGlobalScanner();
    await first.loadMore(messages: 1);
    await first.settle();
    await first.save(force: true);

    // 250 new stickers in chat 2 after session one began.
    td.history[2]!.insertAll(0, [
      for (var i = 249; i >= 0; i--) _sticker(1000 + i, 1100 + i, 20),
    ]);
    td.delivered.clear();
    final reopened = await _service(
      td,
      store: store,
      now: 2000,
    ).openGlobalScanner();
    await reopened.resolveKnown();
    while (!reopened.exhausted) {
      await reopened.loadMore();
    }
    await reopened.settle();

    // Every message counted exactly once across both sessions.
    expect(_uses(reopened.stickers), {10: 2, 20: 251, 30: 1});
    expect(reopened.scannedMessages, 256);
    // The older walk resumed chat 2 from the top, hit the newer walk's
    // range on its first message and jumped below it: the 250 new messages
    // were read once, not twice.
    final chat2 = td.delivered[2]!;
    final repeats = chat2.length - chat2.toSet().length;
    expect(repeats, 0);
    expect(chat2.length, lessThan(260));
  });

  test('a long chat is indexed as one range', () async {
    final td = _longChat(1000);
    final scanner = _service(td).chatScanner(9);
    while (!scanner.exhausted) {
      await scanner.loadMore();
    }
    expect(scanner.scannedMessages, 1000);
    expect(scanner.readRangeCount, 1);
  });

  test(
    'a save asked for mid-batch waits for the batch to be counted',
    () async {
      final store = _MemoryStore();
      final td = _FakeTd();
      final scanner = await _service(td, store: store).openGlobalScanner();
      final loading = scanner.loadMore(messages: 3);
      // The batch is still reading; this save must not record half of it.
      await scanner.save(force: true);
      expect(store.saved, isEmpty);
      await loading;
      await scanner.settle();
      await Future<void>.delayed(Duration.zero);
      final saved = jsonDecode(store.saved[777]!) as Map<String, dynamic>;
      expect(saved['scannedMessages'], 3);
    },
  );

  test('each account keeps its own scan', () async {
    final store = _MemoryStore();
    final td = _FakeTd();
    final first = await _service(td, store: store).openGlobalScanner();
    await first.loadMore();
    await first.settle();
    await first.save(force: true);

    td.userId = 888;
    final other = await _service(td, store: store).openGlobalScanner();
    await other.resolveKnown();
    await other.settle();
    expect(other.scannedMessages, 0);
    expect(other.stickers, isEmpty);
    expect(store.saved.keys, [777]);
  });

  test('the store writes one file per account and reads it back', () async {
    final dir = await Directory.systemTemp.createTemp('sticker-finder-test');
    addTearDown(() => dir.delete(recursive: true));
    final store = ChatPackScanStore(supportDirectory: () async => dir);
    await store.write(777, {'version': 1, 'top': 5});
    expect(await store.read(777), {'version': 1, 'top': 5});
    expect(await store.read(888), isNull);
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
    expect(files, hasLength(1));
    expect(files.single, isNot(contains('777')), reason: 'hashed owner');
  });

  test('plain animated emoji do not surface the built-in emoji set', () {
    final refs = ChatPackReferences()
      ..addMessage({
        'content': {
          '@type': 'messageAnimatedEmoji',
          'animated_emoji': {
            'sticker': {
              'set_id': '99',
              'full_type': {'@type': 'stickerFullTypeRegular'},
            },
          },
        },
      })
      ..addMessage({
        'content': {
          '@type': 'messageAnimatedEmoji',
          'animated_emoji': {
            'sticker': {
              'set_id': '50',
              'full_type': {
                '@type': 'stickerFullTypeCustomEmoji',
                'custom_emoji_id': '501',
              },
            },
          },
        },
      });
    expect(refs.stickerSets, isEmpty);
    expect(refs.customEmoji, {501: 1});
  });

  test('sorts by each key in both directions, stable on ties', () {
    final packs = [
      _pack(1, 'beta', uses: 2, lastUsed: 10, items: 5),
      _pack(2, 'Alpha', uses: 5, lastUsed: 30, items: 5),
      _pack(3, 'gamma', uses: 2, lastUsed: 20, items: 9),
    ];
    List<int> ids(ChatPackSort sort, bool descending) => sortPacks(
      packs,
      sort,
      descending: descending,
    ).map((p) => p.id).toList();

    expect(ids(ChatPackSort.usage, true), [2, 1, 3]);
    expect(ids(ChatPackSort.usage, false), [1, 3, 2]);
    expect(ids(ChatPackSort.recent, true), [2, 3, 1]);
    expect(ids(ChatPackSort.name, false), [2, 1, 3]);
    expect(ids(ChatPackSort.name, true), [3, 1, 2]);
    expect(ids(ChatPackSort.size, true), [3, 1, 2]);
  });

  test('filters by title and by not-added', () {
    final packs = [
      _pack(1, 'Duck Stickers'),
      _pack(2, 'Cats', installed: true),
      _pack(3, 'duckling'),
    ];
    expect(filterPacks(packs, query: ' DUCK ').map((p) => p.id), [1, 3]);
    expect(filterPacks(packs, onlyMissing: true).map((p) => p.id), [1, 3]);
    expect(
      filterPacks(packs, query: 'cat', onlyMissing: true).map((p) => p.id),
      isEmpty,
    );
  });

  testWidgets('phone layout: previews, Add (N), tabs, add all', (tester) async {
    final td = _FakeTd();
    await tester.pumpWidget(
      await _app(ChatStickerPacksView(chatId: 2, service: _service(td))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pack 20'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget, reason: 'set 20 is installed');
    final stats = find.byKey(const ValueKey('chat-sticker-pack-stats-20'));
    expect(
      find.descendant(of: stats, matching: find.text('1')),
      findsNWidgets(2),
      reason: 'one use by one person',
    );
    expect(
      tester.getBottomRight(stats).dy,
      lessThan(tester.getTopLeft(find.text('Added')).dy),
      reason: 'counts sit above the button',
    );
    expect(find.textContaining(RegExp(r'used \d')), findsNothing);
    expect(find.text('No older messages'), findsOneWidget);
    expect(find.byType(SliverGrid), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-sticker-packs-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('Pack 50'), findsOneWidget);
    expect(find.text('Pack 60'), findsOneWidget);
    expect(find.text('Add (${60 % 17})'), findsOneWidget);
    expect(find.text('😀'), findsWidgets, reason: 'preview strip renders');

    await tester.tap(find.byKey(const ValueKey('chat-sticker-pack-add-50')));
    await tester.pumpAndSettle();
    expect(td.installed, contains(50));

    await tester.tap(find.byKey(const ValueKey('chat-sticker-packs-add-all')));
    await tester.pumpAndSettle();
    expect(td.installed, contains(60));
    expect(find.text('Added'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('filter, not-added and sort controls reshape the list', (
    tester,
  ) async {
    final td = _FakeTd();
    await tester.pumpWidget(
      await _app(ChatStickerPacksView(service: _service(td))),
    );
    await tester.pumpAndSettle();

    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(top('Pack 10'), lessThan(top('Pack 20')), reason: 'most used');

    await tester.tap(
      find.byKey(const ValueKey('chat-sticker-packs-sort-name')),
    );
    await tester.pumpAndSettle();
    expect(top('Pack 10'), lessThan(top('Pack 30')));

    // Tapping the active sort flips its direction.
    await tester.tap(
      find.byKey(const ValueKey('chat-sticker-packs-sort-name')),
    );
    await tester.pumpAndSettle();
    expect(top('Pack 30'), lessThan(top('Pack 10')));

    await tester.tap(
      find.byKey(const ValueKey('chat-sticker-packs-not-added')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pack 20'), findsNothing, reason: 'already installed');
    expect(find.text('Pack 10'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No packs match'), findsOneWidget);
  });

  testWidgets('global finder reads every chat, newest messages first', (
    tester,
  ) async {
    final td = _FakeTd();
    await tester.pumpWidget(
      await _app(ChatStickerPacksView(service: _service(td))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sticker & Emoji Finder'), findsOneWidget);
    expect(find.text('From your last 6 messages'), findsOneWidget);
    expect(find.text('Pack 30'), findsOneWidget, reason: 'archived chat');
  });

  testWidgets('a reopened finder shows the saved scan straight away', (
    tester,
  ) async {
    final store = _MemoryStore();
    final td = _FakeTd();
    await tester.pumpWidget(
      await _app(
        ChatStickerPacksView(
          key: const ValueKey('first'),
          service: _service(td, store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('From your last 6 messages'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    final reads = _historyReads(td);
    await tester.pumpWidget(
      await _app(
        ChatStickerPacksView(
          key: const ValueKey('second'),
          service: _service(td, store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('From your last 6 messages'), findsOneWidget);
    expect(find.text('Pack 30'), findsOneWidget);
    expect(
      _historyReads(td),
      reads,
      reason: 'same clock second: nothing newer to read',
    );
  });

  testWidgets('the scan keeps running until history runs out', (tester) async {
    final td = _longChat(1000);
    await tester.pumpWidget(
      await _app(ChatStickerPacksView(chatId: 9, service: _service(td))),
    );
    await tester.pumpAndSettle();
    // Three batches of 400 without any scrolling: every message, four per
    // set, so 250 packs.
    expect(find.text('From the last 1000 messages'), findsOneWidget);
    expect(find.text('250'), findsOneWidget, reason: 'sticker tab count');
    expect(
      find.byKey(const ValueKey('chat-sticker-packs-pause')),
      findsNothing,
      reason: 'nothing left to pause',
    );
  });

  testWidgets('pausing stops the scan and resuming continues it', (
    tester,
  ) async {
    final td = _longChat(4000, withPacks: false);
    await tester.pumpWidget(
      await _app(ChatStickerPacksView(chatId: 9, service: _service(td))),
    );
    // Let the first batch land, then pause mid-scan.
    final pause = find.byKey(const ValueKey('chat-sticker-packs-pause'));
    for (var i = 0; i < 50 && pause.evaluate().isEmpty; i++) {
      await tester.pump();
    }
    expect(_historyReads(td), lessThan(40), reason: 'still mid-scan');
    await tester.tap(pause);
    await tester.pumpAndSettle();
    final paused = _historyReads(td);
    expect(find.text('Resume scanning'), findsOneWidget);
    expect(find.text('No older messages'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(_historyReads(td), paused, reason: 'no reads while paused');

    await tester.tap(find.byKey(const ValueKey('chat-sticker-packs-resume')));
    await tester.pumpAndSettle();
    expect(_historyReads(td), greaterThan(paused));
    expect(find.text('From the last 4000 messages'), findsOneWidget);
    expect(find.text('No older messages'), findsOneWidget);
  });

  testWidgets('wide desktop layout uses two compact columns', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    try {
      final td = _FakeTd();
      await tester.pumpWidget(
        await _app(ChatStickerPacksView(chatId: 1, service: _service(td))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('chat-sticker-pack-10')))
            .height,
        58,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<Widget> _app(Widget home) async {
  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  return ChangeNotifierProvider<ThemeController>.value(
    value: theme,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}
