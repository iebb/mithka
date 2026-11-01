import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_search_bar.dart';
import 'package:mithka/chat/chat_message_search_controller.dart';
import 'package:mithka/components/app_date_picker.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
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

  testWidgets('the calendar resolves the picked day and hands it over', (
    tester,
  ) async {
    final pickedDay = _pickableNinth();
    final msgTime =
        DateTime(
          pickedDay.year,
          pickedDay.month,
          9,
          12,
        ).millisecondsSinceEpoch ~/
        1000;
    handler = (request) async => switch (request['@type']) {
      'getChatMessageByDate' => _message(1200, date: msgTime),
      'getChatHistory' => {
        '@type': 'messages',
        'total_count': 0,
        'messages': <Map<String, dynamic>>[],
      },
      _ => const {},
    };
    final controller = ChatMessageSearchController(chatId: _chatId);
    addTearDown(controller.dispose);
    ChatMessage? jumped;
    await tester.pumpWidget(_harness(controller, onJump: (m) => jumped = m));

    await tester.tap(find.byKey(const ValueKey('chatSearchDateJump')));
    await tester.pumpAndSettle();

    // Pick a specific day in the owned grid — the 9th, inside the allowed
    // range (the picker dims days after today).
    await _showMonthOf(tester, pickedDay);
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
    await tester.pumpAndSettle();

    final byDate = requests
        .where((request) => request['@type'] == 'getChatMessageByDate')
        .toList();
    expect(byDate, hasLength(1));
    // Inclusive last second of the picked day (23:59:59 local):
    // DateTime(year, month, 10) - 1s.
    final stamp = byDate.single['date'] as int;
    final expectedEndExclusive =
        DateTime(
          pickedDay.year,
          pickedDay.month,
          pickedDay.day + 1,
        ).millisecondsSinceEpoch ~/
        1000;
    expect(stamp, expectedEndExclusive - 1);
    final boundary = DateTime.fromMillisecondsSinceEpoch(stamp * 1000);
    expect(boundary.year, pickedDay.year);
    expect(boundary.month, pickedDay.month);
    expect(boundary.day, 9);
    expect(boundary.hour, 23);
    expect(boundary.minute, 59);
    expect(boundary.second, 59);
    expect(jumped?.id, _packed(1200));
  });

  testWidgets('a date with no messages toasts instead of jumping', (
    tester,
  ) async {
    handler = (request) async => switch (request['@type']) {
      'getChatMessageByDate' => throw TdError(<String, dynamic>{
        '@type': 'error',
        'code': 404,
        'message': 'NOT_FOUND',
      }),
      _ => <String, dynamic>{'@type': 'ok'},
    };
    final controller = ChatMessageSearchController(chatId: _chatId);
    addTearDown(controller.dispose);
    var jumped = 0;
    await tester.pumpWidget(_harness(controller, onJump: (_) => jumped++));

    await tester.tap(find.byKey(const ValueKey('chatSearchDateJump')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(jumped, 0);
    expect(
      find.text(AppStrings.t(AppStringKeys.chatSearchNoMessagesAtDate)),
      findsOneWidget,
    );
    // The toast holds a ~1.4s hold timer plus a fade; drain both.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed history walk toasts a failure, not an empty day', (
    tester,
  ) async {
    final pickedDay = _pickableNinth();
    final msgTime =
        DateTime(
          pickedDay.year,
          pickedDay.month,
          9,
          12,
        ).millisecondsSinceEpoch ~/
        1000;
    handler = (request) async => switch (request['@type']) {
      'getChatMessageByDate' => _message(1200, date: msgTime),
      'getChatHistory' => throw TdError(<String, dynamic>{
        '@type': 'error',
        'code': 500,
        'message': 'HISTORY_FETCH_FAILED',
      }),
      _ => <String, dynamic>{'@type': 'ok'},
    };
    final controller = ChatMessageSearchController(chatId: _chatId);
    addTearDown(controller.dispose);
    var jumped = 0;
    await tester.pumpWidget(_harness(controller, onJump: (_) => jumped++));

    await tester.tap(find.byKey(const ValueKey('chatSearchDateJump')));
    await tester.pumpAndSettle();
    await _showMonthOf(tester, pickedDay);
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(jumped, 0);
    expect(
      find.text(AppStrings.t(AppStringKeys.chatSearchDateJumpFailed)),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.t(AppStringKeys.chatSearchNoMessagesAtDate)),
      findsNothing,
    );
    // Drain the toast's hold timer and fade.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

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

  testWidgets(
    'a held 404 lookup across close/reopen returns current:false and never toasts',
    (tester) async {
      final held = heldLookup();
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      var jumps = 0;
      await tester.pumpWidget(_harness(controller, onJump: (_) => jumps++));

      await tester.tap(find.byKey(const ValueKey('chatSearchDateJump')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
      await tester.pump();

      controller.close();
      controller.open();
      await tester.pump();

      held.completeError(
        TdError(<String, dynamic>{
          '@type': 'error',
          'code': 404,
          'message': 'NOT_FOUND',
        }),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(jumps, 0);
      expect(
        find.text(AppStrings.t(AppStringKeys.chatSearchNoMessagesAtDate)),
        findsNothing,
      );

      // Direct controller boundary check: held lookup + close/open + 404 ->
      // current is false.
      final directHeld = heldLookup();
      final future = controller.messageAtDate(DateTime(2026, 10, 13));
      controller.close();
      controller.open();
      directHeld.completeError(
        TdError(<String, dynamic>{
          '@type': 'error',
          'code': 404,
          'message': 'NOT_FOUND',
        }),
      );
      final outcome = await future;
      expect(outcome.current, isFalse);
      expect(outcome.message, isNull);
    },
  );

  testWidgets(
    'closing and reopening search while the date picker is open drops the pick',
    (tester) async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      var jumps = 0;
      await tester.pumpWidget(_harness(controller, onJump: (_) => jumps++));

      await tester.tap(find.byKey(const ValueKey('chatSearchDateJump')));
      await tester.pumpAndSettle();

      // Replace the search session while the modal picker is still on screen.
      controller.close();
      controller.open();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
      await tester.pumpAndSettle();

      expect(
        requests.where((r) => r['@type'] == 'getChatMessageByDate'),
        isEmpty,
      );
      expect(jumps, 0);
    },
  );

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
    'packed ids: the anchor itself is the first cursor, never anchor - 1',
    () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      controller.open();

      final pickedDay = DateTime(2026, 10, 10);
      final dayStart = DateTime(2026, 10, 10).millisecondsSinceEpoch ~/ 1000;
      // The reviewer's reproduction: three same-day messages whose server ids are
      // 1, 2 and 3, i.e. wire ids 1<<20, 2<<20 and 3<<20. Anchoring at 3<<20 and
      // asking from 3<<20 - 1 sends 3145727 (low type bits 7), which the pinned
      // TDLib rejects with 400 — the jump must resolve 1<<20 instead.
      final day = <Map<String, dynamic>>[
        _message(3, date: dayStart + 3 * 3600),
        _message(2, date: dayStart + 2 * 3600),
        _message(1, date: dayStart + 3600),
      ];
      expect(day.first['id'], 3145728);
      expect((day.first['id'] as int) - 1, 3145727);
      expect(_isValidMessageId(3145727), isFalse);

      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return day.first; // 3<<20, the day's latest message
          case 'getChatHistory':
            _enforceHistoryContract(request);
            return _historyPage(
              day.reversed.toList(growable: false),
              request['from_message_id'] as int,
              request['limit'] as int,
            );
          default:
            return const {'@type': 'ok'};
        }
      };

      final result = await controller.messageAtDate(pickedDay);
      expect(result.current, isTrue);
      expect(result.emptyDay, isFalse);
      expect(result.message?.id, _packed(1));
      expect(result.message?.date, dayStart + 3600);
      final calls = requests
          .where((r) => r['@type'] == 'getChatHistory')
          .toList();
      // The whole day fits in one page and reaches server id 1, which proves
      // nothing older exists — so one call suffices and the cursor is the
      // anchor itself, never `anchor.id - 1`.
      expect(calls.map((r) => r['from_message_id']), [_packed(3)]);
      expect(calls.map((r) => r['offset']), [0]);
    },
  );

  test(
    'the transport contract mirrors MessageId::is_valid and non-positive offset',
    () {
      // A plain server id has the low 20 type bits clear. Yet-unsent (1) and
      // local (2) ids are valid forms too; every other low-bit pattern is not.
      expect(_packed(3), 3145728);
      expect(_isValidMessageId(_packed(3)), isTrue);
      expect(_isValidMessageId(_packed(3) | 1), isTrue);
      expect(_isValidMessageId(_packed(3) | 2), isTrue);
      expect(_isValidMessageId(_packed(3) - 1), isFalse);
      expect(_isValidMessageId((_packed(3) - 1) | 7), isFalse);
      expect(_isValidMessageId(_packed(3) | (1 << 19)), isFalse);
      expect(_isValidMessageId(1 << 19), isFalse);
      expect(_isValidMessageId(0), isFalse);
      expect(_isValidMessageId(-1), isFalse);

      // The fake transport raises TDLib's exact errors, so a regression to
      // `anchor.id - 1` cannot pass silently against a lenient fake.
      expect(
        () => _enforceHistoryContract({
          'from_message_id': _packed(3) - 1,
          'offset': 0,
        }),
        throwsA(
          isA<TdError>().having(
            (error) => error.message,
            'message',
            'Invalid value of parameter from_message_id specified',
          ),
        ),
      );
      expect(
        () => _enforceHistoryContract({
          'from_message_id': _packed(3),
          'offset': 1,
        }),
        throwsA(
          isA<TdError>().having(
            (error) => error.message,
            'message',
            'Parameter offset must be non-positive',
          ),
        ),
      );
      for (final id in [_packed(3), _packed(3) | 1, _packed(3) | 2]) {
        _enforceHistoryContract({'from_message_id': id, 'offset': 0});
      }
    },
  );

  test(
    'busy-day and interrupted pagination: a proven first message vs an unresolved walk',
    () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      controller.open();

      final pickedDay = DateTime(2026, 10, 10);
      final dayStart = DateTime(2026, 10, 10).millisecondsSinceEpoch ~/ 1000;
      // 1,500 same-day messages, server ids 1..1500 (wire ids 1<<20..1500<<20),
      // all inside the picked day (spanning ~16.5 hours), oldest first: id 1 is
      // the day's first message.
      final busyDay = <Map<String, dynamic>>[
        for (var i = 1; i <= 1500; i++)
          _message(i, date: dayStart + (i - 1) * 40),
      ];
      final busyDayIds = busyDay.map((message) => message['id']).toSet();

      // Case A (busy day): a faithful responder with 100 entries per page
      // (TDLib returns newest→oldest, from_message_id inclusive at offset 0)
      // must walk all the way back to 1<<20, not stop at an intermediate
      // message after a fixed number of pages.
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return busyDay.last; // latest message at or before dayEnd - 1
          case 'getChatHistory':
            _enforceHistoryContract(request);
            return _historyPage(
              busyDay,
              request['from_message_id'] as int,
              request['limit'] as int,
            );
          default:
            return const {'@type': 'ok'};
        }
      };
      final busy = await controller.messageAtDate(pickedDay);
      expect(busy.current, isTrue);
      expect(busy.emptyDay, isFalse);
      expect(busy.message?.id, _packed(1)); // the actual first message
      // 100-message pages consume 99 new ids each (the cursor is echoed), so
      // 1500 -> 1401 -> … -> 15 takes 16 calls; the last page holds ids
      // 15..1 and reaching server id 1 proves the end of history.
      final busyHistoryCalls = requests
          .where((request) => request['@type'] == 'getChatHistory')
          .toList();
      expect(busyHistoryCalls, hasLength(16));
      expect(
        busyHistoryCalls.every((request) => request['offset'] == 0),
        isTrue,
      );
      // Every cursor is an id TDLib itself returned — never a derived id.
      expect(
        busyHistoryCalls.map((request) => request['from_message_id']),
        everyElement(isIn(busyDayIds)),
      );
      _expectPackedCursors(busyHistoryCalls);

      // Case A2 (short first page): TDLib chooses its own page length, so a
      // busy day whose pages hold only 3 entries must still be walked to its
      // real first message instead of being accepted as the day's start.
      final shortPageCalls = <Map<String, dynamic>>[];
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return busyDay.last;
          case 'getChatHistory':
            _enforceHistoryContract(request);
            shortPageCalls.add(Map<String, dynamic>.from(request));
            return _historyPage(busyDay, request['from_message_id'] as int, 3);
          default:
            return const {'@type': 'ok'};
        }
      };
      final shortFirstPage = await controller.messageAtDate(pickedDay);
      expect(shortFirstPage.current, isTrue);
      expect(shortFirstPage.message?.id, _packed(1));
      // 3-message pages consume 2 new ids each: 1500 -> 1498 -> … -> 2 takes
      // 750 calls, and that last page holds ids 2..1, so reaching server id 1
      // proves the end of history.
      expect(shortPageCalls, hasLength(750));
      expect(shortPageCalls.every((request) => request['offset'] == 0), isTrue);
      _expectPackedCursors(shortPageCalls);

      // Case B (interrupted pagination): a history exception mid-walk must NOT
      // report the partial earliest value as a successful first-message jump.
      var walkCalls = 0;
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return busyDay.last;
          case 'getChatHistory':
            _enforceHistoryContract(request);
            walkCalls++;
            if (walkCalls <= 2) {
              return _historyPage(
                busyDay,
                request['from_message_id'] as int,
                request['limit'] as int,
              );
            }
            throw TdError(<String, dynamic>{
              '@type': 'error',
              'code': 400,
              'message': 'HISTORY_FETCH_FAILED',
            });
          default:
            return const {'@type': 'ok'};
        }
      };
      final interrupted = await controller.messageAtDate(pickedDay);
      expect(interrupted.current, isTrue);
      expect(interrupted.emptyDay, isFalse);
      expect(interrupted.message, isNull);
      expect(walkCalls, 3); // two pages walked, the third failed

      // Case C (empty day): TDLib's NOT_FOUND is a real empty answer, not a
      // failed walk, so the result must set emptyDay rather than blame the
      // transport.
      handler = (request) async => switch (request['@type']) {
        'getChatMessageByDate' => throw TdError(<String, dynamic>{
          '@type': 'error',
          'code': 404,
          'message': 'NOT_FOUND',
        }),
        _ => const {'@type': 'ok'},
      };
      final empty = await controller.messageAtDate(pickedDay);
      expect(empty.current, isTrue);
      expect(empty.emptyDay, isTrue);
      expect(empty.message, isNull);
    },
  );

  test(
    'a short page advances the walk, but a page that ignores the bound is unresolved',
    () async {
      final controller = ChatMessageSearchController(chatId: _chatId);
      addTearDown(controller.dispose);
      controller.open();

      final pickedDay = DateTime(2026, 10, 10);
      final dayStart = DateTime(2026, 10, 10).millisecondsSinceEpoch ~/ 1000;
      final anchor = _message(500, date: dayStart + 12 * 3600);
      final older = _message(490, date: dayStart + 11 * 3600);
      final newer = _message(510, date: dayStart + 13 * 3600);

      // First page is short (2 of a requested 100) but moves backwards to 490;
      // TDLib chooses its own page length, so the walk must continue. The
      // second page returns 510 — newer than the 490 cursor, ignoring the
      // inclusive upper bound — which proves nothing about the start of the
      // day and must not be reported as such.
      var historyCalls = 0;
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return anchor;
          case 'getChatHistory':
            _enforceHistoryContract(request);
            historyCalls++;
            return {
              '@type': 'messages',
              'total_count': 1,
              'messages': [historyCalls == 1 ? older : newer],
            };
          default:
            return const {'@type': 'ok'};
        }
      };
      final stalled = await controller.messageAtDate(pickedDay);
      expect(stalled.current, isTrue);
      expect(stalled.emptyDay, isFalse);
      expect(stalled.message, isNull);
      // One advancing page, then three attempts at the 490 cursor before the
      // walk fails closed.
      expect(historyCalls, 4);

      // A page that only ever returns ids newer than the cursor stalls on the
      // first query: the anchor's message is not even echoed, so nothing
      // proves the day's beginning.
      historyCalls = 0;
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return anchor;
          case 'getChatHistory':
            _enforceHistoryContract(request);
            historyCalls++;
            return {
              '@type': 'messages',
              'total_count': 1,
              'messages': [newer],
            };
          default:
            return const {'@type': 'ok'};
        }
      };
      final outOfBound = await controller.messageAtDate(pickedDay);
      expect(outOfBound.current, isTrue);
      expect(outOfBound.emptyDay, isFalse);
      expect(outOfBound.message, isNull);
      // The page ignores the bound on every attempt, so the cursor is retried
      // before the walk fails closed.
      expect(historyCalls, 3);

      // A response without a message list is malformed, not proof that the
      // chat's history ended.
      handler = (request) async {
        switch (request['@type']) {
          case 'getChatMessageByDate':
            return anchor;
          case 'getChatHistory':
            _enforceHistoryContract(request);
            return const {'@type': 'messages', 'total_count': 3};
          default:
            return const {'@type': 'ok'};
        }
      };
      final malformed = await controller.messageAtDate(pickedDay);
      expect(malformed.current, isTrue);
      expect(malformed.emptyDay, isFalse);
      expect(malformed.message, isNull);
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

  testWidgets(
    'owned date picker revalidates selection on month paging and shorter months, and localizes weekdays',
    (tester) async {
      DateTime? picked;
      var completed = false;

      Future<void> openPicker({
        required DateTime initialDate,
        required DateTime firstDate,
        required DateTime lastDate,
        Locale locale = const Locale('zh', 'CN'),
      }) async {
        picked = null;
        completed = false;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppColors.light]),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: GestureDetector(
                    key: const ValueKey('openPicker'),
                    onTap: () {
                      unawaited(
                        showAppDatePicker(
                          context,
                          title: 'Jump to date',
                          initialDate: initialDate,
                          firstDate: firstDate,
                          lastDate: lastDate,
                        ).then((value) {
                          picked = value;
                          completed = true;
                        }),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('openPicker')));
        await tester.pumpAndSettle();
      }

      // 1. Seed/lastDate = 2026-10-13, page right once to 2026-11 (all future
      // days disabled), then tap Confirm without selecting: must NOT return
      // 2026-11-13.
      await openPicker(
        initialDate: DateTime(2026, 10, 13),
        firstDate: DateTime(2009, 8),
        lastDate: DateTime(2026, 10, 13),
      );
      // Localized Chinese weekday labels are rendered instead of hard-coded
      // English 'M'/'T'/'W'.
      expect(find.text('M'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('appDatePickerNextMonth')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      expect(picked, isNull);

      // Dismiss the open dialog before the next scenario.
      Navigator.of(
        tester.element(find.byKey(const ValueKey('appDatePickerConfirm'))),
      ).pop();
      await tester.pumpAndSettle();

      // 2. Shorter-month overflow: seed 2026-03-31, page left to 2026-02
      // (28 days), then Confirm: clamps to 2026-02-28 instead of overflowing
      // into March 3.
      await openPicker(
        initialDate: DateTime(2026, 3, 31),
        firstDate: DateTime(2009, 8),
        lastDate: DateTime(2026, 3, 31),
      );
      await tester.tap(find.byKey(const ValueKey('appDatePickerPrevMonth')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appDatePickerConfirm')));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(picked, DateTime(2026, 2, 28));
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

/// The most recent 9th the picker accepts. It dims days after today, so before
/// the 9th of this month the 9th comes from the previous month.
DateTime _pickableNinth() {
  final now = DateTime.now();
  return now.day >= 9
      ? DateTime(now.year, now.month, 9)
      : DateTime(now.year, now.month - 1, 9);
}

/// Pages the picker, which opens on the current month, back to [day]'s month.
Future<void> _showMonthOf(WidgetTester tester, DateTime day) async {
  final now = DateTime.now();
  if (day.year == now.year && day.month == now.month) return;
  await tester.tap(find.byKey(const ValueKey('appDatePickerPrevMonth')));
  await tester.pumpAndSettle();
}
