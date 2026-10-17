import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view.dart'
    show ChatView, clearChatMemoryCaches;
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

// The floating arrow at the transcript's bottom-right corner normally returns
// to the newest message. After a reply-quote (or View in Chat) jump it must
// instead return to the message the reader was looking at before that jump —
// and only while that origin is still meaningful.

const _chatId = -1000000007777;
const _messageCount = 40;

/// TDLib message ids are packed: `server_id << 20`.
int _mid(int serverId) => serverId << 20;

const _replyId = 36; // replies to 5
const _parentId = 5; // replies to 2
const _grandparentId = 2;

Map<String, dynamic> _message(int serverId, {int? replyTo}) => {
  '@type': 'message',
  'id': _mid(serverId),
  'chat_id': _chatId,
  'date': 1785862260 + serverId,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 2},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': 'Message $serverId\nsecond line\nthird line\nfourth line',
      'entities': <Map<String, dynamic>>[],
    },
  },
  if (replyTo != null)
    'reply_to': {
      '@type': 'messageReplyToMessage',
      'chat_id': _chatId,
      'message_id': _mid(replyTo),
      'quote': {
        '@type': 'textQuote',
        'text': {
          '@type': 'formattedText',
          'text': 'Quoted message $replyTo',
          'entities': <Map<String, dynamic>>[],
        },
        'position': 0,
        'is_manual': true,
      },
    },
};

/// Newest → oldest, the way TDLib answers `getChatHistory`.
List<Map<String, dynamic>> _history() => [
  for (var serverId = _messageCount; serverId >= 1; serverId--)
    _message(
      serverId,
      replyTo: serverId == _replyId
          ? _parentId
          : serverId == _parentId
          ? _grandparentId
          : null,
    ),
];

