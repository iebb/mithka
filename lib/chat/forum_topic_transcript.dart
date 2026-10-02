//
//  forum_topic_transcript.dart
//
//  Request and state shaping for showing one forum topic in the ordinary chat
//  transcript instead of the topic post feed.
//

import '../tdlib/json_helpers.dart';

/// Telegram's General topic. TDLib may omit `topic_id` on its messages.
const generalForumTopicId = 1;

/// The forum topic a raw TDLib `message` belongs to, or null when the message
/// is not scoped to a forum topic.
int? forumTopicIdOfRawMessage(Map<String, dynamic> raw) {
  final topic = raw.obj('topic_id');
  if (topic == null || topic.type != 'messageTopicForum') return null;
  return topic.integer('forum_topic_id');
}

/// Whether [raw] belongs to the forum topic [forumTopicId]. A message that
/// carries no topic reference is part of the General topic.
bool rawMessageBelongsToForumTopic(Map<String, dynamic> raw, int forumTopicId) {
  final topic = raw.obj('topic_id');
  if (topic == null) return forumTopicId == generalForumTopicId;
  return forumTopicIdOfRawMessage(raw) == forumTopicId;
}

/// Rewrites a chat-wide history or search request into its topic-scoped form.
///
/// `getChatHistory` becomes `getForumTopicHistory`, which has no local-only
/// mode, and `searchChatMessages` gains the forum topic filter. Other requests
/// are returned unchanged.
Map<String, dynamic> forumTopicHistoryRequest(
  Map<String, dynamic> request,
  int forumTopicId,
) {
  switch (request.type) {
    case 'getChatHistory':
      return {
        '@type': 'getForumTopicHistory',
        'chat_id': request['chat_id'],
        'forum_topic_id': forumTopicId,
        'from_message_id': request['from_message_id'] ?? 0,
        'offset': request['offset'] ?? 0,
        'limit': request['limit'] ?? 40,
      };
    case 'searchChatMessages':
      return Map<String, dynamic>.from(request)
        ..['topic_id'] = {
          '@type': 'messageTopicForum',
          'forum_topic_id': forumTopicId,
        };
    default:
      return request;
  }
}

/// The thread-history form of a `getForumTopicHistory` request, for TDLib
/// builds that reject the forum-topic method.
Map<String, dynamic> forumTopicThreadHistoryRequest(
  Map<String, dynamic> request,
) => {
  '@type': 'getMessageThreadHistory',
  'chat_id': request['chat_id'],
  'message_id': request['forum_topic_id'],
  'from_message_id': request['from_message_id'] ?? 0,
  'offset': request['offset'] ?? 0,
  'limit': request['limit'] ?? 40,
};

/// A `getChat` result with its read state, latest message and draft replaced
/// by the topic's own values, so a topic transcript opens, positions and
/// marks read against the topic rather than the whole chat.
///
/// When [topic] is unavailable, chat-wide values are dropped rather than
/// applied to the topic.
Map<String, dynamic> forumTopicChatSnapshot(
  Map<String, dynamic> chat,
  Map<String, dynamic>? topic,
) {
  final snapshot = Map<String, dynamic>.from(chat)
    ..remove('last_message')
    ..remove('draft_message')
    ..['is_marked_as_unread'] = false
    ..['unread_count'] = 0
    ..['last_read_inbox_message_id'] = 0
    ..['unread_mention_count'] = 0
    ..['unread_reaction_count'] = 0;
  if (topic == null) return snapshot;
  for (final key in const [
    'last_message',
    'draft_message',
    'unread_count',
    'last_read_inbox_message_id',
    'last_read_outbox_message_id',
    'unread_mention_count',
    'unread_reaction_count',
  ]) {
    if (topic.containsKey(key)) snapshot[key] = topic[key];
  }
  return snapshot;
}
