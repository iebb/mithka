import 'dart:convert';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef BotPlatformQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

enum BotButtonStyle { standard, primary, danger, success }

class BotButtonPresentation {
  const BotButtonPresentation({
    required this.text,
    required this.style,
    required this.customEmojiId,
    required this.type,
  });

  factory BotButtonPresentation.fromJson(Map<String, dynamic> value) =>
      BotButtonPresentation(
        text: value.str('text') ?? '',
        style: switch (value.obj('style')?.type ?? value['style']) {
          'buttonStylePrimary' => BotButtonStyle.primary,
          'buttonStyleDanger' => BotButtonStyle.danger,
          'buttonStyleSuccess' => BotButtonStyle.success,
          _ => BotButtonStyle.standard,
        },
        customEmojiId: value.int64('icon_custom_emoji_id') ?? 0,
        type: value.obj('type')?.type ?? '',
      );

  final String text;
  final BotButtonStyle style;
  final int customEmojiId;
  final String type;
}

class BotPlatformCapabilities {
  const BotPlatformCapabilities({
    required this.userId,
    required this.username,
    required this.inlineMode,
    required this.inlinePlaceholder,
    required this.needsLocation,
    required this.supportsGuestQueries,
    required this.hasTopics,
    required this.allowsUsersToCreateTopics,
    required this.canManageBots,
    required this.canBeAddedToAttachmentMenu,
  });

  final int userId;
  final String username;
  final bool inlineMode;
  final String inlinePlaceholder;
  final bool needsLocation;
  final bool supportsGuestQueries;
  final bool hasTopics;
  final bool allowsUsersToCreateTopics;
  final bool canManageBots;
  final bool canBeAddedToAttachmentMenu;
}

class BotGuestQuery {
  const BotGuestQuery({
    required this.id,
    required this.message,
    required this.referenceMessages,
  });

  factory BotGuestQuery.fromUpdate(Map<String, dynamic> update) {
    if (update.type != 'updateNewGuestQuery') {
      throw const FormatException('NOT_GUEST_QUERY_UPDATE');
    }
    final id = update.int64('id');
    final message = update.obj('message');
    if (id == null || message == null) {
      throw const FormatException('GUEST_QUERY_INVALID');
    }
    return BotGuestQuery(
      id: id,
      message: message,
      referenceMessages: update.objects('reference_messages') ?? const [],
    );
  }

  final int id;
  final Map<String, dynamic> message;
  final List<Map<String, dynamic>> referenceMessages;
}

class BotInlineInvocation {
  const BotInlineInvocation({required this.username, required this.query});

  static BotInlineInvocation? fromText(String text) {
    final match = RegExp(
      r'^@([A-Za-z0-9_]{3,})\s(.*)$',
      dotAll: true,
    ).firstMatch(text);
    if (match == null) return null;
    return BotInlineInvocation(
      username: match.group(1)!,
      query: match.group(2) ?? '',
    );
  }

  final String username;
  final String query;
}

class BotInlineResult {
  const BotInlineResult({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
  });

