import 'dart:convert';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

typedef BotPlatformQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

int? forumTopicIdFromResult(Map<String, dynamic> result) {
  final info = result.obj('info') ?? result;
  return info.integer('forum_topic_id') ??
      info.int64('message_thread_id') ??
      result.integer('forum_topic_id') ??
      result.int64('message_thread_id');
}

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
    this.queryId = 0,
    required this.type,
    required this.title,
    required this.description,
    this.thumbnail,
    this.emoji = '',
  });

  factory BotInlineResult.fromJson(
    Map<String, dynamic> value, {
    int queryId = 0,
  }) {
    final type = value.type ?? '';
    final contact = value.obj('contact');
    final venue = value.obj('venue');
    final game = value.obj('game');
    final animation = value.obj('animation');
    final audio = value.obj('audio');
    final document = value.obj('document');
    final photo = value.obj('photo');
    final sticker = value.obj('sticker');
    final video = value.obj('video');
    final firstName = contact?.str('first_name') ?? '';
    final lastName = contact?.str('last_name') ?? '';
    final contactName = '$firstName $lastName'.trim();
    final title = switch (type) {
      'inlineQueryResultContact' => contactName,
      'inlineQueryResultVenue' => venue?.str('title') ?? '',
      'inlineQueryResultGame' => game?.str('title') ?? '',
      'inlineQueryResultAudio' => audio?.str('title') ?? '',
      'inlineQueryResultDocument' =>
        value.str('title') ?? document?.str('file_name') ?? '',
      'inlineQueryResultSticker' => sticker?.str('emoji') ?? 'Sticker',
      'inlineQueryResultAnimation' =>
        value.str('title') ?? animation?.str('file_name') ?? 'GIF',
      'inlineQueryResultPhoto' => value.str('title') ?? 'Photo',
      'inlineQueryResultVideo' =>
        value.str('title') ?? video?.str('file_name') ?? 'Video',
      'inlineQueryResultVoiceNote' => value.str('title') ?? 'Voice',
      'inlineQueryResultLocation' => value.str('title') ?? 'Location',
      _ => value.str('title') ?? '',
    };
    final description = switch (type) {
      'inlineQueryResultContact' => contact?.str('phone_number') ?? '',
      'inlineQueryResultVenue' => venue?.str('address') ?? '',
      'inlineQueryResultGame' => game?.str('description') ?? '',
      'inlineQueryResultAudio' => audio?.str('performer') ?? '',
      _ => value.str('description') ?? value.str('url') ?? '',
    };
    return BotInlineResult(
      id: value.str('id') ?? '',
      queryId: queryId,
      type: type,
      title: title.trim().isEmpty ? _fallbackTitle(type) : title.trim(),
      description: description.trim(),
      thumbnail: _parseThumbnail(
        value: value,
        photo: photo,
        video: video,
        animation: animation,
        document: document,
        audio: audio,
        sticker: sticker,
        game: game,
        venue: venue,
      ),
      emoji: (sticker?.str('emoji') ?? '').trim(),
    );
  }

  final String id;
  final int queryId;
  final String type;
  final String title;
  final String description;
  final TdFileRef? thumbnail;
  final String emoji;

  BotInlineResult withQueryId(int queryId) => BotInlineResult(
    id: id,
    queryId: queryId,
    type: type,
    title: title,
    description: description,
    thumbnail: thumbnail,
    emoji: emoji,
  );

  bool get isGalleryItem => switch (type) {
    'inlineQueryResultPhoto' ||
    'inlineQueryResultAnimation' ||
    'inlineQueryResultSticker' => true,
    _ => false,
  };

  static TdFileRef? _parseThumbnail({
    required Map<String, dynamic> value,
    required Map<String, dynamic>? photo,
    required Map<String, dynamic>? video,
    required Map<String, dynamic>? animation,
    required Map<String, dynamic>? document,
    required Map<String, dynamic>? audio,
    required Map<String, dynamic>? sticker,
    required Map<String, dynamic>? game,
    required Map<String, dynamic>? venue,
  }) {
    final directThumb = TDParse.fileRef(value.obj('thumbnail')?.obj('file'));
    if (directThumb != null) return directThumb;
    if (photo != null) {
      final attachment = TDParse.photoAttachment(photo);
      if (attachment.image != null) {
        return attachment.image!.thumbnail ?? attachment.image;
      }
    }
    if (sticker != null) {
      final thumb = TDParse.fileRef(sticker.obj('thumbnail')?.obj('file'));
      if (thumb != null) return thumb;
      final fmt = sticker.obj('format')?.type;
      if (fmt == null || fmt == 'stickerFormatWebp') {
        return TDParse.fileRef(sticker.obj('sticker'));
      }
    }
    if (animation != null) {
      final thumb = TDParse.fileRef(animation.obj('thumbnail')?.obj('file'));
      if (thumb != null) return thumb;
    }
    if (video != null) {
      final thumb = TDParse.fileRef(video.obj('thumbnail')?.obj('file'));
      if (thumb != null) return thumb;
    }
    if (document != null) {
      final thumb = TDParse.fileRef(document.obj('thumbnail')?.obj('file'));
      if (thumb != null) return thumb;
    }
    if (audio != null) {
      final thumb = TDParse.fileRef(
        audio.obj('album_cover_thumbnail')?.obj('file'),
      );
      if (thumb != null) return thumb;
    }
    if (game != null) {
      final attachment = TDParse.photoAttachment(game.obj('photo'));
      if (attachment.image != null) {
        return attachment.image!.thumbnail ?? attachment.image;
      }
    }
    if (venue != null) {
      final thumb = TDParse.fileRef(venue.obj('thumbnail')?.obj('file'));
      if (thumb != null) return thumb;
    }
    return null;
  }

  static String _fallbackTitle(String type) => switch (type) {
    'inlineQueryResultAnimation' => 'GIF',
    'inlineQueryResultAudio' => 'Audio',
    'inlineQueryResultContact' => 'Contact',
    'inlineQueryResultDocument' => 'File',
    'inlineQueryResultGame' => 'Game',
    'inlineQueryResultLocation' => 'Location',
    'inlineQueryResultPhoto' => 'Photo',
    'inlineQueryResultSticker' => 'Sticker',
    'inlineQueryResultVenue' => 'Place',
    'inlineQueryResultVideo' => 'Video',
    'inlineQueryResultVoiceNote' => 'Voice',
    _ => 'Result',
  };
}

