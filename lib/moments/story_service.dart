import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef StoryQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

enum StoryPrivacyKind { everyone, contacts, closeFriends, selectedUsers }

class StoryPrivacy {
  const StoryPrivacy._(
    this.kind, {
    this.userIds = const <int>[],
    this.exceptUserIds = const <int>[],
  });

  const StoryPrivacy.everyone({List<int> exceptUserIds = const <int>[]})
    : this._(StoryPrivacyKind.everyone, exceptUserIds: exceptUserIds);

  const StoryPrivacy.contacts({List<int> exceptUserIds = const <int>[]})
    : this._(StoryPrivacyKind.contacts, exceptUserIds: exceptUserIds);

  const StoryPrivacy.closeFriends() : this._(StoryPrivacyKind.closeFriends);

  const StoryPrivacy.selectedUsers(List<int> userIds)
    : this._(StoryPrivacyKind.selectedUsers, userIds: userIds);

  final StoryPrivacyKind kind;
  final List<int> userIds;
  final List<int> exceptUserIds;

  Map<String, dynamic> toTdJson() => switch (kind) {
    StoryPrivacyKind.everyone => {
      '@type': 'storyPrivacySettingsEveryone',
      'except_user_ids': exceptUserIds,
    },
    StoryPrivacyKind.contacts => {
      '@type': 'storyPrivacySettingsContacts',
      'except_user_ids': exceptUserIds,
    },
    StoryPrivacyKind.closeFriends => {
      '@type': 'storyPrivacySettingsCloseFriends',
    },
    StoryPrivacyKind.selectedUsers => {
      '@type': 'storyPrivacySettingsSelectedUsers',
      'user_ids': userIds,
    },
  };
}

class StoryAreaPositionDraft {
  const StoryAreaPositionDraft({
    this.xPercentage = 50,
    this.yPercentage = 50,
    this.widthPercentage = 35,
    this.heightPercentage = 14,
    this.rotationAngle = 0,
    this.cornerRadiusPercentage = 15,
  });

  final double xPercentage;
  final double yPercentage;
  final double widthPercentage;
  final double heightPercentage;
  final double rotationAngle;
  final double cornerRadiusPercentage;

  StoryAreaPositionDraft copyWith({
    double? xPercentage,
    double? yPercentage,
    double? widthPercentage,
    double? heightPercentage,
    double? rotationAngle,
    double? cornerRadiusPercentage,
  }) => StoryAreaPositionDraft(
    xPercentage: xPercentage ?? this.xPercentage,
    yPercentage: yPercentage ?? this.yPercentage,
    widthPercentage: widthPercentage ?? this.widthPercentage,
    heightPercentage: heightPercentage ?? this.heightPercentage,
    rotationAngle: rotationAngle ?? this.rotationAngle,
    cornerRadiusPercentage:
        cornerRadiusPercentage ?? this.cornerRadiusPercentage,
  );

  Map<String, dynamic> toTdJson() => {
    '@type': 'storyAreaPosition',
    'x_percentage': xPercentage,
    'y_percentage': yPercentage,
    'width_percentage': widthPercentage,
    'height_percentage': heightPercentage,
    'rotation_angle': rotationAngle,
    'corner_radius_percentage': cornerRadiusPercentage,
  };
}

class StoryAreaDraft {
  const StoryAreaDraft({
    required this.type,
    this.position = const StoryAreaPositionDraft(),
  });

  factory StoryAreaDraft.link(
    String url, {
    StoryAreaPositionDraft position = const StoryAreaPositionDraft(),
  }) => StoryAreaDraft(
    type: {'@type': 'inputStoryAreaTypeLink', 'url': url.trim()},
    position: position,
  );

  factory StoryAreaDraft.reaction(
    String emoji, {
    bool isDark = false,
    bool isFlipped = false,
    StoryAreaPositionDraft position = const StoryAreaPositionDraft(),
  }) => StoryAreaDraft(
    type: {
      '@type': 'inputStoryAreaTypeSuggestedReaction',
      'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
      'is_dark': isDark,
      'is_flipped': isFlipped,
    },
    position: position,
  );

