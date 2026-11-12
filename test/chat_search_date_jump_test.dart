import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_search_bar.dart';
import 'package:mithka/chat/chat_message_search_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';

/// The search header's calendar affordance: pick a date, land on the first
/// message of that day via `getChatMessageByDate` + backward `getChatHistory`
/// within the picked day's `[dayStart, dayEnd)` bounds. The jump is navigation,
/// not a search hit — the controller only resolves the message, and the caller
/// decides how the transcript moves. A lookup or picker sheet must not survive
/// its session: close/reopen, a newer pick, disposal, or a results restart
/// abandons it silently on both success and error paths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late List<Map<String, dynamic>> requests;
  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          return handler(request);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    requests = [];
    handler = (request) async => <String, dynamic>{'@type': 'ok'};
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  Completer<Map<String, dynamic>> heldLookup() {
    final completer = Completer<Map<String, dynamic>>();
    handler = (request) async {
      if (request['@type'] == 'getChatMessageByDate') {
        return completer.future;
      }
      if (request['@type'] == 'getChatHistory') {
        // A real TDLib answers a walk below the only message with an empty
        // page (end of history), not with the same message again.
        return const <String, dynamic>{
          '@type': 'messages',
          'total_count': 0,
          'messages': <Map<String, dynamic>>[],
        };
      }
      return const <String, dynamic>{'@type': 'ok'};
    };
    return completer;
  }

  testWidgets('a lookup held across close/reopen never lands', (tester) async {
    final held = heldLookup();
    final controller = ChatMessageSearchController(chatId: _chatId);
    addTearDown(controller.dispose);
    var jumps = 0;
    await tester.pumpWidget(_harness(controller, onJump: (_) => jumps++));

    await tester.tap(find.byKey(const ValueKey('chatSearchDateJump')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
    await tester.pump(); // Lookup in flight; the dialog is closed.

    // Close and reopen the same search before the response arrives.
    controller.close();
    controller.open();
    await tester.pump();

    final now = DateTime.now();
    final todayNoon =
        DateTime(now.year, now.month, now.day, 12).millisecondsSinceEpoch ~/
        1000;
    held.complete(_message(1200, date: todayNoon));
    await tester.pumpAndSettle();

    expect(jumps, 0);
    expect(
      find.text(AppStrings.t(AppStringKeys.chatSearchNoMessagesAtDate)),
      findsNothing,
    );
  });

  testWidgets('a newer pick supersedes the older held lookup', (tester) async {
    final first = heldLookup();
    final controller = ChatMessageSearchController(chatId: _chatId);
    addTearDown(controller.dispose);
    final landed = <int>[];
    await tester.pumpWidget(
      _harness(controller, onJump: (m) => landed.add(m.id)),
    );

    await tester.tap(find.byKey(const ValueKey('chatSearchDateJump')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
    await tester.pump();

    // Second pick while the first is still held: it supersedes the first.
    await tester.tap(find.byKey(const ValueKey('chatSearchDateJump')));
    await tester.pumpAndSettle();
    final second = heldLookup();
    await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
    await tester.pump();

    final now = DateTime.now();
    final todayNoon =
        DateTime(now.year, now.month, now.day, 12).millisecondsSinceEpoch ~/
        1000;
    first.complete(_message(1200, date: todayNoon));
    await tester.pumpAndSettle();
    second.complete(_message(1300, date: todayNoon));
    await tester.pumpAndSettle();

    expect(landed, [_packed(1300)]);
    expect(
      find.text(AppStrings.t(AppStringKeys.chatSearchNoMessagesAtDate)),
      findsNothing,
    );
  });

  test(
    'day-boundary contract: previous-day-only and exact next-midnight return null; multi-message day returns the first message',
    () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      controller.open();

      final pickedDay = DateTime(2026, 10, 10);
      final prevDayMsgDate =
          DateTime(2026, 10, 9, 23, 59, 59).millisecondsSinceEpoch ~/ 1000;
      final morningMsgDate =
          DateTime(2026, 10, 10, 8).millisecondsSinceEpoch ~/ 1000;
      final eveningMsgDate =
          DateTime(2026, 10, 10, 23).millisecondsSinceEpoch ~/ 1000;
      final nextMidnightDate =
          DateTime(2026, 10, 11).millisecondsSinceEpoch ~/ 1000;

      // Case 1: Empty picked day with only a previous-day message -> null.
      handler = (request) async => switch (request['@type']) {
        'getChatMessageByDate' => _message(900, date: prevDayMsgDate),
        _ => const {'@type': 'ok'},
      };
      final previousOnly = await controller.messageAtDate(pickedDay);
      expect(previousOnly.current, isTrue);
      expect(previousOnly.emptyDay, isTrue);
      expect(previousOnly.message, isNull);

      // Case 2: A message exactly at next-day midnight is outside the picked
      // day -> null even if a transport returned it.
      handler = (request) async => switch (request['@type']) {
        'getChatMessageByDate' => _message(2000, date: nextMidnightDate),
        _ => const {'@type': 'ok'},
      };
      final nextMidnight = await controller.messageAtDate(pickedDay);
      expect(nextMidnight.current, isTrue);
      expect(nextMidnight.emptyDay, isTrue);
      expect(nextMidnight.message, isNull);

      // Case 3: Messages at 08:00 (id 1001) and 23:00 (id 1002) on the picked
      // day, plus an older previous-day message (id 900). A faithful TDLib
      // transport returns the 23:00 message for getChatMessageByDate, and the
      // backward walk — inclusive bound at offset 0 — reaches the 08:00 first
      // message of the day.
      final allMessages = <Map<String, dynamic>>[
        _message(2000, date: nextMidnightDate),
        _message(1002, date: eveningMsgDate),
        _message(1001, date: morningMsgDate),
        _message(900, date: prevDayMsgDate),
      ];
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            final maxDate = request['date'] as int;
            for (final m in allMessages) {
              if ((m['date'] as int) <= maxDate) return m;
            }
            throw TdError(<String, dynamic>{
              '@type': 'error',
              'code': 404,
              'message': 'NOT_FOUND',
            });
          case 'getChatHistory':
            _enforceHistoryContract(request);
            return _historyPage(
              allMessages.reversed.toList(growable: false),
              request['from_message_id'] as int,
              request['limit'] as int,
            );
          default:
            return const {'@type': 'ok'};
        }
      };

      final multiMessage = await controller.messageAtDate(pickedDay);
      expect(multiMessage.current, isTrue);
      expect(multiMessage.emptyDay, isFalse);
      expect(multiMessage.message?.id, _packed(1001));
      expect(multiMessage.message?.date, morningMsgDate);

      // Case 4: Single-message day. The walk asks from the anchor itself — not
      // `anchor.id - 1`, which is not a message id — and the previous-day
      // message comes back in that same page, proving the boundary in one call.
      requests.clear();
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return _message(1001, date: morningMsgDate);
          case 'getChatHistory':
            _enforceHistoryContract(request);
            return _historyPage(
              [
                _message(1001, date: morningMsgDate),
                _message(900, date: prevDayMsgDate),
              ],
              request['from_message_id'] as int,
              request['limit'] as int,
            );
          default:
            return const {'@type': 'ok'};
        }
      };
      final singleMessageDay = await controller.messageAtDate(pickedDay);
      expect(singleMessageDay.current, isTrue);
      expect(singleMessageDay.message?.id, _packed(1001));
      final singleDayHistoryCalls = requests
          .where((r) => r['@type'] == 'getChatHistory')
          .toList();
      expect(singleDayHistoryCalls, hasLength(1));
      expect(singleDayHistoryCalls.single['from_message_id'], _packed(1001));
      expect(singleDayHistoryCalls.single['offset'], 0);
      _expectPackedCursors(singleDayHistoryCalls);

      // Case 5: Short pages. TDLib chooses the page length, so a responder
      // that returns at most two messages per call must still be walked to the
      // day's first message: each page echoes its cursor and hands back one
      // strictly older id, and the last page (the day's first message plus the
      // previous-day one) proves the boundary.
      final twelveSameDayMessages = <Map<String, dynamic>>[
        for (var i = 12; i >= 1; i--)
          _message(1000 + i, date: morningMsgDate + i * 60),
        _message(900, date: prevDayMsgDate),
      ];
      requests.clear();
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return twelveSameDayMessages.first;
          case 'getChatHistory':
            _enforceHistoryContract(request);
            // TDLib chooses the page length: this responder answers with two
            // messages, the newest at or below the bound and the one before it.
            return _historyPage(
              twelveSameDayMessages.reversed.toList(growable: false),
              request['from_message_id'] as int,
              2,
            );
          default:
            return const {'@type': 'ok'};
        }
      };
      final multiSinglePage = await controller.messageAtDate(pickedDay);
      expect(multiSinglePage.current, isTrue);
      expect(multiSinglePage.message?.id, _packed(1001));
      final shortPageCalls = requests
          .where((r) => r['@type'] == 'getChatHistory')
          .toList();
      // ids 1012<<20 … 1001<<20, one page per cursor: the inclusive echo means
      // each two-message page only advances by one id.
      expect(shortPageCalls, hasLength(12));
      expect(shortPageCalls.every((r) => r['offset'] == 0), isTrue);
      _expectPackedCursors(shortPageCalls);
    },
  );

  test(
    'a short cursor-only page proves nothing: retries advance, then a stalled walk fails closed',
    () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      controller.open();

      final pickedDay = DateTime(2026, 10, 10);
      final dayStart = DateTime(2026, 10, 10).millisecondsSinceEpoch ~/ 1000;
      // The reviewer's reproduction: three same-day messages, wire ids
      // 1<<20..3<<20, anchoring at 3<<20. TDLib may answer the first request
      // with the cursor's own message alone even though older messages exist,
      // so the walk must retry the same cursor instead of reading the short
      // page as the end of history.
      final day = <Map<String, dynamic>>[
        _message(3, date: dayStart + 3 * 3600),
        _message(2, date: dayStart + 2 * 3600),
        _message(1, date: dayStart + 3600),
      ];
      var historyCalls = 0;
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return day.first; // 3<<20
          case 'getChatHistory':
            _enforceHistoryContract(request);
            historyCalls++;
            // First response: the anchor alone, as TDLib is allowed to do.
            if (historyCalls == 1) {
              return {
                '@type': 'messages',
                'total_count': 1,
                'messages': [day.first],
              };
            }
            return _historyPage(
              day.reversed.toList(growable: false),
              request['from_message_id'] as int,
              request['limit'] as int,
            );
          default:
            return const {'@type': 'ok'};
        }
      };
      final retried = await controller.messageAtDate(pickedDay);
      expect(retried.current, isTrue);
      expect(retried.emptyDay, isFalse);
      expect(retried.message?.id, _packed(1));
      final retryCalls = requests
          .where((r) => r['@type'] == 'getChatHistory')
          .toList();
      // The same cursor is asked again — never a derived id.
      expect(retryCalls.take(2).map((r) => r['from_message_id']), [
        _packed(3),
        _packed(3),
      ]);
      _expectPackedCursors(retryCalls);

      // A responder that only ever echoes the cursor never proves the day's
      // first message: the walk fails closed instead of reporting the anchor.
      historyCalls = 0;
      var echoCalls = 0;
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return day.first;
          case 'getChatHistory':
            _enforceHistoryContract(request);
            echoCalls++;
            return {
              '@type': 'messages',
              'total_count': 1,
              'messages': [day.first],
            };
          default:
            return const {'@type': 'ok'};
        }
      };
      final stalled = await controller.messageAtDate(pickedDay);
      expect(stalled.current, isTrue);
      expect(stalled.emptyDay, isFalse);
      expect(
        stalled.message,
        isNull,
        reason: 'the anchor was never proven first',
      );
      expect(echoCalls, greaterThan(1));
      expect(echoCalls, lessThanOrEqualTo(3));

      // Reaching server message id 1 does prove it, whatever the page length.
      final onlyFirstMessage = _message(1, date: dayStart + 600);
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return onlyFirstMessage;
          case 'getChatHistory':
            _enforceHistoryContract(request);
            return _historyPage(
              [onlyFirstMessage],
              request['from_message_id'] as int,
              request['limit'] as int,
            );
          default:
            return const {'@type': 'ok'};
        }
      };
      final proven = await controller.messageAtDate(pickedDay);
      expect(proven.current, isTrue);
      expect(proven.emptyDay, isFalse);
      expect(proven.message?.id, _packed(1));

      // An empty history page is the other proof: nothing older exists.
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return day.first;
          case 'getChatHistory':
            _enforceHistoryContract(request);
            return {
              '@type': 'messages',
              'total_count': 0,
              'messages': <Map<String, dynamic>>[],
            };
          default:
            return const {'@type': 'ok'};
        }
      };
      final emptyPage = await controller.messageAtDate(pickedDay);
      expect(emptyPage.current, isTrue);
      expect(emptyPage.emptyDay, isFalse);
      expect(emptyPage.message?.id, _packed(3));
    },
  );
}

