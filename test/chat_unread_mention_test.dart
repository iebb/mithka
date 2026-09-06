import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('message parser preserves TDLib unread mention state', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 91,
      'chat_id': 12,
      'date': 1,
      'is_outgoing': false,
      'contains_unread_mention': true,
      'unread_reactions': [
        {
          '@type': 'unreadReaction',
          'type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
          'sender_id': {'@type': 'messageSenderUser', 'user_id': 8},
          'is_big': false,
        },
      ],
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': '@me hello',
          'entities': <Object>[],
        },
      },
    });

    expect(message, isNotNull);
    expect(message!.containsUnreadMention, isTrue);
    expect(message.hasUnreadReactions, isTrue);
  });

  test('chat parser preserves separate unread activity counters', () {
    final chat = TDParse.chat({
      '@type': 'chat',
      'id': 12,
      'title': 'Group',
      'unread_count': 4,
      'unread_mention_count': 2,
      'unread_reaction_count': 3,
      'positions': <Object>[],
      'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 7},
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_mute_for': true,
      },
    });

    expect(chat, isNotNull);
    expect(chat!.unreadMentionCount, 2);
    expect(chat.unreadReactionCount, 3);
  });

  test('viewing mentions decrements the badge without going negative', () {
    expect(unreadMentionCountAfterReading(3, 1), 2);
    expect(unreadMentionCountAfterReading(1, 1), 0);
    expect(unreadMentionCountAfterReading(0, 4), 0);
    expect(unreadMentionCountAfterReading(2, -1), 2);
    expect(unreadReactionCountAfterReading(3, 1), 2);
    expect(unreadReactionCountAfterReading(0, 4), 0);
  });
}