  factory StoryAreaDraft.message({
    required int chatId,
    required int messageId,
    StoryAreaPositionDraft position = const StoryAreaPositionDraft(),
  }) => StoryAreaDraft(
    type: {
      '@type': 'inputStoryAreaTypeMessage',
      'chat_id': chatId,
      'message_id': messageId,
    },
    position: position,
  );

  factory StoryAreaDraft.location({
    required double latitude,
    required double longitude,
    double horizontalAccuracy = 0,
    String address = '',
    StoryAreaPositionDraft position = const StoryAreaPositionDraft(),
  }) => StoryAreaDraft(
    type: {
      '@type': 'inputStoryAreaTypeLocation',
      'location': {
        '@type': 'location',
        'latitude': latitude,
        'longitude': longitude,
        'horizontal_accuracy': horizontalAccuracy,
      },
      if (address.trim().isNotEmpty)
        'address': {
          '@type': 'locationAddress',
          'country_code': '',
          'state': '',
          'city': '',
          'street': address.trim(),
        },
    },
    position: position,
  );

  factory StoryAreaDraft.weather({
    required double temperature,
    required String emoji,
    int backgroundColor = 0xCC1D2733,
    StoryAreaPositionDraft position = const StoryAreaPositionDraft(),
  }) => StoryAreaDraft(
    type: {
      '@type': 'inputStoryAreaTypeWeather',
      'temperature': temperature,
      'emoji': emoji,
      'background_color': backgroundColor,
    },
    position: position,
  );

  factory StoryAreaDraft.upgradedGift(
    String giftName, {
    StoryAreaPositionDraft position = const StoryAreaPositionDraft(),
  }) => StoryAreaDraft(
    type: {
      '@type': 'inputStoryAreaTypeUpgradedGift',
      'gift_name': giftName.trim(),
    },
    position: position,
  );

  final Map<String, dynamic> type;
  final StoryAreaPositionDraft position;

  StoryAreaDraft copyWith({StoryAreaPositionDraft? position}) =>
      StoryAreaDraft(type: type, position: position ?? this.position);

  Map<String, dynamic> toTdJson() => {
    '@type': 'inputStoryArea',
    'position': position.toTdJson(),
    'type': type,
  };
}

enum StoryMediaKind { photo, video }

class StoryMediaDraft {
  const StoryMediaDraft.photo({
    required this.path,
    this.addedStickerFileIds = const <int>[],
  }) : kind = StoryMediaKind.photo,
       duration = 0,
       coverFrameTimestamp = 0,
       isAnimation = false;

  const StoryMediaDraft.video({
    required this.path,
    required this.duration,
    this.coverFrameTimestamp = 0,
    this.isAnimation = false,
    this.addedStickerFileIds = const <int>[],
  }) : kind = StoryMediaKind.video;

  final String path;
  final StoryMediaKind kind;
  final double duration;
  final double coverFrameTimestamp;
  final bool isAnimation;
  final List<int> addedStickerFileIds;

  Map<String, dynamic> toTdJson() => switch (kind) {
    StoryMediaKind.photo => {
      '@type': 'inputStoryContentPhoto',
      'photo': {'@type': 'inputFileLocal', 'path': path},
      'added_sticker_file_ids': addedStickerFileIds,
    },
    StoryMediaKind.video => {
      '@type': 'inputStoryContentVideo',
      'video': {'@type': 'inputFileLocal', 'path': path},
      'added_sticker_file_ids': addedStickerFileIds,
      'duration': duration,
      'cover_frame_timestamp': coverFrameTimestamp,
      'is_animation': isAnimation,
    },
  };
}

class StoryPostDraft {
  const StoryPostDraft({
    required this.chatId,
    required this.media,
    this.caption = const {'@type': 'formattedText', 'text': ''},
    this.privacy = const StoryPrivacy.everyone(),
    this.areas = const <StoryAreaDraft>[],
    this.albumIds = const <int>[],
    this.activePeriod = 86400,
    this.fromStoryPosterChatId,
    this.fromStoryId,
    this.postToChatPage = true,
    this.protectContent = false,
  });

  final int chatId;
  final StoryMediaDraft media;
  final Map<String, dynamic> caption;
  final StoryPrivacy privacy;
  final List<StoryAreaDraft> areas;
  final List<int> albumIds;
  final int activePeriod;
  final int? fromStoryPosterChatId;
  final int? fromStoryId;
  final bool postToChatPage;
  final bool protectContent;
}

