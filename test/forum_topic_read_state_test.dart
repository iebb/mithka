import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_chat_view.dart';
import 'package:mithka/tdlib/td_models.dart';

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
}