const _chatId = -100200;

/// TDLib packs a server message id as `server_id << 20`: the low 20 bits are
/// the message type, so a plain server id has them all zero. `MessageId`'s
/// validity check accepts exactly three shapes there — server (0), yet-unsent
/// (1) and local (2) — and `getChatHistory` answers everything else with
/// `400 Invalid value of parameter from_message_id specified`.
const int _serverIdShift = 20;
const int _typeBitsMask = (1 << _serverIdShift) - 1;

/// The wire id TDLib uses for server message [serverId].
int _packed(int serverId) => serverId << _serverIdShift;

/// `MessageId::is_valid`, as the fake transport applies it: a positive id whose
/// low 20 type bits are a known message type. `_packed(3) - 1` (low bits 7) and
/// any other derived id fails here, exactly as the pinned TDLib fails it.
bool _isValidMessageId(int id) {
  if (id <= 0) return false;
  final type = id & _typeBitsMask;
  return type == 0 || type == 1 || type == 2;
}

/// Enforces TDLib's `getChatHistory` request contract inside the fake
/// transport:
/// - `offset` must be non-positive; the official implementation answers a
///   positive offset with `400 Parameter offset must be non-positive`.
/// - `from_message_id` must pass `MessageId::is_valid`; the official
///   implementation answers a derived id such as `anchor.id - 1` with
///   `400 Invalid value of parameter from_message_id specified`.
///
/// A regression back to an `offset: 1` walk or to `id ± 1` arithmetic must
/// fail here instead of silently "working" against a lenient fake.
void _enforceHistoryContract(Map<String, dynamic> request) {
  final offset = (request['offset'] as int?) ?? 0;
  if (offset > 0) {
    throw TdError(<String, dynamic>{
      '@type': 'error',
      'code': 400,
      'message': 'Parameter offset must be non-positive',
    });
  }
  final fromMessageId = (request['from_message_id'] as int?) ?? 0;
  if (!_isValidMessageId(fromMessageId)) {
    throw TdError(<String, dynamic>{
      '@type': 'error',
      'code': 400,
      'message': 'Invalid value of parameter from_message_id specified',
    });
  }
}