enum BotInlineResultsButtonKind { startBot, webApp }

class BotInlineResultsButton {
  const BotInlineResultsButton({
    required this.text,
    required this.kind,
    this.startParameter = '',
    this.webAppUrl = '',
  });

  static BotInlineResultsButton? fromJson(Map<String, dynamic>? value) {
    if (value == null) return null;
    final text = (value.str('text') ?? '').trim();
    if (text.isEmpty) return null;
    final type = value.obj('type');
    return switch (type?.type) {
      'inlineQueryResultsButtonTypeStartBot' => BotInlineResultsButton(
        text: text,
        kind: BotInlineResultsButtonKind.startBot,
        startParameter: type?.str('parameter') ?? '',
      ),
      'inlineQueryResultsButtonTypeWebApp' => BotInlineResultsButton(
        text: text,
        kind: BotInlineResultsButtonKind.webApp,
        webAppUrl: type?.str('url') ?? '',
      ),
      _ => null,
    };
  }

  final String text;
  final BotInlineResultsButtonKind kind;
  final String startParameter;
  final String webAppUrl;

  bool get isWebApp => kind == BotInlineResultsButtonKind.webApp;
}

class BotInlineResultsPage {
  const BotInlineResultsPage({
    required this.queryId,
    required this.results,
    required this.nextOffset,
    this.gallery = false,
    this.button,
  });

  factory BotInlineResultsPage.fromJson(Map<String, dynamic> value) {
    final queryId = value.int64('inline_query_id') ?? 0;
    return BotInlineResultsPage(
      queryId: queryId,
      results: (value.objects('results') ?? const [])
          .map((raw) => BotInlineResult.fromJson(raw, queryId: queryId))
          .where((result) => result.id.isNotEmpty)
          .toList(),
      nextOffset: value.str('next_offset') ?? '',
      gallery: value.boolean('is_gallery') ?? false,
      button: BotInlineResultsButton.fromJson(value.obj('button')),
    );
  }

  final int queryId;
  final List<BotInlineResult> results;
  final String nextOffset;
  final bool gallery;
  final BotInlineResultsButton? button;

  bool get hasMore => nextOffset.trim().isNotEmpty;

  bool get rendersAsGallery =>
      gallery &&
      results.isNotEmpty &&
      results.every((result) => result.isGalleryItem);

  BotInlineResultsPage mergeNextPage(BotInlineResultsPage next) {
    final existing = <BotInlineResult>[
      for (final item in results)
        item.queryId != 0 ? item : item.withQueryId(queryId),
    ];
    final incoming = <BotInlineResult>[
      for (final item in next.results)
        item.queryId != 0 ? item : item.withQueryId(next.queryId),
    ];
    // Deduplicate by result id: TDLib may re-serve an earlier result under
    // the new page's query id, and the first occurrence — with the query id
    // it was actually returned under — is the one that can be sent.
    final seen = <String>{for (final item in existing) item.id};
    final merged = <BotInlineResult>[
      ...existing,
      for (final item in incoming)
        if (seen.add(item.id)) item,
    ];
    return BotInlineResultsPage(
      queryId: next.queryId != 0 ? next.queryId : queryId,
      results: merged,
      nextOffset: next.nextOffset,
      gallery: gallery,
      button: button ?? next.button,
    );
  }
}

class BotPlatformService {
  BotPlatformService({BotPlatformQuery? query, int? queryForSlot})
    : _query = query ?? _pinnedQuery(queryForSlot);

  /// Routes every request to the account slot that owns the caller's chat.
  ///
  /// Bot, inline-query and chat ids are account-scoped: resolving them on the
  /// foreground account after a switch would target a different conversation
  /// with the same numeric id. Null keeps the foreground resolution.
  static BotPlatformQuery _pinnedQuery(int? accountSlot) => accountSlot == null
      ? TdClient.shared.query
      : (Map<String, dynamic> request) =>
            TdClient.shared.queryForSlot(request, accountSlot);

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
    Map<String, dynamic>? options,
  }) => _query({
    '@type': 'sendInlineQueryResultMessage',
    'chat_id': chatId,
    'topic_id': topicId,
    'reply_to': replyTo,
    'options': options ?? const {'@type': 'messageSendOptions'},
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
