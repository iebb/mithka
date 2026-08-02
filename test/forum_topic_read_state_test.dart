import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/forum_topic_browser_view.dart';
import 'package:mithka/channels/topic_chat_view.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'visible topic messages are reported once and offscreen rows are not',
    () {
      final reported = <int>{4};
      const viewport = Rect.fromLTWH(0, 0, 100, 100);
      final bounds = <int, Rect>{
        1: const Rect.fromLTWH(10, 10, 30, 30),
        2: const Rect.fromLTWH(10, 90, 30, 30),
        3: const Rect.fromLTWH(10, 120, 30, 30),
        4: const Rect.fromLTWH(50, 50, 20, 20),
      };

      expect(
        takeNewlyVisibleForumTopicMessageIds(
          viewport: viewport,
          messageBounds: bounds,
          alreadyReported: reported,
        ),
        [1, 2],
      );
      expect(reported, {1, 2, 4});
      expect(
        takeNewlyVisibleForumTopicMessageIds(
          viewport: viewport,
          messageBounds: bounds,
          alreadyReported: reported,
        ),
        isEmpty,
      );
    },
  );

  test('only real incoming topic messages qualify for read reporting', () {
    ChatMessage message({bool outgoing = false, bool service = false}) =>
        ChatMessage(
          id: 12,
          text: 'post',
          date: 1,
          isOutgoing: outgoing,
          isService: service,
        );

    expect(
      isReportableForumTopicMessage(message(), isSynthetic: false),
      isTrue,
    );
    expect(
      isReportableForumTopicMessage(
        message(outgoing: true),
        isSynthetic: false,
      ),
      isFalse,
    );
    expect(
      isReportableForumTopicMessage(message(service: true), isSynthetic: false),
      isFalse,
    );
    expect(
      isReportableForumTopicMessage(message(), isSynthetic: true),
      isFalse,
    );
  });

  test('topic read request uses the forum-history source and exact ids', () {
    expect(
      forumTopicViewMessagesRequest(chatId: -10042, messageIds: [90, 91]),
      {
        '@type': 'viewMessages',
        'chat_id': -10042,
        'message_ids': [90, 91],
        'source': {'@type': 'messageSourceForumTopicHistory'},
        'force_read': true,
      },
    );
  });

  testWidgets('topic browser refreshes unread badges after returning', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final route = Completer<void>();
    var topicLoads = 0;
    final chat = ChatSummary(
      id: -10042,
      title: 'Forum',
      lastMessage: 'Latest',
      lastMessageId: 100,
      date: 1,
      unreadCount: 0,
      order: 1,
      isMuted: false,
      isForum: true,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ForumTopicBrowserView(
            chats: [chat],
            initialChat: chat,
            query: (request) async {
              expect(request['@type'], 'getForumTopics');
              topicLoads++;
              return _forumTopicsResponse(unreadCount: topicLoads == 1 ? 2 : 0);
            },
            openTopicRoute: (_, openedChat, topicId, _) {
              expect(openedChat.id, chat.id);
              expect(topicId, 77);
              return route.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(topicLoads, 1);
    expect(find.byType(UnreadBadge), findsOneWidget);
    await tester.tap(find.text('Topic A'));
    await tester.pump();
    expect(topicLoads, 1, reason: 'refresh waits for the topic route to close');

    route.complete();
    await tester.pumpAndSettle();

    expect(topicLoads, 2);
    expect(find.byType(UnreadBadge), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'topic browser waits for a replacement chat route before refreshing',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);
      final topicRoute = Completer<void>();
      final replacementChatRoute = Completer<void>();
      late TopicChatRouteSession routeSession;
      var topicLoads = 0;
      final chat = ChatSummary(
        id: -10042,
        title: 'Forum',
        lastMessage: 'Latest',
        lastMessageId: 100,
        date: 1,
        unreadCount: 0,
        order: 1,
        isMuted: false,
        isForum: true,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ForumTopicBrowserView(
              chats: [chat],
              initialChat: chat,
              query: (_) async {
                topicLoads++;
                return _forumTopicsResponse(
                  unreadCount: topicLoads == 1 ? 2 : 0,
                );
              },
              openTopicRoute: (_, _, _, session) {
                routeSession = session;
                return topicRoute.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Topic A'));
      await tester.pump();
      routeSession.trackRoute(() => replacementChatRoute.future);
      topicRoute.complete();
      await tester.pump();

      expect(
        topicLoads,
        1,
        reason: 'replacing the topic route does not reveal the browser',
      );

      replacementChatRoute.complete();
      await tester.pumpAndSettle();

      expect(topicLoads, 2);
      expect(find.byType(UnreadBadge), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('forced topic refreshes queue behind an in-flight load', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final delayedRefresh = Completer<Map<String, dynamic>>();
    final openedRoutes = <Completer<void>>[];
    var topicLoads = 0;
    final chat = ChatSummary(
      id: -10042,
      title: 'Forum',
      lastMessage: 'Latest',
      lastMessageId: 100,
      date: 1,
      unreadCount: 0,
      order: 1,
      isMuted: false,
      isForum: true,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ForumTopicBrowserView(
            chats: [chat],
            initialChat: chat,
            query: (_) {
              topicLoads++;
              if (topicLoads == 2) return delayedRefresh.future;
              return Future.value(
                _forumTopicsResponse(unreadCount: topicLoads == 1 ? 2 : 0),
              );
            },
            openTopicRoute: (_, _, _, _) {
              final route = Completer<void>();
              openedRoutes.add(route);
              return route.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Topic A'));
    await tester.pump();
    openedRoutes.single.complete();
    await tester.pump();
    expect(topicLoads, 2);

    await tester.tap(find.text('Topic A'));
    await tester.pump();
    expect(openedRoutes, hasLength(2));
    openedRoutes.last.complete();
    await tester.pump();
    expect(
      topicLoads,
      2,
      reason: 'the second return queues behind the active refresh',
    );

    delayedRefresh.complete(_forumTopicsResponse(unreadCount: 1));
    await tester.pumpAndSettle();

    expect(topicLoads, 3);
    expect(find.byType(UnreadBadge), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('topic-enabled bot chat uses the reusable topic browser', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final chat = ChatSummary(
      id: 420,
      title: 'Topic Bot',
      lastMessage: 'Latest',
      lastMessageId: 100,
      date: 1,
      unreadCount: 0,
      order: 1,
      isMuted: false,
      kind: ChatKind.bot,
      supportsBotTopics: true,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ForumTopicBrowserView(
            chats: [chat],
            initialChat: chat,
            query: (request) async {
              expect(request['@type'], 'getForumTopics');
              expect(request['chat_id'], 420);
              return _forumTopicsResponse(unreadCount: 0);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(chat.isForum, isFalse);
    expect(chat.supportsTopics, isTrue);
    expect(find.text('Topic A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _forumTopicsResponse({required int unreadCount}) => {
  '@type': 'forumTopics',
  'topics': [
    {
      '@type': 'forumTopic',
      'info': {
        '@type': 'forumTopicInfo',
        'message_thread_id': 77,
        'name': 'Topic A',
      },
      'unread_count': unreadCount,
      'order': 10,
      'last_message': {
        '@type': 'message',
        'id': 90,
        'chat_id': -10042,
        'date': 1,
        'is_outgoing': false,
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'Post'},
        },
      },
    },
  ],
};
