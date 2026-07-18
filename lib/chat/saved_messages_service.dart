import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

typedef SavedMessagesQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class SavedMessagesTopicRecord {
  const SavedMessagesTopicRecord({
    required this.id,
    required this.type,
    required this.sourceChatId,
    required this.isPinned,
    required this.order,
    required this.lastMessage,
  });

  factory SavedMessagesTopicRecord.fromUpdate(Map<String, dynamic> topic) {
    final type = topic.obj('type');
    return SavedMessagesTopicRecord(
      id: topic.int64('id') ?? 0,
      type: type?.type ?? 'savedMessagesTopicTypeMyNotes',
      sourceChatId: type?.int64('chat_id'),
      isPinned: topic.boolean('is_pinned') ?? false,
      order: topic.int64('order') ?? 0,
      lastMessage: TDParse.message(topic.obj('last_message') ?? const {}),
    );
  }

  final int id;
  final String type;
  final int? sourceChatId;
  final bool isPinned;
  final int order;
  final ChatMessage? lastMessage;
}

class SavedMessagesTagRecord {
  const SavedMessagesTagRecord({
    required this.type,
    required this.label,
    required this.count,
  });

  factory SavedMessagesTagRecord.fromRaw(Map<String, dynamic> raw) =>
      SavedMessagesTagRecord(
        type: raw.obj('tag') ?? const {'@type': 'reactionTypeEmoji'},
        label: raw.str('label') ?? '',
        count: raw.integer('count') ?? 0,
      );

  final Map<String, dynamic> type;
  final String label;
  final int count;

  String get key => switch (type.type) {
    'reactionTypeEmoji' => 'emoji:${type.str('emoji') ?? ''}',
    'reactionTypeCustomEmoji' => 'custom:${type.int64('custom_emoji_id') ?? 0}',
    _ => type.type ?? 'unknown',
  };

  String get fallbackLabel => switch (type.type) {
    'reactionTypeEmoji' => type.str('emoji') ?? '',
    'reactionTypeCustomEmoji' => 'Custom emoji',
    _ => 'Tag',
  };
}

class SavedMessageRecord {
  const SavedMessageRecord({
    required this.raw,
    required this.message,
    required this.topicId,
    required this.originalChatId,
    required this.originalMessageId,
  });

  factory SavedMessageRecord.fromRaw(Map<String, dynamic> raw) {
    final forward = raw.obj('forward_info');
    final source = forward?.obj('source');
    final origin = forward?.obj('origin');
    var originalChatId = source?.int64('chat_id');
    var originalMessageId = source?.int64('message_id');
    if ((originalChatId ?? 0) == 0 || (originalMessageId ?? 0) == 0) {
      if (origin?.type == 'messageOriginChannel') {
        originalChatId = origin?.int64('chat_id');
        originalMessageId = origin?.int64('message_id');
      }
    }
    final topic = raw.obj('topic_id');
    return SavedMessageRecord(
      raw: raw,
      message: TDParse.message(raw),
      topicId: topic?.type == 'messageTopicSavedMessages'
          ? topic?.int64('saved_messages_topic_id') ?? 0
          : 0,
      originalChatId: (originalChatId ?? 0) == 0 ? null : originalChatId,
      originalMessageId: (originalMessageId ?? 0) == 0
          ? null
          : originalMessageId,
    );
  }

  final Map<String, dynamic> raw;
  final ChatMessage? message;
  final int topicId;
  final int? originalChatId;
  final int? originalMessageId;

  int get id => raw.int64('id') ?? 0;
}

class SavedMessagePage {
  const SavedMessagePage({
    required this.messages,
    required this.nextFromMessageId,
    required this.hasMore,
  });

  final List<SavedMessageRecord> messages;
  final int nextFromMessageId;
  final bool hasMore;
}

class SavedMessagesService {
  SavedMessagesService({SavedMessagesQuery? query})
    : _query = query ?? TdClient.shared.query;

