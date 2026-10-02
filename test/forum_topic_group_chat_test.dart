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

const _chatId = -1004242;

String _transcriptText(dynamic forumTopicId) => forumTopicId is int
    ? 'Message in topic $forumTopicId'
    : 'Message in the whole chat';

Map<String, dynamic> _topicMessage(dynamic forumTopicId) => {
  '@type': 'message',
  'id': forumTopicId is int ? 5 + forumTopicId : 5,
  'chat_id': _chatId,
  'date': 1785862260,
  'is_outgoing': false,
  'topic_id': {
    '@type': 'messageTopicForum',
    'forum_topic_id': forumTopicId is int ? forumTopicId : 0,
  },
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 2},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': _transcriptText(forumTopicId),
      'entities': [],
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getChat' => {
            '@type': 'chat',
            'id': _chatId,
            'title': 'Forum group',
            'type': {
              '@type': 'chatTypeSupergroup',
              'supergroup_id': 4242,
              'is_channel': false,
            },
            'is_forum': true,
            'view_as_topics': true,
            'last_read_inbox_message_id': 5,
            'unread_count': 0,
            'permissions': {'can_send_basic_messages': true},
          },
          'getSupergroup' => {
            '@type': 'supergroup',
            'id': 4242,
            'is_forum': true,
          },
          'getSupergroupFullInfo' => {
            '@type': 'supergroupFullInfo',
            'member_count': 3,
          },
          'getMe' => {
            '@type': 'user',
            'id': 1,
            'type': {'@type': 'userTypeRegular'},
          },
          'getUser' => {
            '@type': 'user',
            'id': request['user_id'] ?? 2,
            'first_name': 'Member',
            'type': {'@type': 'userTypeRegular'},
          },
          'getForumTopic' => {
            '@type': 'forumTopic',
            'info': {
              '@type': 'forumTopicInfo',
              'chat_id': _chatId,
              'forum_topic_id': request['forum_topic_id'],
              'name': 'Topic ${request['forum_topic_id']}',
              'is_general': false,
            },
            'last_message': _topicMessage(request['forum_topic_id']),
            'unread_count': 0,
            'last_read_inbox_message_id': 5,
            'last_read_outbox_message_id': 5,
          },
          'getForumTopicHistory' => {
            '@type': 'messages',
            'total_count': 1,
            'messages': [_topicMessage(request['forum_topic_id'])],
          },
          'getChatHistory' => {
            '@type': 'messages',
            'total_count': 1,
            'messages': [_topicMessage(null)],
          },
          _ => {'@type': 'ok'},
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
    SharedPreferences.setMockInitialValues({'openChatsAtLatest': true});
    theme = ThemeController(await SharedPreferences.getInstance());
    translation = TranslationController(await SharedPreferences.getInstance());
  });
  tearDown(() {
    theme.dispose();
    translation.dispose();
  });

  Widget app({int? forumTopicId, Key? key}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<TranslationController>.value(value: translation),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatView(
        key: key,
        chatId: _chatId,
        title: 'Forum group',
        forumTopicId: forumTopicId,
      ),
    ),
  );

  test('forum topics as group chat defaults to off', () async {
    expect(theme.forumTopicsAsGroupChat, isFalse);
    theme.forumTopicsAsGroupChat = true;
    expect(theme.forumTopicsAsGroupChat, isTrue);
    theme.forumTopicsAsGroupChat = false;
    expect(theme.forumTopicsAsGroupChat, isFalse);
  });

  testWidgets('a single topic renders as a regular chat transcript', (
    tester,
  ) async {
    clearChatMemoryCaches();
    theme.forumTopicsAsGroupChat = true;
    await tester.pumpWidget(app(forumTopicId: 7));
    await tester.pumpAndSettle();
    // The topic's own transcript, in the ordinary chat surface, with the
    // topic's name in the header instead of the post-feed header.
    expect(find.text(_transcriptText(7), findRichText: true), findsOneWidget);
    expect(find.text('Topic 7'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-header-back')), findsNothing);
    expect(tester.takeException(), isNull);
    clearChatMemoryCaches();
  });

  testWidgets(
    'topics and the whole chat never restore each other\'s transcript',
    (tester) async {
      clearChatMemoryCaches();
      theme.forumTopicsAsGroupChat = true;

      Future<void> open(int? forumTopicId) async {
        await tester.pumpWidget(
          app(
            forumTopicId: forumTopicId,
            key: ValueKey('chat-${forumTopicId ?? 'whole'}'),
          ),
        );
        // The first frame is what the session cache paints before any reload.
        for (final other in <int?>[7, 9, null]..remove(forumTopicId)) {
          expect(
            find.text(_transcriptText(other), findRichText: true),
            findsNothing,
          );
        }
        await tester.pumpAndSettle();
        expect(
          find.text(_transcriptText(forumTopicId), findRichText: true),
          findsOneWidget,
        );
        for (final other in <int?>[7, 9, null]..remove(forumTopicId)) {
          expect(
            find.text(_transcriptText(other), findRichText: true),
            findsNothing,
          );
        }
        // Leave the chat so its transcript is written back to the cache.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }

      // Caches stay warm between hops: every reopen reads a populated entry.
      await open(7);
      await open(9);
      await open(null);
      await open(7);
      await open(null);
      await open(9);
      expect(tester.takeException(), isNull);
      clearChatMemoryCaches();
    },
  );
}
