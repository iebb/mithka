import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_chat_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'targeted topic history keeps the target in the legacy fallback',
    () async {
      final requests = <Map<String, dynamic>>[];

      final result = await queryForumTopicHistoryWithFallback(
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          if (request['@type'] == 'getForumTopicHistory') {
            throw StateError('unsupported');
          }
          return {'@type': 'messages', 'messages': const []};
        },
        chatId: -10042,
        forumTopicId: 77,
        fromMessageId: 70,
        offset: -20,
        limit: 40,
      );

      expect(result['@type'], 'messages');
      expect(requests, [
        {
          '@type': 'getForumTopicHistory',
          'chat_id': -10042,
          'forum_topic_id': 77,
          'from_message_id': 70,
          'offset': -20,
          'limit': 40,
        },
        {
          '@type': 'getMessageThreadHistory',
          'chat_id': -10042,
          'message_id': 77,
          'from_message_id': 70,
          'offset': -20,
          'limit': 40,
        },
      ]);
    },
  );

  testWidgets(
    'targeted topic entry loads around and aligns the exact message',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);
      final requests = <Map<String, dynamic>>[];
      const targetMessageId = 70;
      final chat = ChatSummary(
        id: -10042,
        title: 'Forum',
        lastMessage: 'Latest',
        lastMessageId: 90,
        date: 90,
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
            home: TopicChatView(
              chat: chat,
              initialThreadId: 77,
              initialMessageId: targetMessageId,
              showBackButton: false,
              query: (request) async {
                requests.add(Map<String, dynamic>.from(request));
                return switch (request['@type']) {
                  'getForumTopics' => _forumTopicsResponse(),
                  'getForumTopicHistory' => _targetedHistoryResponse(
                    targetMessageId,
                  ),
                  _ => throw StateError('Unexpected request: $request'),
                };
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        requests.where((request) => request['@type'] == 'getForumTopicHistory'),
        [
          {
            '@type': 'getForumTopicHistory',
            'chat_id': -10042,
            'forum_topic_id': 77,
            'from_message_id': targetMessageId,
            'offset': -20,
            'limit': 40,
          },
        ],
      );

      final target = find.byKey(const ValueKey('topic-post-$targetMessageId'));
      final viewport = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.vertical,
      );
      expect(target, findsOneWidget);
      expect(viewport, findsOneWidget);

      final targetRect = tester.getRect(target);
      final viewportRect = tester.getRect(viewport);
      expect(targetRect.overlaps(viewportRect), isTrue);
      expect(
        targetRect.top - viewportRect.top,
        closeTo(
          (viewportRect.height - targetRect.height) *
              forumTopicInitialMessageAlignment,
          1,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Map<String, dynamic> _forumTopicsResponse() => {
  '@type': 'forumTopics',
  'topics': [
    {
      '@type': 'forumTopic',
      'info': {
        '@type': 'forumTopicInfo',
        'forum_topic_id': 77,
        'name': 'Topic A',
      },
      'unread_count': 0,
      'order': 10,
      'last_message': _message(90),
    },
  ],
};

Map<String, dynamic> _targetedHistoryResponse(int targetMessageId) => {
  '@type': 'messages',
  'messages': [for (var id = 90; id > 50; id--) _message(id, targetMessageId)],
};

Map<String, dynamic> _message(int id, [int? targetMessageId]) => {
  '@type': 'message',
  'id': id,
  'chat_id': -10042,
  'date': id,
  'is_outgoing': true,
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': id == targetMessageId ? 'Target post' : 'Post $id',
    },
  },
};