class StoryCollectionResult {
  const StoryCollectionResult({
    required this.stories,
    required this.pinnedStoryIds,
  });

  final List<Map<String, dynamic>> stories;
  final List<int> pinnedStoryIds;
}

class StoryService {
  StoryService({StoryQuery? query}) : _query = query ?? TdClient.shared.query;

  final StoryQuery _query;

  static Map<String, dynamic> buildPostRequest(StoryPostDraft draft) {
    if (draft.chatId == 0) throw ArgumentError.value(draft.chatId, 'chatId');
    if (draft.media.path.trim().isEmpty) {
      throw ArgumentError.value(draft.media.path, 'media.path');
    }
    if (draft.media.kind == StoryMediaKind.video &&
        (draft.media.duration <= 0 || draft.media.duration > 60)) {
      throw ArgumentError.value(draft.media.duration, 'media.duration');
    }
    if (!const {21600, 43200, 86400, 172800}.contains(draft.activePeriod)) {
      throw ArgumentError.value(draft.activePeriod, 'activePeriod');
    }
    final fromPoster = draft.fromStoryPosterChatId;
    final fromId = draft.fromStoryId;
    return {
      '@type': 'postStory',
      'chat_id': draft.chatId,
      'content': draft.media.toTdJson(),
      'areas': {
        '@type': 'inputStoryAreas',
        'areas': draft.areas.map((area) => area.toTdJson()).toList(),
      },
      'caption': draft.caption,
      'privacy_settings': draft.privacy.toTdJson(),
      'album_ids': draft.albumIds,
      'active_period': draft.activePeriod,
      if (fromPoster != null && fromId != null)
        'from_story_full_id': {
          '@type': 'storyFullId',
          'poster_chat_id': fromPoster,
          'story_id': fromId,
        },
      'is_posted_to_chat_page': draft.postToChatPage,
      'protect_content': draft.protectContent,
    };
  }

  static Map<String, dynamic> buildEditRequest({
    required int chatId,
    required int storyId,
    StoryMediaDraft? media,
    List<StoryAreaDraft>? areas,
    Map<String, dynamic>? caption,
  }) => {
    '@type': 'editStory',
    'story_poster_chat_id': chatId,
    'story_id': storyId,
    'content': ?media?.toTdJson(),
    'areas': ?(areas == null
        ? null
        : {
            '@type': 'inputStoryAreas',
            'areas': areas.map((area) => area.toTdJson()).toList(),
          }),
    'caption': ?caption,
  };

  static Map<String, dynamic> buildStartLiveRequest({
    required int chatId,
    StoryPrivacy privacy = const StoryPrivacy.everyone(),
    bool protectContent = false,
    bool isRtmpStream = false,
    bool enableMessages = true,
    int paidMessageStarCount = 0,
  }) => {
    '@type': 'startLiveStory',
    'chat_id': chatId,
    'privacy_settings': privacy.toTdJson(),
    'protect_content': protectContent,
    'is_rtmp_stream': isRtmpStream,
    'enable_messages': enableMessages,
    'paid_message_star_count': paidMessageStarCount,
  };

  Future<Map<String, dynamic>> post(StoryPostDraft draft) =>
      _query(buildPostRequest(draft));

  Future<Map<String, dynamic>> edit({
    required int chatId,
    required int storyId,
    StoryMediaDraft? media,
    List<StoryAreaDraft>? areas,
    Map<String, dynamic>? caption,
  }) => _query(
    buildEditRequest(
      chatId: chatId,
      storyId: storyId,
      media: media,
      areas: areas,
      caption: caption,
    ),
  );

  Future<Map<String, dynamic>> canPost(int chatId) =>
      _query({'@type': 'canPostStory', 'chat_id': chatId});

  Future<List<int>> postableChatIds({int? savedMessagesId}) async {
    final candidates = <int>{};
    if (savedMessagesId != null) {
      candidates.add(savedMessagesId);
    } else {
      try {
        candidates.add(await savedMessagesChatId());
      } catch (_) {}
    }
    try {
      candidates.addAll(await chatsToPost());
    } catch (_) {}

    final orderedCandidates = candidates.toList(growable: false);
    final allowed = await Future.wait(
      orderedCandidates.map((chatId) async {
        try {
          final result = await canPost(chatId);
          return result.type == 'canPostStoryResultOk';
        } catch (_) {}
        return false;
      }),
    );
    return List.unmodifiable([
      for (var i = 0; i < orderedCandidates.length; i++)
        if (allowed[i]) orderedCandidates[i],
    ]);
  }