  factory BotInlineResult.fromJson(Map<String, dynamic> value) {
    final type = value.type ?? '';
    final contact = value.obj('contact');
    final venue = value.obj('venue');
    final game = value.obj('game');
    final animation = value.obj('animation');
    final audio = value.obj('audio');
    final document = value.obj('document');
    final sticker = value.obj('sticker');
    final video = value.obj('video');
    final firstName = contact?.str('first_name') ?? '';
    final lastName = contact?.str('last_name') ?? '';
    final contactName = '$firstName $lastName'.trim();
    final title = switch (type) {
      'inlineQueryResultContact' => contactName,
      'inlineQueryResultVenue' => venue?.str('title') ?? '',
      'inlineQueryResultGame' => game?.str('title') ?? '',
      'inlineQueryResultAnimation' =>
        value.str('title') ?? animation?.str('file_name') ?? '',
      'inlineQueryResultAudio' => audio?.str('title') ?? '',
      'inlineQueryResultSticker' => sticker?.str('emoji') ?? '',
      'inlineQueryResultVoiceNote' => value.str('title') ?? '',
      _ => value.str('title') ?? '',
    };
    final description = switch (type) {
      'inlineQueryResultContact' => contact?.str('phone_number') ?? '',
      'inlineQueryResultVenue' => venue?.str('address') ?? '',
      'inlineQueryResultGame' => game?.str('description') ?? '',
      'inlineQueryResultAudio' => audio?.str('performer') ?? '',
      'inlineQueryResultDocument' =>
        value.str('description') ?? document?.str('file_name') ?? '',
      'inlineQueryResultPhoto' => value.str('description') ?? '',
      'inlineQueryResultVideo' =>
        value.str('description') ?? video?.str('file_name') ?? '',
      _ => value.str('description') ?? '',
    };
    return BotInlineResult(
      id: value.str('id') ?? '',
      type: type,
      title: title.trim().isEmpty ? _fallbackTitle(type) : title.trim(),
      description: description.trim(),
    );
  }

  final String id;
  final String type;
  final String title;
  final String description;

  static String _fallbackTitle(String type) => switch (type) {
    'inlineQueryResultArticle' => 'Article',
    'inlineQueryResultAnimation' => 'Animation',
    'inlineQueryResultAudio' => 'Audio',
    'inlineQueryResultContact' => 'Contact',
    'inlineQueryResultDocument' => 'Document',
    'inlineQueryResultGame' => 'Game',
    'inlineQueryResultLocation' => 'Location',
    'inlineQueryResultPhoto' => 'Photo',
    'inlineQueryResultSticker' => 'Sticker',
    'inlineQueryResultVenue' => 'Venue',
    'inlineQueryResultVideo' => 'Video',
    'inlineQueryResultVoiceNote' => 'Voice message',
    _ => 'Result',
  };
}

class BotInlineResultsPage {
  const BotInlineResultsPage({
    required this.queryId,
    required this.results,
    required this.nextOffset,
  });

  factory BotInlineResultsPage.fromJson(Map<String, dynamic> value) =>
      BotInlineResultsPage(
        queryId: value.int64('inline_query_id') ?? 0,
        results: (value.objects('results') ?? const [])
            .map(BotInlineResult.fromJson)
            .where((result) => result.id.isNotEmpty)
            .toList(),
        nextOffset: value.str('next_offset') ?? '',
      );

  final int queryId;
  final List<BotInlineResult> results;
  final String nextOffset;
}

class BotPlatformService {
  BotPlatformService({BotPlatformQuery? query})
    : _query = query ?? TdClient.shared.query;

  final BotPlatformQuery _query;

  Future<BotPlatformCapabilities> capabilitiesForUsername(
    String username,
  ) async {
    final chat = await _query({
      '@type': 'searchPublicChat',
      'username': username.replaceFirst('@', ''),
    });
    final userId = chat.obj('type')?.int64('user_id');
    if (userId == null) throw StateError('BOT_NOT_FOUND');
    return capabilitiesForUserId(userId, fallbackUsername: username);
  }

  Future<BotPlatformCapabilities> capabilitiesForUserId(
    int userId, {
    String fallbackUsername = '',
  }) async {
    final user = await _query({'@type': 'getUser', 'user_id': userId});
    return _capabilitiesFromUser(
      user,
      userId: userId,
      fallbackUsername: fallbackUsername,
    );
  }

  Future<bool> currentAccountIsBot() async {
    final me = await _query({'@type': 'getMe'});
    return me.obj('type')?.type == 'userTypeBot';
  }