/// Every `getChatHistory` cursor must satisfy `MessageId::is_valid`, carry no
/// low type bits (a plain server id), and arrive at `offset: 0`. A regression
/// to `anchor.id - 1` / `oldest.id - 1` fails the first two checks.
void _expectPackedCursors(List<Map<String, dynamic>> calls) {
  expect(calls, isNotEmpty);
  for (final call in calls) {
    final cursor = call['from_message_id'] as int;
    expect(cursor & _typeBitsMask, 0, reason: 'derived id $cursor was sent');
    expect(_isValidMessageId(cursor), isTrue, reason: 'invalid id $cursor');
    expect(call['offset'], 0);
  }
}

/// A faithful `getChatHistory` page: `from_message_id` is an inclusive upper
/// bound — at offset 0 its own message is the first entry — messages come back
/// newest→oldest, and TDLib, not the caller, decides the page length, so the
/// slice can be shorter than [limit].
Map<String, dynamic> _historyPage(
  List<Map<String, dynamic>> oldestFirst,
  int fromMessageId,
  int limit,
) {
  final page = oldestFirst.reversed
      .where((message) => (message['id'] as int) <= fromMessageId)
      .take(limit)
      .toList(growable: false);
  return {'@type': 'messages', 'total_count': page.length, 'messages': page};
}

/// A `message` object carrying a real packed id: [serverId] is the server-side
/// message id, packed the way TDLib packs it (`serverId << 20`).
Map<String, dynamic> _message(int serverId, {required int date}) => {
  '@type': 'message',
  'id': _packed(serverId),
  'chat_id': _chatId,
  'date': date,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 55},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'a needle in message $serverId',
      'entities': <Map<String, dynamic>>[],
    },
  },
};

Widget _harness(
  ChatMessageSearchController controller, {
  required ValueChanged<dynamic> onJump,
}) {
  // A search session in progress: the date lookup only resolves while the
  // session is open, as it does in production.
  controller.open();
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppColors.light]),
    home: Scaffold(
      body: ChatSearchHeaderBar(
        controller: controller,
        height: 48,
        onClose: () {},
        onJumpToMessage: onJump,
      ),
    ),
  );
}