  Future<bool> canPostAnyStory() async => (await postableChatIds()).isNotEmpty;

  Future<StoryCollectionResult> loadStoryCollection(
    int chatId, {
    required bool archived,
    int pageLimit = 100,
    int maximumPages = 100,
  }) async {
    if (pageLimit <= 0) throw ArgumentError.value(pageLimit, 'pageLimit');
    if (maximumPages <= 0) {
      throw ArgumentError.value(maximumPages, 'maximumPages');
    }
    final stories = <Map<String, dynamic>>[];
    final seen = <int>{};
    final pinned = <int>[];
    var fromStoryId = 0;
    for (var page = 0; page < maximumPages; page++) {
      final response = await _query({
        '@type': archived
            ? 'getChatArchivedStories'
            : 'getChatPostedToChatPageStories',
        'chat_id': chatId,
        'from_story_id': fromStoryId,
        'limit': pageLimit,
      });
      if (page == 0 && !archived) {
        pinned.addAll(response.int64Array('pinned_story_ids') ?? const <int>[]);
      }
      final pageStories = response.objects('stories') ?? const [];
      if (pageStories.isEmpty) break;
      var added = 0;
      var lastId = fromStoryId;
      for (final story in pageStories) {
        final id = story.integer('id');
        if (id == null || id <= 0) continue;
        lastId = id;
        if (seen.add(id)) {
          stories.add(story);
          added++;
        }
      }
      if (added == 0 || lastId == fromStoryId || lastId <= 0) break;
      fromStoryId = lastId;
    }
    return StoryCollectionResult(
      stories: List.unmodifiable(stories),
      pinnedStoryIds: List.unmodifiable(pinned),
    );
  }

  Future<bool> isPremium() async {
    final me = await _query({'@type': 'getMe'});
    return me.boolean('is_premium') ?? false;
  }

  Future<List<int>> chatsToPost() async {
    final response = await _query({'@type': 'getChatsToPostStories'});
    return response.int64Array('chat_ids') ?? const <int>[];
  }

  Future<int> savedMessagesChatId() async {
    final me = await _query({'@type': 'getMe'});
    final id = me.int64('id');
    if (id == null) throw StateError('TDLib getMe returned no identifier');
    final chat = await _query({
      '@type': 'createPrivateChat',
      'user_id': id,
      'force': false,
    });
    final chatId = chat.int64('id');
    if (chatId == null) throw StateError('TDLib returned no Saved Messages');
    return chatId;
  }

