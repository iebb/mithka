import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'outgoing_attachment.dart';

class DirectMessagesTopic {
  const DirectMessagesTopic({
    required this.chatId,
    required this.id,
    required this.senderId,
    required this.order,
    required this.canSendUnpaidMessages,
    required this.isMarkedAsUnread,
    required this.unreadCount,
    required this.lastReadInboxMessageId,
    required this.lastReadOutboxMessageId,
    required this.unreadReactionCount,
    this.lastMessage,
    this.draftText = '',
    this.senderTitle = '',
    this.senderPhoto,
  });

  final int chatId;
  final int id;
  final Map<String, dynamic> senderId;
  final int order;
  final bool canSendUnpaidMessages;
  final bool isMarkedAsUnread;
  final int unreadCount;
  final int lastReadInboxMessageId;
  final int lastReadOutboxMessageId;
  final int unreadReactionCount;
  final ChatMessage? lastMessage;
  final String draftText;
  final String senderTitle;
  final TdFileRef? senderPhoto;

  DirectMessagesTopic copyWith({String? senderTitle, TdFileRef? senderPhoto}) =>
      DirectMessagesTopic(
        chatId: chatId,
        id: id,
        senderId: senderId,
        order: order,
        canSendUnpaidMessages: canSendUnpaidMessages,
        isMarkedAsUnread: isMarkedAsUnread,
        unreadCount: unreadCount,
        lastReadInboxMessageId: lastReadInboxMessageId,
        lastReadOutboxMessageId: lastReadOutboxMessageId,
        unreadReactionCount: unreadReactionCount,
        lastMessage: lastMessage,
        draftText: draftText,
        senderTitle: senderTitle ?? this.senderTitle,
        senderPhoto: senderPhoto ?? this.senderPhoto,
      );

  static DirectMessagesTopic? fromTd(Map<String, dynamic> object) {
    if (object.type != 'directMessagesChatTopic') return null;
    final chatId = object.int64('chat_id');
    final id = object.int64('id');
    final senderId = object.obj('sender_id');
    if (chatId == null || id == null || senderId == null) return null;
    final draft = object.obj('draft_message')?.obj('content');
    return DirectMessagesTopic(
      chatId: chatId,
      id: id,
      senderId: senderId,
      order: object.int64('order') ?? 0,
      canSendUnpaidMessages:
          object.boolean('can_send_unpaid_messages') ?? false,
      isMarkedAsUnread: object.boolean('is_marked_as_unread') ?? false,
      unreadCount: object.int64('unread_count') ?? 0,
      lastReadInboxMessageId: object.int64('last_read_inbox_message_id') ?? 0,
      lastReadOutboxMessageId: object.int64('last_read_outbox_message_id') ?? 0,
      unreadReactionCount: object.int64('unread_reaction_count') ?? 0,
      lastMessage: switch (object.obj('last_message')) {
        final message? => TDParse.message(message),
        null => null,
      },
      draftText: draft?.obj('text')?.str('text') ?? '',
    );
  }
}

class SuggestedPostCapabilities {
  const SuggestedPostCapabilities({
    this.canAddOffer = false,
    this.canBeApproved = false,
    this.canBeDeclined = false,
    this.canBeEdited = false,
    this.canEditSuggestedPostInfo = false,
  });

  final bool canAddOffer;
  final bool canBeApproved;
  final bool canBeDeclined;
  final bool canBeEdited;
  final bool canEditSuggestedPostInfo;

  bool get hasActions =>
      canAddOffer ||
      canBeApproved ||
      canBeDeclined ||
      canBeEdited ||
      canEditSuggestedPostInfo;

  static SuggestedPostCapabilities fromTd(Map<String, dynamic> object) =>
      SuggestedPostCapabilities(
        canAddOffer: object.boolean('can_add_offer') ?? false,
        canBeApproved: object.boolean('can_be_approved') ?? false,
        canBeDeclined: object.boolean('can_be_declined') ?? false,
        canBeEdited: object.boolean('can_be_edited') ?? false,
        canEditSuggestedPostInfo:
            object.boolean('can_edit_suggested_post_info') ?? false,
      );
}

