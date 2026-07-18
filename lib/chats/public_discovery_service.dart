import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

class PublicDiscoveryMessagePage {
  const PublicDiscoveryMessagePage({
    required this.messages,
    required this.nextOffset,
    this.requiredStarCount = 0,
    this.limitsExceeded = false,
  });

  final List<Map<String, dynamic>> messages;
  final String nextOffset;
  final int requiredStarCount;
  final bool limitsExceeded;

  bool get requiresStarConfirmation => requiredStarCount > 0;
}

class PublicDiscoveryService {
  const PublicDiscoveryService();

  Future<List<int>> recommendedChannelIds() async {
    final response = await TdClient.shared.query(recommendedChatsRequest());
    return response.int64Array('chat_ids') ?? const [];
  }

  Future<List<int>> searchChannelIds(String query) async {
    final response = await TdClient.shared.query(
      publicChatsRequest(query: query, type: 'searchChatTypeFilterChannel'),
    );
    return response.int64Array('chat_ids') ?? const [];
  }

  Future<List<int>> searchBotChatIds(String query) async {
    final response = await TdClient.shared.query(
      publicChatsRequest(query: query, type: 'searchChatTypeFilterBot'),
    );
    return response.int64Array('chat_ids') ?? const [];
  }

  Future<List<int>> similarChannelIds(int chatId) async {
    final response = await TdClient.shared.query(similarChatsRequest(chatId));
    return response.int64Array('chat_ids') ?? const [];
  }

  Future<List<int>> similarBotUserIds(int botUserId) async {
    final response = await TdClient.shared.query(similarBotsRequest(botUserId));
    return response.int64Array('user_ids') ?? const [];
  }

  Future<void> markSimilarChannelOpened({
    required int sourceChatId,
    required int openedChatId,
  }) => TdClient.shared.query(
    openSimilarChatRequest(
      sourceChatId: sourceChatId,
      openedChatId: openedChatId,
    ),
  );

  Future<void> markSimilarBotOpened({
    required int sourceBotUserId,
    required int openedBotUserId,
  }) => TdClient.shared.query(
    openSimilarBotRequest(
      sourceBotUserId: sourceBotUserId,
      openedBotUserId: openedBotUserId,
    ),
  );

  Future<PublicDiscoveryMessagePage> searchPublicPosts({
    required String query,
    String offset = '',
    int? agreedStarCount,
  }) async {
    final tag = normalizedTag(query);
    if (tag != null) {
      final response = await TdClient.shared.query(
        publicTagSearchRequest(tag: tag, offset: offset),
      );
      return PublicDiscoveryMessagePage(
        messages: response.objects('messages') ?? const [],
        nextOffset: response.str('next_offset') ?? '',
      );
    }

    if (offset.isEmpty && agreedStarCount == null) {
      final limits = await TdClient.shared.query(
        publicPostLimitsRequest(query),
      );
      final isFree = limits.boolean('is_current_query_free') ?? false;
      final starCount = limits.int64('star_count') ?? 0;
      if (!isFree && starCount > 0) {
        return PublicDiscoveryMessagePage(
          messages: const [],
          nextOffset: '',
          requiredStarCount: starCount,
        );
      }
    }

    final response = await TdClient.shared.query(
      publicPostSearchRequest(
        query: query,
        offset: offset,
        starCount: agreedStarCount ?? 0,
      ),
    );
    return PublicDiscoveryMessagePage(
      messages: response.objects('messages') ?? const [],
      nextOffset: response.str('next_offset') ?? '',
      limitsExceeded: response.boolean('are_limits_exceeded') ?? false,
    );
  }

  Future<PublicDiscoveryMessagePage> searchGlobalMedia({
    required String query,
    required String filterType,
    String offset = '',
  }) async {
    final response = await TdClient.shared.query(
      globalMediaSearchRequest(
        query: query,
        filterType: filterType,
        offset: offset,
      ),
    );
    return PublicDiscoveryMessagePage(
      messages: response.objects('messages') ?? const [],
      nextOffset: response.str('next_offset') ?? '',
    );
  }

  @visibleForTesting
  static Map<String, dynamic> recommendedChatsRequest() => {
    '@type': 'getRecommendedChats',
  };

  @visibleForTesting
  static Map<String, dynamic> publicChatsRequest({
    required String query,
    required String type,
  }) => {
    '@type': 'searchPublicChats',
    'query': query,
    'type_filter': {'@type': type},
  };

  @visibleForTesting
  static Map<String, dynamic> similarChatsRequest(int chatId) => {
    '@type': 'getChatSimilarChats',
    'chat_id': chatId,
  };

  @visibleForTesting
  static Map<String, dynamic> similarBotsRequest(int botUserId) => {
    '@type': 'getBotSimilarBots',
    'bot_user_id': botUserId,
  };

  @visibleForTesting
  static Map<String, dynamic> openSimilarChatRequest({
    required int sourceChatId,
    required int openedChatId,
  }) => {
    '@type': 'openChatSimilarChat',
    'chat_id': sourceChatId,
    'opened_chat_id': openedChatId,
  };

  @visibleForTesting
  static Map<String, dynamic> openSimilarBotRequest({
    required int sourceBotUserId,
    required int openedBotUserId,
  }) => {
    '@type': 'openBotSimilarBot',
    'bot_user_id': sourceBotUserId,
    'opened_bot_user_id': openedBotUserId,
  };

  @visibleForTesting
  static Map<String, dynamic> publicPostLimitsRequest(String query) => {
    '@type': 'getPublicPostSearchLimits',
    'query': query,
  };

  @visibleForTesting
  static Map<String, dynamic> publicPostSearchRequest({
    required String query,
    required String offset,
    required int starCount,
  }) => {
    '@type': 'searchPublicPosts',
    'query': query,
    'offset': offset,
    'limit': 50,
    'star_count': starCount,
  };

  @visibleForTesting
  static Map<String, dynamic> publicTagSearchRequest({
    required String tag,
    required String offset,
  }) => {
    '@type': 'searchPublicMessagesByTag',
    'tag': tag,
    'offset': offset,
    'limit': 50,
  };

  @visibleForTesting
  static Map<String, dynamic> globalMediaSearchRequest({
    required String query,
    required String filterType,
    required String offset,
  }) => {
    '@type': 'searchMessages',
    'chat_list': null,
    'query': query,
    'offset': offset,
    'limit': 60,
    'filter': {'@type': filterType},
    'chat_type_filter': null,
    'min_date': 0,
    'max_date': 0,
  };

  @visibleForTesting
  static String? normalizedTag(String query) {
    final value = query.trim();
    if (value.length < 2 ||
        (!value.startsWith('#') && !value.startsWith(r'$'))) {
      return null;
    }
    return RegExp(r'^[#$][\p{L}\p{N}_]+$', unicode: true).hasMatch(value)
        ? value
        : null;
  }
}