  Future<Map<String, dynamic>> captionEntities(String text) async {
    if (text.trim().isEmpty) {
      return {'@type': 'formattedText', 'text': ''};
    }
    final response = await _query({'@type': 'getTextEntities', 'text': text});
    return {
      '@type': 'formattedText',
      'text': text,
      'entities':
          response.objects('entities') ?? const <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, dynamic>> startLive({
    required int chatId,
    StoryPrivacy privacy = const StoryPrivacy.everyone(),
    bool protectContent = false,
    bool isRtmpStream = false,
    bool enableMessages = true,
    int paidMessageStarCount = 0,
  }) => _query(
    buildStartLiveRequest(
      chatId: chatId,
      privacy: privacy,
      protectContent: protectContent,
      isRtmpStream: isRtmpStream,
      enableMessages: enableMessages,
      paidMessageStarCount: paidMessageStarCount,
    ),
  );

  Future<Map<String, dynamic>> rtmpUrl(int chatId, {bool replace = false}) =>
      _query({
        '@type': replace ? 'replaceLiveStoryRtmpUrl' : 'getLiveStoryRtmpUrl',
        'chat_id': chatId,
      });

  Future<Map<String, dynamic>> close(int chatId, int storyId) => _query({
    '@type': 'closeStory',
    'story_poster_chat_id': chatId,
    'story_id': storyId,
  });

  Future<Map<String, dynamic>> delete(int chatId, int storyId) => _query({
    '@type': 'deleteStory',
    'story_poster_chat_id': chatId,
    'story_id': storyId,
  });

  Future<Map<String, dynamic>> setPrivacy(int storyId, StoryPrivacy privacy) =>
      _query({
        '@type': 'setStoryPrivacySettings',
        'story_id': storyId,
        'privacy_settings': privacy.toTdJson(),
      });

  Future<Map<String, dynamic>> setPostedToPage(
    int chatId,
    int storyId,
    bool value,
  ) => _query({
    '@type': 'toggleStoryIsPostedToChatPage',
    'story_poster_chat_id': chatId,
    'story_id': storyId,
    'is_posted_to_chat_page': value,
  });

  Future<Map<String, dynamic>> setPinned(int chatId, List<int> storyIds) =>
      _query({
        '@type': 'setChatPinnedStories',
        'chat_id': chatId,
        'story_ids': storyIds,
      });

  Future<Map<String, dynamic>> albums(int chatId) =>
      _query({'@type': 'getChatStoryAlbums', 'chat_id': chatId});

  Future<Map<String, dynamic>> albumStories(
    int chatId,
    int albumId, {
    int offset = 0,
    int limit = 100,
  }) => _query({
    '@type': 'getStoryAlbumStories',
    'chat_id': chatId,
    'story_album_id': albumId,
    'offset': offset,
    'limit': limit,
  });

  Future<Map<String, dynamic>> createAlbum(
    int chatId,
    String name,
    List<int> storyIds,
  ) => _query({
    '@type': 'createStoryAlbum',
    'story_poster_chat_id': chatId,
    'name': name.trim(),
    'story_ids': storyIds,
  });

  Future<Map<String, dynamic>> renameAlbum(
    int chatId,
    int albumId,
    String name,
  ) => _query({
    '@type': 'setStoryAlbumName',
    'chat_id': chatId,
    'story_album_id': albumId,
    'name': name.trim(),
  });

  Future<Map<String, dynamic>> reorderAlbums(int chatId, List<int> albumIds) =>
      _query({
        '@type': 'reorderStoryAlbums',
        'chat_id': chatId,
        'story_album_ids': albumIds,
      });

  Future<Map<String, dynamic>> deleteAlbum(int chatId, int albumId) => _query({
    '@type': 'deleteStoryAlbum',
    'chat_id': chatId,
    'story_album_id': albumId,
  });

  Future<Map<String, dynamic>> addAlbumStories(
    int chatId,
    int albumId,
    List<int> storyIds,
  ) => _albumStoryMutation('addStoryAlbumStories', chatId, albumId, storyIds);

  Future<Map<String, dynamic>> removeAlbumStories(
    int chatId,
    int albumId,
    List<int> storyIds,
  ) =>
      _albumStoryMutation('removeStoryAlbumStories', chatId, albumId, storyIds);

  Future<Map<String, dynamic>> reorderAlbumStories(
    int chatId,
    int albumId,
    List<int> storyIds,
  ) => _albumStoryMutation(
    'reorderStoryAlbumStories',
    chatId,
    albumId,
    storyIds,
  );

  Future<Map<String, dynamic>> _albumStoryMutation(
    String type,
    int chatId,
    int albumId,
    List<int> storyIds,
  ) => _query({
    '@type': type,
    'chat_id': chatId,
    'story_album_id': albumId,
    'story_ids': storyIds,
  });

  Future<Map<String, dynamic>> react(
    int chatId,
    int storyId,
    Map<String, dynamic>? reaction,
  ) => _query({
    '@type': 'setStoryReaction',
    'story_poster_chat_id': chatId,
    'story_id': storyId,
    'reaction_type': ?reaction,
    'update_recent_reactions': true,
  });

  Future<Map<String, dynamic>> deleteLiveMessages(
    int groupCallId,
    List<int> messageIds, {
    bool reportSpam = false,
  }) => _query({
    '@type': 'deleteGroupCallMessages',
    'group_call_id': groupCallId,
    'message_ids': messageIds,
    'report_spam': reportSpam,
  });

  Future<Map<String, dynamic>> deleteLiveMessagesBySender(
    int groupCallId,
    Map<String, dynamic> sender, {
    bool reportSpam = false,
  }) => _query({
    '@type': 'deleteGroupCallMessagesBySender',
    'group_call_id': groupCallId,
    'sender_id': sender,
    'report_spam': reportSpam,
  });
}