class SuggestedPostLimits {
  const SuggestedPostLimits({
    this.minimumStars = 0,
    this.maximumStars = 0,
    this.minimumTonHundredths = 0,
    this.maximumTonHundredths = 0,
    this.minimumSendDelay = 0,
    this.maximumSendDelay = 0,
  });

  final int minimumStars;
  final int maximumStars;
  final int minimumTonHundredths;
  final int maximumTonHundredths;
  final int minimumSendDelay;
  final int maximumSendDelay;
}

@visibleForTesting
Map<String, dynamic> loadDirectMessagesTopicsRequest({
  required int chatId,
  int limit = 40,
}) => {
  '@type': 'loadDirectMessagesChatTopics',
  'chat_id': chatId,
  'limit': limit,
};

@visibleForTesting
Map<String, dynamic> directMessagesTopicHistoryRequest({
  required int chatId,
  required int topicId,
  int fromMessageId = 0,
  int limit = 80,
}) => {
  '@type': 'getDirectMessagesChatTopicHistory',
  'chat_id': chatId,
  'topic_id': topicId,
  'from_message_id': fromMessageId,
  'offset': 0,
  'limit': limit,
};

@visibleForTesting
Map<String, dynamic> directMessagesTopicMessageByDateRequest({
  required int chatId,
  required int topicId,
  required int date,
}) => {
  '@type': 'getDirectMessagesChatTopicMessageByDate',
  'chat_id': chatId,
  'topic_id': topicId,
  'date': date,
};

@visibleForTesting
Map<String, dynamic> deleteDirectMessagesTopicByDateRequest({
  required int chatId,
  required int topicId,
  required int minDate,
  required int maxDate,
}) => {
  '@type': 'deleteDirectMessagesChatTopicMessagesByDate',
  'chat_id': chatId,
  'topic_id': topicId,
  'min_date': minDate,
  'max_date': maxDate,
};

@visibleForTesting
Map<String, dynamic> sendDirectMessageRequest({
  required int chatId,
  required int topicId,
  required String text,
  SuggestedPostPrice? price,
  int sendDate = 0,
  int replyToMessageId = 0,
  bool asSuggestedPost = false,
}) => sendDirectContentRequest(
  chatId: chatId,
  topicId: topicId,
  inputMessageContent: {
    '@type': 'inputMessageText',
    'text': {'@type': 'formattedText', 'text': text},
  },
  price: price,
  sendDate: sendDate,
  replyToMessageId: replyToMessageId,
  asSuggestedPost: asSuggestedPost,
);

@visibleForTesting
Map<String, dynamic> sendDirectContentRequest({
  required int chatId,
  required int topicId,
  required Map<String, dynamic> inputMessageContent,
  SuggestedPostPrice? price,
  int sendDate = 0,
  int replyToMessageId = 0,
  bool asSuggestedPost = false,
}) => {
  '@type': 'sendMessage',
  'chat_id': chatId,
  'topic_id': {
    '@type': 'messageTopicDirectMessages',
    'direct_messages_chat_topic_id': topicId,
  },
  if (replyToMessageId != 0)
    'reply_to': {
      '@type': 'inputMessageReplyToMessage',
      'message_id': replyToMessageId,
    },
  if (asSuggestedPost || price != null || sendDate != 0)
    'options': {
      '@type': 'messageSendOptions',
      'suggested_post_info': {
        '@type': 'inputSuggestedPostInfo',
        'price': price?.toTdJson(),
        'send_date': sendDate,
      },
    },
  'input_message_content': inputMessageContent,
};

@visibleForTesting
Map<String, dynamic> addSuggestedPostOfferRequest({
  required int chatId,
  required int messageId,
  SuggestedPostPrice? price,
  int sendDate = 0,
}) => {
  '@type': 'addOffer',
  'chat_id': chatId,
  'message_id': messageId,
  'options': {
    '@type': 'messageSendOptions',
    'suggested_post_info': {
      '@type': 'inputSuggestedPostInfo',
      'price': price?.toTdJson(),
      'send_date': sendDate,
    },
  },
};

@visibleForTesting
Map<String, dynamic> approveSuggestedPostRequest({
  required int chatId,
  required int messageId,
  int sendDate = 0,
}) => {
  '@type': 'approveSuggestedPost',
  'chat_id': chatId,
  'message_id': messageId,
  'send_date': sendDate,
};