  BotPlatformCapabilities _capabilitiesFromUser(
    Map<String, dynamic> user, {
    required int userId,
    required String fallbackUsername,
  }) {
    final type = user.obj('type');
    if (type?.type != 'userTypeBot') throw StateError('USER_NOT_BOT');
    final usernames = user.obj('usernames');
    final active = usernames?['active_usernames'];
    final editable = usernames?.str('editable_username');
    return BotPlatformCapabilities(
      userId: userId,
      username: editable != null && editable.isNotEmpty
          ? editable
          : (active is List ? active.whereType<String>().firstOrNull : null) ??
                fallbackUsername.replaceFirst('@', ''),
      inlineMode: type?.boolean('is_inline') ?? false,
      inlinePlaceholder: type?.str('inline_query_placeholder') ?? '',
      needsLocation: type?.boolean('need_location') ?? false,
      supportsGuestQueries: type?.boolean('supports_guest_queries') ?? false,
      hasTopics: type?.boolean('has_topics') ?? false,
      allowsUsersToCreateTopics:
          type?.boolean('allows_users_to_create_topics') ?? false,
      canManageBots: type?.boolean('can_manage_bots') ?? false,
      canBeAddedToAttachmentMenu:
          type?.boolean('can_be_added_to_attachment_menu') ?? false,
    );
  }

  Future<Map<String, dynamic>> inlineResults({
    required int botUserId,
    required int chatId,
    required String query,
    String offset = '',
    Map<String, dynamic>? location,
  }) => _query({
    '@type': 'getInlineQueryResults',
    'bot_user_id': botUserId,
    'chat_id': chatId,
    'user_location': location,
    'query': query,
    'offset': offset,
  });

  Future<Map<String, dynamic>> sendInlineResult({
    required int chatId,
    required int queryId,
    required String resultId,
    bool hideViaBot = false,
    Map<String, dynamic>? topicId,
    Map<String, dynamic>? replyTo,
  }) => _query({
    '@type': 'sendInlineQueryResultMessage',
    'chat_id': chatId,
    'topic_id': topicId,
    'reply_to': replyTo,
    'options': {'@type': 'messageSendOptions'},
    'query_id': queryId,
    'result_id': resultId,
    'hide_via_bot': hideViaBot,
  });

  Future<Map<String, dynamic>> preparedKeyboardButton({
    required int botUserId,
    required String preparedButtonId,
  }) => _query({
    '@type': 'getPreparedKeyboardButton',
    'bot_user_id': botUserId,
    'prepared_button_id': preparedButtonId,
  });

  Future<Map<String, dynamic>> createBotTopic({
    required int chatId,
    required String name,
    int iconColor = 0x6fb9f0,
    int iconCustomEmojiId = 0,
    bool isNameImplicit = false,
  }) => _query({
    '@type': 'createForumTopic',
    'chat_id': chatId,
    'name': name.trim(),
    'is_name_implicit': isNameImplicit,
    'icon': {
      '@type': 'forumTopicIcon',
      'color': iconColor,
      'custom_emoji_id': iconCustomEmojiId,
    },
  });

  Future<Map<String, dynamic>> createManagedBot({
    required int managerBotUserId,
    required String name,
    required String username,
    bool viaLink = false,
  }) => _query({
    '@type': 'createBot',
    'manager_bot_user_id': managerBotUserId,
    'name': name.trim(),
    'username': username.replaceFirst('@', '').trim(),
    'via_link': viaLink,
  });

  Future<Map<String, dynamic>> answerGuestQuery({
    required int guestQueryId,
    required Map<String, dynamic> result,
  }) => _query({
    '@type': 'answerGuestQuery',
    'guest_query_id': guestQueryId,
    'result': result,
  });

  Future<void> updateBotAutomationStatus({
    required int pendingUpdateCount,
    String errorMessage = '',
  }) => _query({
    '@type': 'setBotUpdatesStatus',
    'pending_update_count': pendingUpdateCount,
    'error_message': errorMessage,
  });

  static String callbackData(Map<String, dynamic> buttonType) {
    final value = buttonType['data'];
    if (value is String) {
      try {
        return utf8.decode(base64Decode(value));
      } catch (_) {
        return value;
      }
    }
    return '';
  }
}