  final SavedMessagesQuery _query;
  int? _savedChatId;

  Future<Map<String, dynamic>> currentUser() => _query({'@type': 'getMe'});

  Future<int> savedChatId() async {
    final cached = _savedChatId;
    if (cached != null) return cached;
    final option = await _query({'@type': 'getOption', 'name': 'my_id'});
    final userId = option.int64('value');
    if (userId == null) throw StateError('Saved Messages user is unavailable');
    final chat = await _query({
      '@type': 'createPrivateChat',
      'user_id': userId,
      'force': false,
    });
    final chatId = chat.int64('id');
    if (chatId == null) throw StateError('Saved Messages chat is unavailable');
    _savedChatId = chatId;
    return chatId;
  }

  Future<void> loadTopics({int limit = 100}) =>
      _query({'@type': 'loadSavedMessagesTopics', 'limit': limit});

  Future<List<SavedMessagesTagRecord>> tags({int topicId = 0}) async {
    final response = await _query({
      '@type': 'getSavedMessagesTags',
      'saved_messages_topic_id': topicId,
    });
    return [
      for (final raw
          in response.objects('tags') ?? const <Map<String, dynamic>>[])
        SavedMessagesTagRecord.fromRaw(raw),
    ];
  }

  Future<void> setTagLabel(SavedMessagesTagRecord tag, String label) => _query({
    '@type': 'setSavedMessagesTagLabel',
    'tag': tag.type,
    'label': label.trim(),
  });

  Future<void> setTopicPinned(int topicId, bool pinned) => _query({
    '@type': 'toggleSavedMessagesTopicIsPinned',
    'saved_messages_topic_id': topicId,
    'is_pinned': pinned,
  });

  Future<Map<String, dynamic>> getChat(int chatId) =>
      _query({'@type': 'getChat', 'chat_id': chatId});

  Future<SavedMessagePage> messages({
    required int topicId,
    required String query,
    required SavedMessagesTagRecord? tag,
    required int fromMessageId,
    int limit = 50,
  }) async {
    final trimmedQuery = query.trim();
    late Map<String, dynamic> response;
    if (trimmedQuery.isNotEmpty || tag != null) {
      try {
        response = await _query({
          '@type': 'searchSavedMessages',
          'saved_messages_topic_id': topicId,
          'tag': tag?.type,
          'query': trimmedQuery,
          'from_message_id': fromMessageId,
          'offset': 0,
          'limit': limit,
        });
      } catch (_) {
        if (tag != null) rethrow;
        response = await _query({
          '@type': 'searchChatMessages',
          'chat_id': await savedChatId(),
          'topic_id': topicId == 0
              ? null
              : {
                  '@type': 'messageTopicSavedMessages',
                  'saved_messages_topic_id': topicId,
                },
          'query': trimmedQuery,
          'sender_id': null,
          'from_message_id': fromMessageId,
          'offset': 0,
          'limit': limit,
          'filter': null,
        });
      }
    } else if (topicId != 0) {
      response = await _query({
        '@type': 'getSavedMessagesTopicHistory',
        'saved_messages_topic_id': topicId,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': limit,
      });
    } else {
      response = await _query({
        '@type': 'getChatHistory',
        'chat_id': await savedChatId(),
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': limit,
        'only_local': false,
      });
    }
    final rawMessages =
        response.objects('messages') ?? const <Map<String, dynamic>>[];
    final records = rawMessages.map(SavedMessageRecord.fromRaw).toList();
    final responseNext = response.int64('next_from_message_id');
    final derivedNext = records.isEmpty ? 0 : records.last.id;
    final next = responseNext ?? derivedNext;
    return SavedMessagePage(
      messages: records,
      nextFromMessageId: next,
      hasMore: responseNext != null
          ? responseNext != 0
          : records.length >= limit,
    );
  }
}