@visibleForTesting
Map<String, dynamic> declineSuggestedPostRequest({
  required int chatId,
  required int messageId,
  String comment = '',
}) => {
  '@type': 'declineSuggestedPost',
  'chat_id': chatId,
  'message_id': messageId,
  'comment': comment,
};

@visibleForTesting
Map<String, dynamic> directMessagesTopicDraftRequest({
  required int chatId,
  required int topicId,
  required String text,
  required int date,
}) => {
  '@type': 'setChatDraftMessage',
  'chat_id': chatId,
  'topic_id': {
    '@type': 'messageTopicDirectMessages',
    'direct_messages_chat_topic_id': topicId,
  },
  'draft_message': text.trim().isEmpty
      ? null
      : {
          '@type': 'draftMessage',
          'date': date,
          'content': {
            '@type': 'draftMessageContentText',
            'text': {'@type': 'formattedText', 'text': text},
          },
          'effect_id': 0,
          'suggested_post_info': null,
        },
};

class ChannelDirectMessagesService extends ChangeNotifier {
  ChannelDirectMessagesService({required this.chatId, TdClient? client})
    : _client = client ?? TdClient.shared;

  final int chatId;
  final TdClient _client;
  final Map<int, DirectMessagesTopic> _topics = {};
  final Set<int> _resolvingSenders = {};
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool loading = false;
  bool hasMore = true;
  String? error;

  List<DirectMessagesTopic> get topics {
    final result = _topics.values.where((topic) => topic.order != 0).toList();
    result.sort((a, b) {
      final order = b.order.compareTo(a.order);
      return order != 0 ? order : b.id.compareTo(a.id);
    });
    return result;
  }

  Future<void> start() async {
    _subscription ??= _client.subscribe().listen(_handleUpdate);
    _client.send({'@type': 'openChat', 'chat_id': chatId});
    await loadMore();
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _client.query(loadDirectMessagesTopicsRequest(chatId: chatId));
    } on TdError catch (caught) {
      if (caught.code == 404) {
        hasMore = false;
      } else {
        error = caught.message;
      }
    } catch (caught) {
      error = caught.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<DirectMessagesTopic?> refreshTopic(int topicId) async {
    final object = await _client.query({
      '@type': 'getDirectMessagesChatTopic',
      'chat_id': chatId,
      'topic_id': topicId,
    });
    final topic = DirectMessagesTopic.fromTd(object);
    if (topic == null) return null;
    _storeTopic(topic);
    return _topics[topic.id];
  }

  Future<int> revenue(int topicId) async {
    final response = await _client.query({
      '@type': 'getDirectMessagesChatTopicRevenue',
      'chat_id': chatId,
      'topic_id': topicId,
    });
    return response.int64('star_count') ?? 0;
  }

  Future<void> setCanSendUnpaidMessages(
    int topicId, {
    required bool canSendUnpaidMessages,
    required bool refundPayments,
  }) async {
    await _client.query({
      '@type': 'toggleDirectMessagesChatTopicCanSendUnpaidMessages',
      'chat_id': chatId,
      'topic_id': topicId,
      'can_send_unpaid_messages': canSendUnpaidMessages,
      'refund_payments': refundPayments,
    });
    await refreshTopic(topicId);
  }

  Future<void> markUnread(int topicId, bool marked) async {
    await _client.query({
      '@type': 'setDirectMessagesChatTopicIsMarkedAsUnread',
      'chat_id': chatId,
      'topic_id': topicId,
      'is_marked_as_unread': marked,
    });
    await refreshTopic(topicId);
  }

  Future<void> clearHistory(int topicId) async {
    await _client.query({
      '@type': 'deleteDirectMessagesChatTopicHistory',
      'chat_id': chatId,
      'topic_id': topicId,
    });
    await refreshTopic(topicId);
  }

  Future<ChatMessage?> messageByDate(int topicId, int date) async =>
      TDParse.message(
        await _client.query(
          directMessagesTopicMessageByDateRequest(
            chatId: chatId,
            topicId: topicId,
            date: date,
          ),
        ),
      );

  Future<void> clearHistoryByDate(
    int topicId, {
    required int minDate,
    required int maxDate,
  }) async {
    await _client.query(
      deleteDirectMessagesTopicByDateRequest(
        chatId: chatId,
        topicId: topicId,
        minDate: minDate,
        maxDate: maxDate,
      ),
    );
    await refreshTopic(topicId);
  }

  Future<void> unpinAll(int topicId) => _client.query({
    '@type': 'unpinAllDirectMessagesChatTopicMessages',
    'chat_id': chatId,
    'topic_id': topicId,
  });

  Future<void> readAllReactions(int topicId) => _client.query({
    '@type': 'readAllDirectMessagesChatTopicReactions',
    'chat_id': chatId,
    'topic_id': topicId,
  });

  void _handleUpdate(Map<String, dynamic> update) {
    if (update.type != 'updateDirectMessagesChatTopic') return;
    final raw = update.obj('topic');
    final topic = raw == null ? null : DirectMessagesTopic.fromTd(raw);
    if (topic == null || topic.chatId != chatId) return;
    _storeTopic(topic);
  }

  void _storeTopic(DirectMessagesTopic topic) {
    final existing = _topics[topic.id];
    final resolved = topic.copyWith(
      senderTitle: existing?.senderTitle,
      senderPhoto: existing?.senderPhoto,
    );
    _topics[topic.id] = resolved;
    notifyListeners();
    if (resolved.senderTitle.isEmpty) unawaited(_resolveSender(resolved));
  }

  Future<void> _resolveSender(DirectMessagesTopic topic) async {
    if (!_resolvingSenders.add(topic.id)) return;
    try {
      final sender = topic.senderId;
      if (sender.type == 'messageSenderUser') {
        final userId = sender.int64('user_id');
        if (userId == null) return;
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': userId,
        });
        _topics[topic.id] = (_topics[topic.id] ?? topic).copyWith(
          senderTitle: TDParse.userName(user),
          senderPhoto: TDParse.smallPhoto(user.obj('profile_photo')),
        );
      } else if (sender.type == 'messageSenderChat') {
        final senderChatId = sender.int64('chat_id');
        if (senderChatId == null) return;
        final chat = await _client.query({
          '@type': 'getChat',
          'chat_id': senderChatId,
        });
        _topics[topic.id] = (_topics[topic.id] ?? topic).copyWith(
          senderTitle: chat.str('title') ?? '',
          senderPhoto: TDParse.smallPhoto(chat.obj('photo')),
        );
      }
      notifyListeners();
    } catch (_) {
      // Sender metadata is decorative; the topic remains usable by identifier.
    } finally {
      _resolvingSenders.remove(topic.id);
    }
  }

  @override
  void dispose() {
    _client.send({'@type': 'closeChat', 'chat_id': chatId});
    _subscription?.cancel();
    super.dispose();
  }
}