Map<String, dynamic> _chatJson() => {
  '@type': 'chat',
  'id': _chatId,
  'title': 'Jump origin group',
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': -_chatId - 1000000000000,
    'is_channel': false,
  },
  'last_read_inbox_message_id': 0,
  'unread_count': 0,
  'permissions': {'can_send_basic_messages': true},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  late List<Map<String, dynamic>> requests;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          switch (request['@type']) {
            case 'getChat':
              return _chatJson();
            case 'getChatHistory':
              final offset = request['offset'] as int? ?? 0;
              // Real TDLib: "Parameter offset must be non-positive".
              if (offset > 0) {
                throw StateError('Parameter offset must be non-positive');
              }
              final history = _history();
              final from = request['from_message_id'] as int? ?? 0;
              final limit = request['limit'] as int? ?? 40;
              var start = 0;
              if (from > 0) {
                final index = history.indexWhere(
                  (m) => (m['id'] as int) <= from,
                );
                start = index < 0
                    ? history.length
                    : index + (offset < 0 ? -offset - 1 : 0);
              }
              if (start >= history.length) {
                return {
                  '@type': 'messages',
                  'total_count': history.length,
                  'messages': <Map<String, dynamic>>[],
                };
              }
              final page = history.skip(start).take(limit).toList();
              return {
                '@type': 'messages',
                'total_count': page.length,
                'messages': page,
              };
            case 'getMessages':
              final ids = (request['message_ids'] as List?)?.cast<int>() ?? [];
              final byId = {for (final m in _history()) m['id'] as int: m};
              return {
                '@type': 'messages',
                'total_count': ids.length,
                'messages': [
                  for (final id in ids)
                    if (byId[id] != null) byId[id]!,
                ],
              };
            case 'getMe':
              return {
                '@type': 'user',
                'id': 1,
                'first_name': 'Reader',
                'type': {'@type': 'userTypeRegular'},
              };
            case 'getUser':
              return {
                '@type': 'user',
                'id': request['user_id'] ?? 2,
                'first_name': 'Member',
                'type': {'@type': 'userTypeRegular'},
              };
            case 'getSupergroup':
              return {'@type': 'supergroup', 'id': -_chatId - 1000000000000};
            case 'getSupergroupFullInfo':
              return {'@type': 'supergroupFullInfo', 'member_count': 12};
            case 'getMessageAvailableReactions':
              return {
                '@type': 'availableReactions',
                'top_reactions': <Map<String, dynamic>>[],
                'recent_reactions': <Map<String, dynamic>>[],
                'popular_reactions': <Map<String, dynamic>>[],
                'allow_custom_emoji': false,
                'are_tags': false,
                'unavailability_reason': null,
              };
            case 'getOption':
              return {'@type': 'optionValueBoolean', 'value': false};
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  late ThemeController theme;
  late TranslationController translation;

  setUp(() async {
    requests = [];
    SharedPreferences.setMockInitialValues({'openChatsAtLatest': true});
    theme = ThemeController(await SharedPreferences.getInstance());
    translation = TranslationController(await SharedPreferences.getInstance());
  });
  tearDown(() {
    clearChatMemoryCaches();
    theme.dispose();
    translation.dispose();
  });

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<TranslationController>.value(value: translation),
    ],
    child: MaterialApp(
      theme: ThemeData(
        extensions: [AppColors.light],
        platform: TargetPlatform.android,
      ),
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ChatView(chatId: _chatId, title: 'Jump origin group'),
    ),
  );

  Finder transcript() => find.byType(CustomScrollView);

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: transcript(), matching: find.byType(Scrollable)),
      )
      .position;

  Future<void> pumpFrames(WidgetTester tester, {int frames = 30}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    clearChatMemoryCaches();
    await tester.pumpWidget(app());
    // The transcript keeps timers alive (progress polling), so bounded pumps
    // instead of pumpAndSettle; the entry positioning runs several endOfFrame
    // passes before it reveals the chat.
    await pumpFrames(tester, frames: 14);
    expect(
      find.byKey(ValueKey('messageTapTarget-${_mid(_messageCount)}')),
      findsOneWidget,
      reason: 'the newest message must render',
    );
  }

  Finder messageRow(int serverId) =>
      find.byKey(ValueKey('messageTapTarget-${_mid(serverId)}'));

  Finder replyQuoteOf(int serverId) => find.descendant(
    of: messageRow(serverId),
    matching: find.byKey(const ValueKey('messageReplyOpenOriginal')),
  );

  final jumpArrow = find.byKey(const ValueKey('chat-jump-to-bottom'));

  /// Rows currently intersecting the transcript viewport, mapped to their top
  /// offset inside that viewport.
  Map<int, double> visibleRows(WidgetTester tester) {
    final viewport = tester.getRect(transcript());
    final rows = <int, double>{};
    final finder = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('messageTapTarget-');
    });
    for (final element in finder.evaluate()) {
      final key = element.widget.key! as ValueKey<String>;
      final id = int.tryParse(key.value.substring('messageTapTarget-'.length));
      final box = element.renderObject;
      if (id == null || box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom <= viewport.top || top >= viewport.bottom) continue;
      rows[id] = top - viewport.top;
    }
    return rows;
  }

  Future<void> dragTranscript(WidgetTester tester, double distance) async {
    final steps = (distance.abs() / 45).ceil().clamp(1, 1000);
    final gesture = await tester.startGesture(tester.getCenter(transcript()));
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, distance / steps));
      await tester.pump();
    }
    await gesture.up();
    await pumpFrames(tester, frames: 8);
  }

  /// Leaves the loaded bottom by dragging toward older messages, so a reply
  /// jump starts from somewhere the reader chose to be. Stepped rather than a
  /// single `drag`: the transcript measures the latest row during layout, so a
  /// one-shot fling would be judged against a frame-old measurement.
  Future<void> dragUpFromBottom(WidgetTester tester, double distance) async {
    expect(
      jumpArrow,
      findsNothing,
      reason: 'the newest message is on screen before the drag',
    );
    await dragTranscript(tester, distance);
    expect(
      jumpArrow,
      findsOneWidget,
      reason: 'scrolling up reveals the floating arrow',
    );
  }

  testWidgets(
    'the arrow returns to the message the reader left, not the bottom',
    (tester) async {
      await pumpChat(tester);
      await dragUpFromBottom(tester, 320);

      final before = visibleRows(tester);
      expect(before, contains(_mid(_replyId)));
      final replyTop = before[_mid(_replyId)]!;

      await tester.tap(replyQuoteOf(_replyId));
      await pumpFrames(tester);

      // The jump landed on the quoted parent, far above the reply.
      expect(
        visibleRows(tester),
        contains(_mid(_parentId)),
        reason: 'tapping the quote jumps to the replied-to message',
      );
      expect(visibleRows(tester), isNot(contains(_mid(_replyId))));
      expect(jumpArrow, findsOneWidget);

      await tester.tap(jumpArrow);
      await pumpFrames(tester);

      final after = visibleRows(tester);
      expect(
        after,
        contains(_mid(_replyId)),
        reason:
            'the arrow restores the message that was in view before the jump',
      );
      expect(
        after[_mid(_replyId)],
        closeTo(replyTop, 1.5),
        reason: 'the origin row comes back at its recorded viewport offset',
      );
      // Every row that was on screen returns to the same place.
      for (final entry in before.entries) {
        if (!after.containsKey(entry.key)) continue;
        expect(after[entry.key], closeTo(entry.value, 1.5));
      }
      // And the viewport did not fall through to the chat bottom.
      final pos = position(tester);
      expect(pos.pixels, lessThan(pos.maxScrollExtent - 200));
      expect(jumpArrow, findsOneWidget);
    },
  );

  testWidgets('without a preceding jump the arrow still goes to the bottom', (
    tester,
  ) async {
    await pumpChat(tester);
    await dragUpFromBottom(tester, 320);
    expect(visibleRows(tester), isNot(contains(_mid(_messageCount))));

    await tester.tap(jumpArrow);
    await pumpFrames(tester);

    expect(
      visibleRows(tester),
      contains(_mid(_messageCount)),
      reason: 'the arrow keeps its original meaning with no stored origin',
    );
    expect(
      jumpArrow,
      findsNothing,
      reason: 'the newest message is on screen again',
    );
  });

  testWidgets('a chain of jumps returns to the first origin', (tester) async {
    await pumpChat(tester);
    await dragUpFromBottom(tester, 320);
    final before = visibleRows(tester);
    final replyTop = before[_mid(_replyId)]!;

    await tester.tap(replyQuoteOf(_replyId));
    await pumpFrames(tester);
    expect(visibleRows(tester), contains(_mid(_parentId)));

    // Second jump: the parent carries its own quote.
    await tester.tap(replyQuoteOf(_parentId));
    await pumpFrames(tester);
    expect(visibleRows(tester), contains(_mid(_grandparentId)));

    await tester.tap(jumpArrow);
    await pumpFrames(tester);

    final after = visibleRows(tester);
    expect(
      after,
      contains(_mid(_replyId)),
      reason: 'the chain returns to where the reader first left',
    );
    expect(after[_mid(_replyId)], closeTo(replyTop, 1.5));
    expect(after, isNot(contains(_mid(_parentId))));
  });

  testWidgets('a second tap after the origin is consumed goes to the bottom', (
    tester,
  ) async {
    await pumpChat(tester);
    await dragUpFromBottom(tester, 320);
    await tester.tap(replyQuoteOf(_replyId));
    await pumpFrames(tester);

    await tester.tap(jumpArrow);
    await pumpFrames(tester);
    expect(visibleRows(tester), contains(_mid(_replyId)));
    expect(jumpArrow, findsOneWidget);

    await tester.tap(jumpArrow);
    await pumpFrames(tester);
    expect(
      visibleRows(tester),
      contains(_mid(_messageCount)),
      reason: 'the consumed origin must not survive a second tap',
    );
    expect(jumpArrow, findsNothing);
  });

  testWidgets('a long user drag away from the jump target drops the origin', (
    tester,
  ) async {
    await pumpChat(tester);
    await dragUpFromBottom(tester, 320);
    await tester.tap(replyQuoteOf(_replyId));
    await pumpFrames(tester);
    expect(visibleRows(tester), contains(_mid(_parentId)));

    // Read a long way away from where the jump landed, back toward the
    // newest messages: the quoted parent must leave the viewport.
    await dragTranscript(tester, -520);
    expect(visibleRows(tester), isNot(contains(_mid(_parentId))));

    await tester.tap(jumpArrow);
    await pumpFrames(tester);
    expect(
      visibleRows(tester),
      contains(_mid(_messageCount)),
      reason: 'an abandoned origin must not teleport the reader back',
    );
  });

  test('the history fixture keeps TDLib history semantics', () {
    final ids = _history().map((m) => m['id'] as int).toList();
    final descending = [...ids]..sort((a, b) => b - a);
    expect(
      ids,
      orderedEquals(descending),
      reason: 'pages must arrive newest → oldest',
    );
  });
}
