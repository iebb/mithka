import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef GroupAdministrationQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class GroupAdministrationService {
  GroupAdministrationService({GroupAdministrationQuery? query})
    : _query = query ?? TdClient.shared.query;

  final GroupAdministrationQuery _query;

  Future<Map<String, dynamic>> getChat(int chatId) =>
      _query({'@type': 'getChat', 'chat_id': chatId});

  Future<Map<String, dynamic>> getUser(int userId) =>
      _query({'@type': 'getUser', 'user_id': userId});

  Future<Map<String, dynamic>> getSupergroup(int supergroupId) =>
      _query({'@type': 'getSupergroup', 'supergroup_id': supergroupId});

  Future<Map<String, dynamic>> getSupergroupFullInfo(int supergroupId) =>
      _query({'@type': 'getSupergroupFullInfo', 'supergroup_id': supergroupId});

  Future<int> myId() async {
    final me = await _query({'@type': 'getMe'});
    return me.int64('id') ?? 0;
  }

  Future<List<Map<String, dynamic>>> inviteLinkCreatorCounts(int chatId) async {
    final response = await _query({
      '@type': 'getChatInviteLinkCounts',
      'chat_id': chatId,
    });
    return response.objects('invite_link_counts') ?? const [];
  }

  Future<List<Map<String, dynamic>>> inviteLinks({
    required int chatId,
    required int creatorUserId,
    bool revoked = false,
  }) async {
    final result = <Map<String, dynamic>>[];
    var offsetDate = 0;
    var offsetInviteLink = '';
    while (true) {
      final response = await _query({
        '@type': 'getChatInviteLinks',
        'chat_id': chatId,
        'creator_user_id': creatorUserId,
        'is_revoked': revoked,
        'offset_date': offsetDate,
        'offset_invite_link': offsetInviteLink,
        'limit': 100,
      });
      final page = response.objects('invite_links') ?? const [];
      result.addAll(page);
      if (page.length < 100) break;
      final last = page.last;
      final nextDate = last.integer('date') ?? 0;
      final nextLink = last.str('invite_link') ?? '';
      if (nextDate == offsetDate && nextLink == offsetInviteLink) break;
      offsetDate = nextDate;
      offsetInviteLink = nextLink;
    }
    return result;
  }

  Future<Map<String, dynamic>> createInviteLink({
    required int chatId,
    required String name,
    required int expirationDate,
    required int memberLimit,
    required bool createsJoinRequest,
  }) => _query({
    '@type': 'createChatInviteLink',
    'chat_id': chatId,
    'name': name.trim(),
    'expiration_date': expirationDate,
    'member_limit': createsJoinRequest ? 0 : memberLimit,
    'creates_join_request': createsJoinRequest,
  });

  Future<Map<String, dynamic>> editInviteLink({
    required int chatId,
    required String inviteLink,
    required String name,
    required int expirationDate,
    required int memberLimit,
    required bool createsJoinRequest,
  }) => _query({
    '@type': 'editChatInviteLink',
    'chat_id': chatId,
    'invite_link': inviteLink,
    'name': name.trim(),
    'expiration_date': expirationDate,
    'member_limit': createsJoinRequest ? 0 : memberLimit,
    'creates_join_request': createsJoinRequest,
  });

  Future<void> revokeInviteLink(int chatId, String inviteLink) => _query({
    '@type': 'revokeChatInviteLink',
    'chat_id': chatId,
    'invite_link': inviteLink,
  });

  Future<List<Map<String, dynamic>>> inviteLinkMembers(
    int chatId,
    String inviteLink,
  ) async {
    final result = <Map<String, dynamic>>[];
    Map<String, dynamic>? offset;
    while (true) {
      final response = await _query({
        '@type': 'getChatInviteLinkMembers',
        'chat_id': chatId,
        'invite_link': inviteLink,
        'only_with_expired_subscription': false,
        'offset_member': offset,
        'limit': 100,
      });
      final page = response.objects('members') ?? const [];
      result.addAll(page);
      if (page.length < 100) break;
      final next = page.last;
      if (next.int64('user_id') == offset?.int64('user_id') &&
          next.integer('joined_chat_date') ==
              offset?.integer('joined_chat_date')) {
        break;
      }
      offset = next;
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> joinRequests(int chatId) async {
    final result = <Map<String, dynamic>>[];
    Map<String, dynamic>? offset;
    while (true) {
      final response = await _query({
        '@type': 'getChatJoinRequests',
        'chat_id': chatId,
        'invite_link': '',
        'query': '',
        'offset_request': offset,
        'limit': 100,
      });
      final page = response.objects('requests') ?? const [];
      result.addAll(page);
      if (page.length < 100) break;
      final next = page.last;
      if (next.int64('user_id') == offset?.int64('user_id') &&
          next.integer('date') == offset?.integer('date')) {
        break;
      }
      offset = next;
    }
    return result;
  }

  Future<void> processJoinRequest(
    int chatId,
    int userId, {
    required bool approve,
  }) => _query({
    '@type': 'processChatJoinRequest',
    'chat_id': chatId,
    'user_id': userId,
    'approve': approve,
  });

  Future<void> processAllJoinRequests(int chatId, {required bool approve}) =>
      _query({
        '@type': 'processChatJoinRequests',
        'chat_id': chatId,
        'invite_link': '',
        'approve': approve,
      });

  Future<void> setJoinByRequest(
    int supergroupId,
    bool enabled, {
    int guardBotUserId = 0,
    bool applyToInviteLinks = true,
  }) => _query({
    '@type': 'toggleSupergroupJoinByRequest',
    'supergroup_id': supergroupId,
    'join_by_request': enabled,
    'guard_bot_user_id': guardBotUserId,
    'apply_to_invite_links': applyToInviteLinks,
  });

  Future<void> setSlowMode(int chatId, int delay) => _query({
    '@type': 'setChatSlowModeDelay',
    'chat_id': chatId,
    'slow_mode_delay': delay,
  });

  Future<void> setProtectedContent(int chatId, bool enabled) => _query({
    '@type': 'toggleChatHasProtectedContent',
    'chat_id': chatId,
    'has_protected_content': enabled,
  });

  Future<void> setAvailableReactions(
    int chatId,
    Map<String, dynamic> availableReactions,
  ) => _query({
    '@type': 'setChatAvailableReactions',
    'chat_id': chatId,
    'available_reactions': availableReactions,
  });

  Future<List<int>> suitableDiscussionChats() async {
    final response = await _query({'@type': 'getSuitableDiscussionChats'});
    return response.int64Array('chat_ids') ?? const [];
  }

  Future<void> setDiscussionGroup(int chatId, int discussionChatId) => _query({
    '@type': 'setChatDiscussionGroup',
    'chat_id': chatId,
    'discussion_chat_id': discussionChatId,
  });

  Future<void> setHiddenMembers(int supergroupId, bool enabled) => _query({
    '@type': 'toggleSupergroupHasHiddenMembers',
    'supergroup_id': supergroupId,
    'has_hidden_members': enabled,
  });

  Future<void> setAggressiveAntiSpam(int supergroupId, bool enabled) => _query({
    '@type': 'toggleSupergroupHasAggressiveAntiSpamEnabled',
    'supergroup_id': supergroupId,
    'has_aggressive_anti_spam_enabled': enabled,
  });

  Future<void> setAutomaticTranslation(int supergroupId, bool enabled) =>
      _query({
        '@type': 'toggleSupergroupHasAutomaticTranslation',
        'supergroup_id': supergroupId,
        'has_automatic_translation': enabled,
      });

  Future<void> setDescription(int chatId, String description) => _query({
    '@type': 'setChatDescription',
    'chat_id': chatId,
    'description': description.trim(),
  });

  Future<void> setPhoto(int chatId, String path) => _query({
    '@type': 'setChatPhoto',
    'chat_id': chatId,
    'photo': {
      '@type': 'inputChatPhotoStatic',
      'photo': {'@type': 'inputFileLocal', 'path': path},
    },
  });

  Future<void> removePhoto(int chatId) =>
      _query({'@type': 'setChatPhoto', 'chat_id': chatId, 'photo': null});

  Future<void> setSignedMessages({
    required int supergroupId,
    required bool signMessages,
    required bool showMessageSender,
  }) => _query({
    '@type': 'toggleSupergroupSignMessages',
    'supergroup_id': supergroupId,
    'sign_messages': signMessages,
    'show_message_sender': showMessageSender,
  });

  Future<void> setAllHistoryAvailable(int supergroupId, bool enabled) =>
      _query({
        '@type': 'toggleSupergroupIsAllHistoryAvailable',
        'supergroup_id': supergroupId,
        'is_all_history_available': enabled,
      });

  Future<void> setForumMode({
    required int supergroupId,
    required bool isForum,
    required bool hasForumTabs,
  }) => _query({
    '@type': 'toggleSupergroupIsForum',
    'supergroup_id': supergroupId,
    'is_forum': isForum,
    'has_forum_tabs': isForum && hasForumTabs,
  });

  Future<List<Map<String, dynamic>>> forumTopics(int chatId) async {
    final result = <Map<String, dynamic>>[];
    var offsetDate = 0;
    var offsetMessageId = 0;
    var offsetForumTopicId = 0;
    while (true) {
      final response = await _query({
        '@type': 'getForumTopics',
        'chat_id': chatId,
        'query': '',
        'offset_date': offsetDate,
        'offset_message_id': offsetMessageId,
        'offset_forum_topic_id': offsetForumTopicId,
        'limit': 100,
      });
      final page = response.objects('topics') ?? const [];
      result.addAll(page);
      if (page.length < 100) break;
      final last = page.last;
      final nextDate = last.obj('last_message')?.integer('date') ?? 0;
      final nextMessageId = last.obj('last_message')?.int64('id') ?? 0;
      final nextTopicId = last.obj('info')?.integer('forum_topic_id') ?? 0;
      if (nextDate == offsetDate &&
          nextMessageId == offsetMessageId &&
          nextTopicId == offsetForumTopicId) {
        break;
      }
      offsetDate = nextDate;
      offsetMessageId = nextMessageId;
      offsetForumTopicId = nextTopicId;
    }
    return result;
  }

  Future<Map<String, dynamic>> createForumTopic({
    required int chatId,
    required String name,
    required int color,
    int customEmojiId = 0,
  }) => _query({
    '@type': 'createForumTopic',
    'chat_id': chatId,
    'name': name.trim(),
    'is_name_implicit': false,
    'icon': {
      '@type': 'forumTopicIcon',
      'color': color,
      'custom_emoji_id': customEmojiId,
    },
  });

  Future<void> editForumTopic({
    required int chatId,
    required int forumTopicId,
    required String name,
    int? customEmojiId,
  }) => _query({
    '@type': 'editForumTopic',
    'chat_id': chatId,
    'forum_topic_id': forumTopicId,
    'name': name.trim(),
    'edit_icon_custom_emoji': customEmojiId != null,
    'icon_custom_emoji_id': customEmojiId ?? 0,
  });

  Future<void> deleteForumTopic(int chatId, int forumTopicId) => _query({
    '@type': 'deleteForumTopic',
    'chat_id': chatId,
    'forum_topic_id': forumTopicId,
  });

  Future<void> toggleForumTopicPinned(
    int chatId,
    int forumTopicId,
    bool pinned,
  ) => _query({
    '@type': 'toggleForumTopicIsPinned',
    'chat_id': chatId,
    'forum_topic_id': forumTopicId,
    'is_pinned': pinned,
  });

  Future<void> reorderPinnedForumTopics(int chatId, List<int> topicIds) =>
      _query({
        '@type': 'setPinnedForumTopics',
        'chat_id': chatId,
        'forum_topic_ids': topicIds,
      });

  Future<Map<String, dynamic>> statistics(int chatId, {required bool dark}) =>
      _query({
        '@type': 'getChatStatistics',
        'chat_id': chatId,
        'is_dark': dark,
      });

  Future<Map<String, dynamic>> boostStatus(int chatId) =>
      _query({'@type': 'getChatBoostStatus', 'chat_id': chatId});

  Future<Map<String, dynamic>> boostLink(int chatId) =>
      _query({'@type': 'getChatBoostLink', 'chat_id': chatId});

  Future<Map<String, dynamic>> boosts(int chatId) async {
    final result = <Map<String, dynamic>>[];
    var offset = '';
    var totalCount = 0;
    while (true) {
      final response = await _query({
        '@type': 'getChatBoosts',
        'chat_id': chatId,
        'only_gift_codes': false,
        'offset': offset,
        'limit': 100,
      });
      result.addAll(response.objects('boosts') ?? const []);
      totalCount = response.integer('total_count') ?? result.length;
      final nextOffset = response.str('next_offset') ?? '';
      if (nextOffset.isEmpty || nextOffset == offset) break;
      offset = nextOffset;
    }
    return {
      '@type': 'foundChatBoosts',
      'total_count': totalCount,
      'boosts': result,
      'next_offset': '',
    };
  }

  Future<Map<String, dynamic>> premiumGiveawayOptions(int chatId) => _query({
    '@type': 'getPremiumGiveawayPaymentOptions',
    'boosted_chat_id': chatId,
  });

  Future<Map<String, dynamic>> starGiveawayOptions() =>
      _query({'@type': 'getStarGiveawayPaymentOptions'});

  Future<void> setMemberTag(int chatId, int userId, String tag) => _query({
    '@type': 'setChatMemberTag',
    'chat_id': chatId,
    'user_id': userId,
    'tag': tag.trim(),
  });
}