class ChannelDirectMessageTopicController extends ChangeNotifier {
  ChannelDirectMessageTopicController({
    required this.chatId,
    required this.topicId,
    TdClient? client,
  }) : _client = client ?? TdClient.shared;

  final int chatId;
  final int topicId;
  final TdClient _client;
  final List<ChatMessage> _messages = [];
  final Map<int, SuggestedPostCapabilities> capabilities = {};
  final Set<int> _resolvingSenders = {};
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool loading = false;
  bool sending = false;
  bool hasOlder = true;
  String? error;
  int? meId;
  String meName = '';
  TdFileRef? mePhoto;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  Future<void> start() async {
    _subscription ??= _client.subscribe().listen(_handleUpdate);
    _client.send({'@type': 'openChat', 'chat_id': chatId});
    unawaited(_loadMe());
    await loadHistory();
  }

  Future<void> _loadMe() async {
    try {
      final me = await _client.query({'@type': 'getMe'});
      meId = me.int64('id');
      meName = TDParse.userName(me);
      mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadHistory({bool older = false}) async {
    if (loading || (older && !hasOlder)) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final from = older && _messages.isNotEmpty ? _messages.first.id : 0;
      final knownIds = _messages.map((message) => message.id).toSet();
      final response = await _client.query(
        directMessagesTopicHistoryRequest(
          chatId: chatId,
          topicId: topicId,
          fromMessageId: from,
        ),
      );
      final parsed = (response.objects('messages') ?? const [])
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      if (parsed.isEmpty) {
        if (older) hasOlder = false;
      } else {
        if (older && parsed.every((message) => knownIds.contains(message.id))) {
          hasOlder = false;
        }
        _merge(parsed);
        unawaited(_hydrate(parsed));
        await _markRead();
      }
    } catch (caught) {
      error = caught is TdError ? caught.message : caught.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<SuggestedPostLimits> loadLimits() async {
    Future<int> option(String name) async {
      try {
        final response = await _client.query({
          '@type': 'getOption',
          'name': name,
        });
        return response.int64('value') ?? 0;
      } catch (_) {
        return 0;
      }
    }

    final values = await Future.wait([
      option('suggested_post_star_count_min'),
      option('suggested_post_star_count_max'),
      option('suggested_post_gram_cent_count_min'),
      option('suggested_post_gram_cent_count_max'),
      option('suggested_post_send_delay_min'),
      option('suggested_post_send_delay_max'),
    ]);
    return SuggestedPostLimits(
      minimumStars: values[0],
      maximumStars: values[1],
      minimumTonHundredths: values[2],
      maximumTonHundredths: values[3],
      minimumSendDelay: values[4],
      maximumSendDelay: values[5],
    );
  }

  Future<void> sendText(
    String text, {
    SuggestedPostPrice? price,
    int sendDate = 0,
    int replyToMessageId = 0,
    bool asSuggestedPost = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || sending) return;
    sending = true;
    notifyListeners();
    try {
      final response = await _client.query(
        sendDirectMessageRequest(
          chatId: chatId,
          topicId: topicId,
          text: trimmed,
          price: price,
          sendDate: sendDate,
          replyToMessageId: replyToMessageId,
          asSuggestedPost: asSuggestedPost,
        ),
      );
      final message = TDParse.message(response);
      if (message != null) {
        _merge([message]);
        unawaited(_hydrate([message]));
      }
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> sendAttachment(
    OutgoingAttachment attachment, {
    String caption = '',
    SuggestedPostPrice? price,
    int sendDate = 0,
    int replyToMessageId = 0,
    bool asSuggestedPost = false,
  }) async {
    if (sending) return;
    sending = true;
    notifyListeners();
    try {
      final resolved = await resolveAttachmentDimensions(attachment);
      final response = await _client.query(
        sendDirectContentRequest(
          chatId: chatId,
          topicId: topicId,
          inputMessageContent: attachmentInputMessageContent(
            resolved,
            caption: caption,
          ),
          price: price,
          sendDate: sendDate,
          replyToMessageId: replyToMessageId,
          asSuggestedPost: asSuggestedPost,
        ),
      );
      final message = TDParse.message(response);
      if (message != null) {
        _merge([message]);
        unawaited(_hydrate([message]));
      }
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> addOffer(
    int messageId, {
    SuggestedPostPrice? price,
    int sendDate = 0,
  }) async {
    final response = await _client.query(
      addSuggestedPostOfferRequest(
        chatId: chatId,
        messageId: messageId,
        price: price,
        sendDate: sendDate,
      ),
    );
    final message = TDParse.message(response);
    if (message != null) {
      _merge([message]);
      unawaited(_hydrate([message]));
    }
  }

  Future<void> approve(int messageId, {int sendDate = 0}) async {
    await _client.query(
      approveSuggestedPostRequest(
        chatId: chatId,
        messageId: messageId,
        sendDate: sendDate,
      ),
    );
    await _refreshMessage(messageId);
  }

  Future<void> decline(int messageId, {String comment = ''}) async {
    await _client.query(
      declineSuggestedPostRequest(
        chatId: chatId,
        messageId: messageId,
        comment: comment.trim(),
      ),
    );
    await _refreshMessage(messageId);
  }

  Future<void> editText(int messageId, String text) async {
    await _client.query({
      '@type': 'editMessageText',
      'chat_id': chatId,
      'message_id': messageId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': text.trim()},
      },
    });
    await _refreshMessage(messageId);
  }

  Future<void> saveDraft(String text) => _client.query(
    directMessagesTopicDraftRequest(
      chatId: chatId,
      topicId: topicId,
      text: text,
      date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
  );

  Future<void> _refreshMessage(int messageId) async {
    final response = await _client.query({
      '@type': 'getMessage',
      'chat_id': chatId,
      'message_id': messageId,
    });
    final message = TDParse.message(response);
    if (message != null) {
      _merge([message]);
      await _hydrate([message]);
    }
  }

  Future<void> _hydrate(Iterable<ChatMessage> messages) async {
    await Future.wait([
      for (final message in messages) ...[
        _resolveSender(message),
        _resolveReply(message),
        _loadCapabilities(message),
      ],
    ]);
  }

  Future<void> _resolveSender(ChatMessage message) async {
    final senderId = message.senderId;
    if (senderId == null || !_resolvingSenders.add(message.id)) return;
    try {
      if (message.senderIsChat) {
        final chat = await _client.query({
          '@type': 'getChat',
          'chat_id': senderId,
        });
        message.senderName = chat.str('title') ?? '';
        message.senderPhoto = TDParse.smallPhoto(chat.obj('photo'));
      } else {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        message.senderName = TDParse.userName(user);
        message.senderPhoto = TDParse.smallPhoto(user.obj('profile_photo'));
      }
      notifyListeners();
    } catch (_) {
      // Keep the transcript functional if a sender was deleted or inaccessible.
    } finally {
      _resolvingSenders.remove(message.id);
    }
  }

  Future<void> _resolveReply(ChatMessage message) async {
    final replyToMessageId = message.replyToMessageId;
    if (replyToMessageId == null || message.replyToPreview != null) return;
    ChatMessage? quoted;
    for (final candidate in _messages) {
      if (candidate.id == replyToMessageId) {
        quoted = candidate;
        break;
      }
    }
    try {
      quoted ??= TDParse.message(
        await _client.query({
          '@type': 'getMessage',
          'chat_id': chatId,
          'message_id': replyToMessageId,
        }),
      );
    } catch (_) {}
    if (quoted == null) return;
    message.replyToPreview = quoted.text;
    message.replyToDate = quoted.date;
    message.replyToImage = quoted.image;
    message.replyToImageWidth = quoted.imageWidth;
    message.replyToImageHeight = quoted.imageHeight;
    message.replyToSender = quoted.isOutgoing
        ? meName
        : quoted.senderName ?? '';
    notifyListeners();
  }

  Future<void> _loadCapabilities(ChatMessage message) async {
    try {
      final response = await _client.query({
        '@type': 'getMessageProperties',
        'chat_id': chatId,
        'message_id': message.id,
      });
      capabilities[message.id] = SuggestedPostCapabilities.fromTd(response);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _markRead() async {
    if (_messages.isEmpty) return;
    final latest = _messages.last.id;
    await _client.query({
      '@type': 'viewMessages',
      'chat_id': chatId,
      'message_ids': [latest],
      'source': {'@type': 'messageSourceDirectMessagesChatTopicHistory'},
      'force_read': true,
    });
  }

  void _handleUpdate(Map<String, dynamic> update) {
    switch (update.type) {
      case 'updateNewMessage':
        final raw = update.obj('message');
        if (!_belongsToTopic(raw)) return;
        final message = raw == null ? null : TDParse.message(raw);
        if (message == null) return;
        _merge([message]);
        unawaited(_hydrate([message]));
        unawaited(_markRead());
      case 'updateMessageSuggestedPostInfo':
      case 'updateMessageContent':
      case 'updateMessageEdited':
      case 'updateMessageInteractionInfo':
        if (update.int64('chat_id') != chatId) return;
        final id = update.int64('message_id');
        if (id == null || !_messages.any((message) => message.id == id)) return;
        unawaited(_refreshMessage(id));
      case 'updateDeleteMessages':
        if (update.int64('chat_id') != chatId) return;
        final ids = update.int64Array('message_ids')?.toSet() ?? const <int>{};
        _messages.removeWhere((message) => ids.contains(message.id));
        notifyListeners();
    }
  }

  bool _belongsToTopic(Map<String, dynamic>? message) {
    if (message == null || message.int64('chat_id') != chatId) return false;
    final topic = message.obj('topic_id');
    return topic?.type == 'messageTopicDirectMessages' &&
        topic?.int64('direct_messages_chat_topic_id') == topicId;
  }

  void _merge(Iterable<ChatMessage> incoming) {
    final byId = {for (final message in _messages) message.id: message};
    for (final message in incoming) {
      byId[message.id] = message;
    }
    _messages
      ..clear()
      ..addAll(byId.values)
      ..sort((a, b) => a.id.compareTo(b.id));
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
