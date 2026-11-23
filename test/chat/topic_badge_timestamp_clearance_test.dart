//
//  topic_badge_timestamp_clearance_test.dart
//
//  In a topics-enabled bot chat's "All topics" transcript the topic section
//  badge sits directly under the previous message. A message can hang its
//  detail timestamp below its own bubble (`alwaysShowMessageTime`, a tap or a
//  hover), so the badge must keep clear of that floating row.
//
//  The transcript's row contract is: every row reserves top padding for the
//  previous row's out-of-box paint (message rows 7, the time separator and the
//  system banner 6). The topic section header reserved none, so with a topic
//  name wide enough to reach the timestamp's column the badge's plate covered
//  the timestamp text.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 700;
const _botUserId = 42;
const _topicA = 61474;
const _topicB = 61753;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => _response(request),
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
  });

  testWidgets('topic section badges clear the previous message timestamp', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({
      'alwaysShowMessageTime': true,
      'showChannelsTab': false,
      'showMomentsTab': false,
      'communitiesEnabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final translation = TranslationController(prefs);
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);
    addTearDown(auth.dispose);
    addTearDown(translation.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AppLocaleController>.value(
            value: AppLocaleController(prefs),
          ),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
          ChangeNotifierProvider<AuthManager>.value(value: auth),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
            platform: TargetPlatform.iOS,
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChatView(chatId: _chatId, title: 'Topic Bot'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 2));

    final headerFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Padding &&
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith(
            'forum-topic-section-',
          ),
    );
    final timestampFinder = find.byKey(
      const ValueKey('messageTappedTimestamp'),
      skipOffstage: false,
    );
    final pills = <Rect>[];
    for (final element in headerFinder.evaluate()) {
      final key = (element.widget.key as ValueKey<String>).value;
      // The visible plate, not the full-width row wrapper.
      pills.add(
        tester.getRect(
          find.byKey(
            ValueKey(
              key.replaceFirst(
                'forum-topic-section-',
                'forum-topic-section-tap-',
              ),
            ),
          ),
        ),
      );
    }
    final stamps = <Rect>[
      for (final element in timestampFinder.evaluate())
        tester.getRect(find.byElementPredicate((e) => e == element)),
    ];

    // Both topic runs render a badge and every message keeps its always-on
    // detail timestamp; without that the checks below would pass vacuously.
    expect(pills, hasLength(2));
    expect(stamps, hasLength(4));

    for (final pill in pills) {
      for (final stamp in stamps) {
        final overlap = pill.intersect(stamp);
        expect(
          overlap.width <= 0 || overlap.height <= 0,
          isTrue,
          reason:
              'the topic badge $pill paints over the message timestamp $stamp '
              '(overlap $overlap)',
        );
      }
    }

    // Pin the actual regression: the message that closes one topic hangs its
    // timestamp 5px into the next row, and the badge that opens the following
    // topic is that next row. It must sit directly under that stamp — far
    // enough away to clear it, close enough that the assertion above is not
    // passing because the badge drifted off somewhere else.
    final lastPill = pills.last;
    final adjacent = stamps
        .where(
          (stamp) =>
              stamp.bottom <= lastPill.top + 1 &&
              lastPill.top - stamp.bottom <= 8,
        )
        .toList();
    expect(
      adjacent,
      hasLength(1),
      reason:
          'expected exactly one timestamp hanging right above the last '
          'badge, at ${lastPill.top}; stamps were $stamps',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  });
}

Map<String, dynamic> _response(Map<String, dynamic> request) =>
    switch (request['@type']) {
      'getChat' => {
        '@type': 'chat',
        'id': _chatId,
        'title': 'Topic Bot',
        'type': {'@type': 'chatTypePrivate', 'user_id': _botUserId},
        'permissions': {
          '@type': 'chatPermissions',
          'can_send_basic_messages': true,
        },
      },
      'getUser' => {
        '@type': 'user',
        'id': _botUserId,
        'first_name': 'Topic',
        'last_name': 'Bot',
        'type': {'@type': 'userTypeBot', 'has_topics': true},
      },
      'getSupergroup' => {
        '@type': 'error',
        'message': 'chat not found',
        'code': 400,
      },
      'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Me'},
      'getConnectionState' => {'@type': 'connectionStateReady'},
      'getForumTopics' => {
        '@type': 'forumTopics',
        'topics': [
          _topic(_topicA, '项目组讨论与技术方案评审', _message(10, 'A first')),
          _topic(_topicB, '产品反馈与建议收集', _message(12, 'B first')),
        ],
      },
      'getChatHistory' => {'@type': 'messages', 'messages': _history},
      'getMessage' => _message(request['message_id'] as int, 'Fetched'),
      _ => {'@type': 'ok'},
    };

Map<String, dynamic> _topic(
  int id,
  String name,
  Map<String, dynamic> lastMessage,
) => {
  '@type': 'forumTopic',
  'info': {
    '@type': 'forumTopicInfo',
    'chat_id': _chatId,
    'forum_topic_id': id,
    'name': name,
  },
  'last_message': lastMessage,
};

/// Oldest first: two topics, an incoming and an outgoing message in each.
final List<Map<String, dynamic>> _history = [
  _message(10, 'A first', topicId: _topicA),
  _message(11, 'A second', topicId: _topicA, outgoing: true),
  _message(12, 'B first', topicId: _topicB),
  _message(13, 'B second', topicId: _topicB, outgoing: true),
];

Map<String, dynamic> _message(
  int id,
  String text, {
  int? topicId,
  bool outgoing = false,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1700000000 + id,
  'is_outgoing': outgoing,
  'sender_id': {
    '@type': 'messageSenderUser',
    'user_id': outgoing ? 1 : _botUserId,
  },
  if (topicId != null)
    'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': topicId},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text},
  },
};
