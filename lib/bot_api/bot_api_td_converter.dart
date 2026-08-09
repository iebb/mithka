import 'dart:io';

import 'bot_api_store.dart';

class BotApiConvertedMessage {
  const BotApiConvertedMessage({
    required this.users,
    required this.chat,
    required this.message,
  });

  final List<Map<String, dynamic>> users;
  final Map<String, dynamic> chat;
  final Map<String, dynamic> message;
}

/// Converts Bot API payloads to the TDLib JSON shapes consumed by Mithka.
class BotApiTdConverter {
  BotApiTdConverter({required this.store, required this.bot});

  final BotApiStore store;
  final Map<String, dynamic> bot;

  int get botId => _int(bot['id']) ?? 0;

  int rememberExternalId(String kind, String value) {
    final id = _stableId(value);
    if (id != 0) store.setMetadata('external_id.$kind.$id', value);
    return id;
  }

  String? externalId(String kind, int id) =>
      store.metadata('external_id.$kind.$id');

  Map<String, dynamic> user(Map<String, dynamic> source) {
    final id = _int(source['id']) ?? 0;
    final username = _string(source['username']);
    final isBot = source['is_bot'] == true;
    final photo = profilePhoto(_map(source['photo']));
    return {
      '@type': 'user',
      'id': id,
      'first_name': _string(source['first_name']),
      'last_name': _string(source['last_name']),
      'usernames': {
        '@type': 'usernames',
        'active_usernames': [if (username.isNotEmpty) username],
        'disabled_usernames': const <String>[],
        'editable_username': '',
      },
      'phone_number': '',
      'status': {
        '@type': isBot ? 'userStatusOnline' : 'userStatusRecently',
        if (isBot) 'expires': 0,
      },
      'profile_photo': photo,
      'is_contact': false,
      'is_mutual_contact': false,
      'is_close_friend': false,
      'is_verified': source['is_verified'] == true,
      'is_premium': source['is_premium'] == true,
      'is_support': false,
      'restriction_reason': '',
      'is_scam': false,
      'is_fake': false,
      'have_access': true,
      'type': isBot
          ? {
              '@type': 'userTypeBot',
              'can_be_edited': id == botId,
              'can_join_groups': source['can_join_groups'] != false,
              'can_read_all_group_messages':
                  source['can_read_all_group_messages'] == true,
              'has_main_web_app': source['has_main_web_app'] == true,
              'is_inline':
                  _string(source['supports_inline_queries']).isNotEmpty ||
                  source['supports_inline_queries'] == true,
              'inline_query_placeholder': '',
              'need_location': false,
            }
          : const {'@type': 'userTypeRegular'},
      'language_code': _string(source['language_code']),
      'added_to_attachment_menu': source['added_to_attachment_menu'] == true,
    };
  }

  Map<String, dynamic>? profilePhoto(Map<String, dynamic>? source) {
    final info = _chatPhoto(source);
    if (info == null) return null;
    final uniqueId = _string(source?['small_file_unique_id']);
    final identity = uniqueId.isNotEmpty
        ? uniqueId
        : _string(source?['small_file_id']);
    return {
      ...info,
      '@type': 'profilePhoto',
      'id': rememberExternalId('profile_photo', identity),
    };
  }

  Map<String, dynamic> userProfilePhotos(Object? source) {
    final value = _map(source);
    final photos = <Map<String, dynamic>>[];
    for (final rawPhoto in _list(value?['photos'])) {
      final sourceSizes = _list(
        rawPhoto,
      ).map(_map).whereType<Map<String, dynamic>>().toList();
      if (sourceSizes.isEmpty) continue;
      final largest = sourceSizes.reduce(
        (a, b) =>
            ((_int(a['width']) ?? 0) * (_int(a['height']) ?? 0)) >=
                ((_int(b['width']) ?? 0) * (_int(b['height']) ?? 0))
            ? a
            : b,
      );
      final uniqueId = _string(largest['file_unique_id']);
      final identity = uniqueId.isNotEmpty
          ? uniqueId
          : _string(largest['file_id']);
      photos.add({
        '@type': 'chatPhoto',
        'id': rememberExternalId('profile_photo', identity),
        'added_date': 0,
        'minithumbnail': null,
        'sizes': [for (final size in sourceSizes) _photoSize(size)],
        'animation': null,
      });
    }
    return {
      '@type': 'chatPhotos',
      'total_count': _int(value?['total_count']) ?? photos.length,
      'photos': photos,
    };
  }

  BotApiConvertedMessage message(
    Map<String, dynamic> source, {
    Map<String, dynamic>? previousChat,
    bool incrementUnread = true,
  }) {
    final sourceChat = _map(source['chat']) ?? const <String, dynamic>{};
    final from = _map(source['from']);
    final senderChat = _map(source['sender_chat']);
    final users = <Map<String, dynamic>>[];
    if (from != null) users.add(user(from));
    for (final serviceUser in _serviceUsers(source)) {
      users.add(user(serviceUser));
    }
    if (sourceChat['type'] == 'private' && sourceChat['id'] != botId) {
      users.add(user({...sourceChat, 'is_bot': false}));
    }
    final tdMessage = _message(source);
    final outgoing = tdMessage['is_outgoing'] == true;
    final previousUnread = _int(previousChat?['unread_count']) ?? 0;
    final unread = incrementUnread && !outgoing
        ? previousUnread + 1
        : previousUnread;
    return BotApiConvertedMessage(
      users: _uniqueUsers(users),
      chat: chat(
        sourceChat,
        lastMessage: tdMessage,
        unreadCount: unread,
        senderChat: senderChat,
      ),
      message: tdMessage,
    );
  }

  Map<String, dynamic> chat(
    Map<String, dynamic> source, {
    Map<String, dynamic>? lastMessage,
    int unreadCount = 0,
    Map<String, dynamic>? senderChat,
  }) {
    final id = _int(source['id']) ?? _int(senderChat?['id']) ?? 0;
    final type = _string(source['type']).isNotEmpty
        ? _string(source['type'])
        : _string(senderChat?['type']);
    final title = _chatTitle(source, senderChat: senderChat);
    final date = _int(lastMessage?['date']) ?? 0;
    final messageId = _int(lastMessage?['id']) ?? 0;
    final order = date == 0 ? 0 : date * 1000000 + messageId.abs() % 1000000;
    final photo = _chatPhoto(
      _map(source['photo']) ?? _map(senderChat?['photo']),
    );
    return {
      '@type': 'chat',
      'id': id,
      'type': _chatType(id, type),
      'title': title,
      'photo': photo,
      'accent_color_id': id.abs() % 7,
      'background_custom_emoji_id': 0,
      'profile_accent_color_id': -1,
      'profile_background_custom_emoji_id': 0,
      'permissions': _chatPermissions(),
      'last_message': lastMessage,
      'positions': order == 0
          ? const <Map<String, dynamic>>[]
          : [
              {
                '@type': 'chatPosition',
                'list': const {'@type': 'chatListMain'},
                'order': order,
                'is_pinned': false,
                'source': null,
              },
            ],
      'chat_lists': const [
        {'@type': 'chatListMain'},
      ],
      'message_sender_id': type == 'private'
          ? {'@type': 'messageSenderUser', 'user_id': id}
          : {'@type': 'messageSenderChat', 'chat_id': id},
      'block_list': null,
      'has_protected_content': false,
      'is_translatable': true,
      'is_marked_as_unread': false,
      'view_as_topics': source['is_forum'] == true,
      'has_scheduled_messages': false,
      'can_be_deleted_only_for_self': false,
      'can_be_deleted_for_all_users': false,
      'can_be_reported': false,
      'default_disable_notification': false,
      'unread_count': unreadCount,
      'last_read_inbox_message_id': 0,
      'last_read_outbox_message_id': outgoingMessageId(lastMessage),
      'unread_mention_count': 0,
      'unread_reaction_count': 0,
      'notification_settings': _notificationSettings(),
      'available_reactions': const {'@type': 'chatAvailableReactionsAll'},
      'message_auto_delete_time': 0,
      'emoji_status_custom_emoji_id': 0,
      'background': null,
      'theme_name': '',
      'action_bar': null,
      'video_chat': const {
        '@type': 'videoChat',
        'group_call_id': 0,
        'has_participants': false,
        'default_participant_id': null,
      },
      'pending_join_requests': null,
      'reply_markup_message_id': 0,
      'draft_message': null,
      'client_data': '',
    };
  }

  int outgoingMessageId(Map<String, dynamic>? message) =>
      message?['is_outgoing'] == true ? _int(message?['id']) ?? 0 : 0;

  Map<String, dynamic> content(Map<String, dynamic> message) {
    final service = _serviceContent(message);
    if (service != null) return service;
    if (message['text'] is String) {
      return {
        '@type': 'messageText',
        'text': formattedText(message['text'], message['entities']),
        'link_preview': null,
        'link_preview_options': const {
          '@type': 'linkPreviewOptions',
          'is_disabled': false,
          'url': '',
          'force_small_media': false,
          'force_large_media': false,
          'show_above_text': false,
        },
      };
    }
    if (message['photo'] is List) {
      final sizes = <Map<String, dynamic>>[
        for (final value in message['photo'] as List)
          if (_map(value) case final photo?) _photoSize(photo),
      ];
      return {
        '@type': 'messagePhoto',
        'photo': {
          '@type': 'photo',
          'has_stickers': false,
          'minithumbnail': null,
          'sizes': sizes,
        },
        'caption': formattedText(
          message['caption'],
          message['caption_entities'],
        ),
        'show_caption_above_media': message['show_caption_above_media'] == true,
        'has_spoiler': message['has_media_spoiler'] == true,
        'is_secret': false,
      };
    }
    final video = _map(message['video']);
    if (video != null) {
      return {
        '@type': 'messageVideo',
        'video': _video(video),
        'alternative_videos': const <Map<String, dynamic>>[],
        'storyboards': const <Map<String, dynamic>>[],
        'cover': null,
        'start_timestamp': 0,
        'caption': formattedText(
          message['caption'],
          message['caption_entities'],
        ),
        'show_caption_above_media': message['show_caption_above_media'] == true,
        'has_spoiler': message['has_media_spoiler'] == true,
        'is_secret': false,
      };
    }
    final animation = _map(message['animation']);
    if (animation != null) {
      return {
        '@type': 'messageAnimation',
        'animation': _animation(animation),
        'caption': formattedText(
          message['caption'],
          message['caption_entities'],
        ),
        'show_caption_above_media': message['show_caption_above_media'] == true,
        'has_spoiler': message['has_media_spoiler'] == true,
        'is_secret': false,
      };
    }
    final audio = _map(message['audio']);
    if (audio != null) {
      return {
        '@type': 'messageAudio',
        'audio': _audio(audio),
        'caption': formattedText(
          message['caption'],
          message['caption_entities'],
        ),
      };
    }
    final document = _map(message['document']);
    if (document != null) {
      return {
        '@type': 'messageDocument',
        'document': _document(document),
        'caption': formattedText(
          message['caption'],
          message['caption_entities'],
        ),
      };
    }
    final voice = _map(message['voice']);
    if (voice != null) {
      return {
        '@type': 'messageVoiceNote',
        'voice_note': {
          '@type': 'voiceNote',
          'duration': _int(voice['duration']) ?? 0,
          'waveform': '',
          'mime_type': _string(voice['mime_type']),
          'speech_recognition_result': null,
          'voice': file(voice),
        },
        'caption': formattedText(
          message['caption'],
          message['caption_entities'],
        ),
        'is_listened':
            message['from'] is Map &&
            _int((message['from'] as Map)['id']) == botId,
      };
    }
    final videoNote = _map(message['video_note']);
    if (videoNote != null) {
      final length = _int(videoNote['length']) ?? 0;
      return {
        '@type': 'messageVideoNote',
        'video_note': {
          '@type': 'videoNote',
          'duration': _int(videoNote['duration']) ?? 0,
          'waveform': '',
          'length': length,
          'minithumbnail': null,
          'thumbnail': _thumbnail(_map(videoNote['thumbnail'])),
          'speech_recognition_result': null,
          'video': file(videoNote),
        },
        'is_viewed': false,
        'is_secret': false,
      };
    }
    final sticker = _map(message['sticker']);
    if (sticker != null) {
      return {
        '@type': 'messageSticker',
        'sticker': _sticker(sticker),
        'is_premium': false,
      };
    }
    final location = _map(message['location']);
    if (location != null) {
      return {
        '@type': 'messageLocation',
        'location': _location(location),
        'live_period': _int(message['live_period']) ?? 0,
        'expires_in': 0,
        'heading': _int(message['heading']) ?? 0,
        'proximity_alert_radius': _int(message['proximity_alert_radius']) ?? 0,
      };
    }
    final venue = _map(message['venue']);
    if (venue != null) {
      return {
        '@type': 'messageVenue',
        'venue': {
          '@type': 'venue',
          'location': _location(_map(venue['location']) ?? const {}),
          'title': _string(venue['title']),
          'address': _string(venue['address']),
          'provider': _string(venue['foursquare_type']).isNotEmpty
              ? 'foursquare'
              : _string(venue['google_place_type']).isNotEmpty
              ? 'google'
              : '',
          'id': _string(venue['foursquare_id']).isNotEmpty
              ? _string(venue['foursquare_id'])
              : _string(venue['google_place_id']),
          'type': _string(venue['foursquare_type']).isNotEmpty
              ? _string(venue['foursquare_type'])
              : _string(venue['google_place_type']),
        },
      };
    }
    final contact = _map(message['contact']);
    if (contact != null) {
      return {
        '@type': 'messageContact',
        'contact': {
          '@type': 'contact',
          'phone_number': _string(contact['phone_number']),
          'first_name': _string(contact['first_name']),
          'last_name': _string(contact['last_name']),
          'vcard': _string(contact['vcard']),
          'user_id': _int(contact['user_id']) ?? 0,
        },
      };
    }
    final poll = _map(message['poll']);
    if (poll != null) return {'@type': 'messagePoll', 'poll': pollObject(poll)};
    final dice = _map(message['dice']);
    if (dice != null) {
      return {
        '@type': 'messageDice',
        'initial_state': null,
        'final_state': null,
        'emoji': _string(dice['emoji']),
        'value': _int(dice['value']) ?? 0,
        'success_animation_frame_number': 0,
      };
    }
    final rich = _map(message['rich_message']);
    if (rich != null) {
      return {
        '@type': 'messageRichMessage',
        'message': {...rich, 'is_full': true},
      };
    }
    return {'@type': 'messageUnsupported'};
  }

  /// Converts Bot API service-message fields to the TDLib content names the
  /// rest of Mithka already localizes and renders as centered system events.
  ///
  /// Some compatible endpoints still emit the pre-1.0 singular participant
  /// aliases, so keep those alongside the current `new_chat_members` and
  /// `left_chat_member` fields instead of leaking raw `[field_name]` text.
  Map<String, dynamic>? _serviceContent(Map<String, dynamic> message) {
    final addedUsers = _addedChatUsers(message);
    if (addedUsers.isNotEmpty) {
      return {
        '@type': 'messageChatAddMembers',
        'member_user_ids': [
          for (final member in addedUsers) ?_int(member['id']),
        ],
      };
    }

    final removedUser =
        _map(message['left_chat_member']) ??
        _map(message['left_chat_participant']);
    if (removedUser != null) {
      return {
        '@type': 'messageChatDeleteMember',
        'user_id': _int(removedUser['id']) ?? 0,
      };
    }

    if (message['new_chat_title'] is String) {
      return {
        '@type': 'messageChatChangeTitle',
        'title': _string(message['new_chat_title']),
      };
    }
    if (message['new_chat_photo'] is List) {
      return const {'@type': 'messageChatChangePhoto', 'photo': null};
    }
    if (message['delete_chat_photo'] == true) {
      return const {'@type': 'messageChatDeletePhoto'};
    }
    if (message['group_chat_created'] == true) {
      return {
        '@type': 'messageBasicGroupChatCreate',
        'title': _string((_map(message['chat']))?['title']),
        'member_user_ids': const <int>[],
      };
    }
    if (message['supergroup_chat_created'] == true ||
        message['channel_chat_created'] == true) {
      return {
        '@type': 'messageSupergroupChatCreate',
        'title': _string((_map(message['chat']))?['title']),
      };
    }
    if (_int(message['migrate_to_chat_id']) case final chatId?) {
      return {
        '@type': 'messageChatUpgradeTo',
        'supergroup_id': _peerId(chatId),
      };
    }
    if (_int(message['migrate_from_chat_id']) case final chatId?) {
      return {
        '@type': 'messageChatUpgradeFrom',
        'basic_group_id': _peerId(chatId),
      };
    }

    final pinned = _map(message['pinned_message']);
    if (pinned != null) {
      return {
        '@type': 'messagePinMessage',
        'message_id': _int(pinned['message_id']) ?? 0,
      };
    }

    final autoDelete = _map(message['message_auto_delete_timer_changed']);
    if (autoDelete != null) {
      return {
        '@type': 'messageChatSetMessageAutoDeleteTime',
        'message_auto_delete_time':
            _int(autoDelete['message_auto_delete_time']) ?? 0,
        'from_user_id': 0,
      };
    }
    if (message.containsKey('video_chat_started')) {
      return const {'@type': 'messageVideoChatStarted', 'group_call_id': 0};
    }
    final videoChatEnded = _map(message['video_chat_ended']);
    if (videoChatEnded != null) {
      return {
        '@type': 'messageVideoChatEnded',
        'duration': _int(videoChatEnded['duration']) ?? 0,
      };
    }

    final topicCreated = _map(message['forum_topic_created']);
    if (topicCreated != null) {
      return {
        '@type': 'messageForumTopicCreated',
        'name': _string(topicCreated['name']),
        'icon': {
          '@type': 'forumTopicIcon',
          'color': _int(topicCreated['icon_color']) ?? 0,
          'custom_emoji_id': rememberExternalId(
            'custom_emoji',
            _string(topicCreated['icon_custom_emoji_id']),
          ),
        },
      };
    }
    final topicEdited = _map(message['forum_topic_edited']);
    if (topicEdited != null) {
      return {
        '@type': 'messageForumTopicEdited',
        'name': _string(topicEdited['name']),
        'edit_icon_custom_emoji_id': topicEdited.containsKey(
          'icon_custom_emoji_id',
        ),
        'icon_custom_emoji_id': rememberExternalId(
          'custom_emoji',
          _string(topicEdited['icon_custom_emoji_id']),
        ),
      };
    }
    if (message.containsKey('forum_topic_closed')) {
      return const {
        '@type': 'messageForumTopicIsClosedToggled',
        'is_closed': true,
      };
    }
    if (message.containsKey('forum_topic_reopened')) {
      return const {
        '@type': 'messageForumTopicIsClosedToggled',
        'is_closed': false,
      };
    }

    final boost = _map(message['boost_added']);
    if (boost != null) {
      return {
        '@type': 'messageChatBoost',
        'boost_count': _int(boost['boost_count']) ?? 1,
      };
    }
    if (message.containsKey('chat_background_set')) {
      return const {'@type': 'messageChatSetBackground', 'background': null};
    }
    final communityAdded = _map(message['community_chat_added']);
    if (communityAdded != null) {
      final community = _map(communityAdded['community']);
      return {
        '@type': 'messageChatAddedToCommunity',
        // Bot API 10.2 exposes only the stable id and display name here. Keep
        // both on the TD-shaped content so the transcript can render the rich
        // service card without reaching back into the transport payload.
        'community_id': _int(community?['id']) ?? 0,
        'community_name': _string(community?['name']),
      };
    }
    if (message.containsKey('community_chat_removed')) {
      return const {'@type': 'messageChatRemovedFromCommunity'};
    }

    final paidPrice = _map(message['paid_message_price_changed']);
    if (paidPrice != null) {
      return {
        '@type': 'messagePaidMessagePriceChanged',
        'paid_message_star_count':
            _int(paidPrice['paid_message_star_count']) ??
            _int(paidPrice['star_count']) ??
            0,
      };
    }
    final directPrice = _map(message['direct_message_price_changed']);
    if (directPrice != null) {
      return {
        '@type': 'messageDirectMessagePriceChanged',
        'star_count': _int(directPrice['star_count']) ?? 0,
      };
    }

    // The Bot API adds service fields regularly. Keep new ones in the service
    // lane with a localized "System message" fallback until an exact TDLib
    // mapping is added; never expose a transport field name to the user.
    if (_botApiServiceFields.any(message.containsKey)) {
      return const {'@type': 'messageCustomServiceAction', 'text': ''};
    }
    return null;
  }

  List<Map<String, dynamic>> _serviceUsers(Map<String, dynamic> message) => [
    ..._addedChatUsers(message),
    for (final key in const ['left_chat_member', 'left_chat_participant'])
      ?_map(message[key]),
    for (final raw in _list(
      (_map(message['video_chat_participants_invited']))?['users'],
    ))
      ?_map(raw),
  ];

  List<Map<String, dynamic>> _addedChatUsers(Map<String, dynamic> message) => [
    for (final raw in _list(message['new_chat_members'])) ?_map(raw),
    for (final key in const ['new_chat_participant', 'new_chat_member'])
      ?_map(message[key]),
  ];

  Map<String, dynamic> pollObject(Map<String, dynamic> source) {
    final botPollId = _string(source['id']);
    final type = _string(source['type']);
    return {
      '@type': 'poll',
      'id': _stableId(botPollId),
      'bot_api_id': botPollId,
      'question': formattedText(
        source['question'],
        source['question_entities'],
      ),
      'options': [
        for (var index = 0; index < _list(source['options']).length; index++)
          if (_map(_list(source['options'])[index]) case final option?)
            {
              '@type': 'pollOption',
              'id': '$index',
              'text': formattedText(option['text'], option['text_entities']),
              'voter_count': _int(option['voter_count']) ?? 0,
              'vote_percentage': 0,
              'is_chosen': false,
              'is_being_chosen': false,
            },
      ],
      'total_voter_count': _int(source['total_voter_count']) ?? 0,
      'recent_voter_ids': const <Map<String, dynamic>>[],
      'is_anonymous': source['is_anonymous'] == true,
      'type': type == 'quiz'
          ? {
              '@type': 'pollTypeQuiz',
              'correct_option_ids': [?_int(source['correct_option_id'])],
              'explanation': formattedText(
                source['explanation'],
                source['explanation_entities'],
              ),
            }
          : {
              '@type': 'pollTypeRegular',
              'allow_multiple_answers':
                  source['allows_multiple_answers'] == true,
            },
      'open_period': _int(source['open_period']) ?? 0,
      'close_date': _int(source['close_date']) ?? 0,
      'is_closed': source['is_closed'] == true,
      'can_vote': false,
      'can_get_voters': false,
      'can_see_results': true,
      'allows_revoting': false,
    };
  }

  Map<String, dynamic> formattedText(Object? text, Object? rawEntities) => {
    '@type': 'formattedText',
    'text': text is String ? text : '',
    'entities': [
      for (final value in _list(rawEntities))
        if (_map(value) case final entity?) _entity(entity),
    ],
  };

  Map<String, dynamic> file(Map<String, dynamic> source) {
    final botFileId = _string(source['file_id']);
    if (botFileId.isEmpty) return _emptyFile();
    final record = store.registerFile(
      botFileId: botFileId,
      uniqueId: _string(source['file_unique_id']),
      size: _int(source['file_size']) ?? 0,
    );
    return fileFromRecord(record);
  }

  Map<String, dynamic> fileFromRecord(BotApiFileRecord record) {
    final complete =
        record.localPath.isNotEmpty && File(record.localPath).existsSync();
    return {
      '@type': 'file',
      'id': record.id,
      'size': record.size,
      'expected_size': record.size,
      'local': {
        '@type': 'localFile',
        'path': complete ? record.localPath : '',
        'can_be_downloaded': record.botFileId.isNotEmpty,
        'can_be_deleted': complete,
        'is_downloading_active': false,
        'is_downloading_completed': complete,
        'download_offset': 0,
        'downloaded_prefix_size': complete ? record.size : 0,
        'downloaded_size': complete ? record.size : 0,
      },
      'remote': {
        '@type': 'remoteFile',
        'id': record.botFileId,
        'unique_id': record.uniqueId,
        'is_uploading_active': false,
        'is_uploading_completed': true,
        'uploaded_size': record.size,
      },
    };
  }

  Map<String, dynamic> supergroup(Map<String, dynamic> chat) {
    final id = _int(chat['id']) ?? 0;
    final type = _string(chat['type']);
    return {
      '@type': 'supergroup',
      'id': _peerId(id),
      'usernames': {
        '@type': 'usernames',
        'active_usernames': [
          if (_string(chat['username']).isNotEmpty) _string(chat['username']),
        ],
        'disabled_usernames': const <String>[],
        'editable_username': '',
      },
      'date': 0,
      'status': const {'@type': 'chatMemberStatusMember'},
      'member_count': 0,
      'boost_level': 0,
      'has_automatic_translation': false,
      'has_linked_chat': false,
      'has_location': false,
      'sign_messages': type == 'channel',
      'show_message_sender': true,
      'join_to_send_messages': false,
      'join_by_request': false,
      'is_slow_mode_enabled': false,
      'is_channel': type == 'channel',
      'is_broadcast_group': false,
      'is_forum': chat['is_forum'] == true,
      'is_direct_messages_group': false,
      'is_verified': false,
      'restriction_reason': '',
      'is_scam': false,
      'is_fake': false,
      'has_active_stories': false,
      'has_unread_active_stories': false,
    };
  }

  Map<String, dynamic> basicGroup(Map<String, dynamic> chat) => {
    '@type': 'basicGroup',
    'id': _peerId(_int(chat['id']) ?? 0),
    'member_count': 0,
    'status': const {'@type': 'chatMemberStatusMember'},
    'is_active': true,
    'upgraded_to_supergroup_id': 0,
  };

  Map<String, dynamic> _message(Map<String, dynamic> source) {
    final sourceChat = _map(source['chat']) ?? const <String, dynamic>{};
    final from = _map(source['from']);
    final senderChat = _map(source['sender_chat']);
    final fromId = _int(from?['id']);
    final isOutgoing = fromId == botId;
    return {
      '@type': 'message',
      'id': _int(source['message_id']) ?? 0,
      'sender_id': senderChat != null
          ? {
              '@type': 'messageSenderChat',
              'chat_id': _int(senderChat['id']) ?? 0,
            }
          : fromId != null
          ? {'@type': 'messageSenderUser', 'user_id': fromId}
          : {
              '@type': 'messageSenderChat',
              'chat_id': _int(sourceChat['id']) ?? 0,
            },
      'chat_id': _int(sourceChat['id']) ?? 0,
      'sending_state': null,
      'scheduling_state': null,
      'is_outgoing': isOutgoing,
      'is_pinned': source['is_pinned'] == true,
      'can_be_edited': isOutgoing,
      'can_be_forwarded': true,
      'can_be_saved': true,
      'can_be_deleted_only_for_self': false,
      'can_be_deleted_for_all_users': isOutgoing,
      'can_get_added_reactions': true,
      'can_get_statistics': false,
      'can_get_message_thread': false,
      'can_get_viewers': false,
      'can_get_media_timestamp_links': false,
      'can_report_reactions': false,
      'has_timestamped_media': false,
      'is_channel_post': _string(sourceChat['type']) == 'channel',
      'is_topic_message': source['is_topic_message'] == true,
      'contains_unread_mention': false,
      'date': _int(source['date']) ?? 0,
      'edit_date': _int(source['edit_date']) ?? 0,
      'forward_info': _forwardInfo(source),
      'import_info': null,
      'interaction_info': _interactionInfo(source),
      'unread_reactions': const <Map<String, dynamic>>[],
      'fact_check': null,
      'reply_to': _replyTo(source),
      'message_thread_id': 0,
      'topic_id': null,
      'self_destruct_type': null,
      'self_destruct_in': 0.0,
      'auto_delete_in': 0.0,
      'via_bot_user_id':
          _int(
            source['via_bot'] is Map ? (source['via_bot'] as Map)['id'] : null,
          ) ??
          0,
      'sender_business_bot_user_id': 0,
      'sender_boost_count': 0,
      'author_signature': _string(source['author_signature']),
      'media_album_id':
          _int(source['media_group_id']) ??
          _stableId(_string(source['media_group_id'])),
      'effect_id': 0,
      'restriction_reason': '',
      'content': content(source),
      'reply_markup': _replyMarkup(_map(source['reply_markup'])),
    };
  }

  Map<String, dynamic>? _replyTo(Map<String, dynamic> source) {
    final reply = _map(source['reply_to_message']);
    final id = _int(reply?['message_id']);
    if (id == null) return null;
    return {
      '@type': 'messageReplyToMessage',
      'chat_id':
          _int((_map(reply?['chat']))?['id']) ??
          _int((_map(source['chat']))?['id']) ??
          0,
      'message_id': id,
      'quote': null,
      'origin': null,
      'origin_send_date': 0,
      'content': null,
    };
  }

  Map<String, dynamic>? _forwardInfo(Map<String, dynamic> source) {
    final origin = _map(source['forward_origin']);
    if (origin != null) {
      final type = _string(origin['type']);
      final converted = switch (type) {
        'user' => {
          '@type': 'messageOriginUser',
          'sender_user_id': _int((_map(origin['sender_user']))?['id']) ?? 0,
        },
        'hidden_user' => {
          '@type': 'messageOriginHiddenUser',
          'sender_name': _string(origin['sender_user_name']),
        },
        'chat' => {
          '@type': 'messageOriginChat',
          'sender_chat_id': _int((_map(origin['sender_chat']))?['id']) ?? 0,
          'author_signature': _string(origin['author_signature']),
        },
        'channel' => {
          '@type': 'messageOriginChannel',
          'chat_id': _int((_map(origin['chat']))?['id']) ?? 0,
          'message_id': _int(origin['message_id']) ?? 0,
          'author_signature': _string(origin['author_signature']),
        },
        _ => null,
      };
      if (converted != null) {
        return {
          '@type': 'messageForwardInfo',
          'origin': converted,
          'date': _int(source['forward_date']) ?? 0,
          'source': null,
          'public_service_announcement_type': '',
        };
      }
    }
    return null;
  }

  Map<String, dynamic>? _interactionInfo(Map<String, dynamic> source) {
    final reactions = _map(source['reactions']);
    final values = _list(reactions?['reaction_counts']);
    if (values.isEmpty) return null;
    return {
      '@type': 'messageInteractionInfo',
      'view_count': 0,
      'forward_count': 0,
      'reply_info': null,
      'reactions': {
        '@type': 'messageReactions',
        'reactions': [
          for (final value in values)
            if (_map(value) case final reaction?)
              {
                '@type': 'messageReaction',
                'type': _reactionType(_map(reaction['type'])),
                'total_count': _int(reaction['total_count']) ?? 0,
                'is_chosen': false,
                'used_sender_id': null,
                'recent_sender_ids': const <Map<String, dynamic>>[],
              },
        ],
        'are_tags': false,
        'paid_reactors': const <Map<String, dynamic>>[],
        'can_get_added_reactions': true,
      },
    };
  }

  Map<String, dynamic> _reactionType(Map<String, dynamic>? type) {
    final custom = _string(type?['custom_emoji_id']);
    if (custom.isNotEmpty) {
      return {
        '@type': 'reactionTypeCustomEmoji',
        'custom_emoji_id': rememberExternalId('custom_emoji', custom),
      };
    }
    return {'@type': 'reactionTypeEmoji', 'emoji': _string(type?['emoji'])};
  }

  Map<String, dynamic>? _replyMarkup(Map<String, dynamic>? source) {
    final keyboard = _list(source?['inline_keyboard']);
    if (keyboard.isEmpty) return null;
    return {
      '@type': 'replyMarkupInlineKeyboard',
      'rows': [
        for (final row in keyboard)
          [
            for (final value in _list(row))
              if (_map(value) case final button?)
                {
                  '@type': 'inlineKeyboardButton',
                  'text': _string(button['text']),
                  'type': _buttonType(button),
                },
          ],
      ],
    };
  }

  Map<String, dynamic> _buttonType(Map<String, dynamic> button) {
    if (_string(button['url']).isNotEmpty) {
      return {
        '@type': 'inlineKeyboardButtonTypeUrl',
        'url': _string(button['url']),
      };
    }
    if (_string(button['callback_data']).isNotEmpty) {
      return {
        '@type': 'inlineKeyboardButtonTypeCallback',
        'data': _string(button['callback_data']),
      };
    }
    final webApp = _map(button['web_app']);
    if (webApp != null) {
      return {
        '@type': 'inlineKeyboardButtonTypeWebApp',
        'url': _string(webApp['url']),
      };
    }
    if (_string(button['switch_inline_query']).isNotEmpty ||
        button.containsKey('switch_inline_query')) {
      return {
        '@type': 'inlineKeyboardButtonTypeSwitchInline',
        'query': _string(button['switch_inline_query']),
        'in_current_chat': false,
      };
    }
    if (_string(button['switch_inline_query_current_chat']).isNotEmpty ||
        button.containsKey('switch_inline_query_current_chat')) {
      return {
        '@type': 'inlineKeyboardButtonTypeSwitchInline',
        'query': _string(button['switch_inline_query_current_chat']),
        'in_current_chat': true,
      };
    }
    if (_string(button['copy_text']).isNotEmpty) {
      return {
        '@type': 'inlineKeyboardButtonTypeCopyText',
        'text': _string(button['copy_text']),
      };
    }
    return const {'@type': 'inlineKeyboardButtonTypeCallback', 'data': ''};
  }

  Map<String, dynamic> _entity(Map<String, dynamic> source) => {
    '@type': 'textEntity',
    'offset': _int(source['offset']) ?? 0,
    'length': _int(source['length']) ?? 0,
    'type': _entityType(source),
  };

  Map<String, dynamic> _entityType(Map<String, dynamic> source) {
    final type = _string(source['type']);
    return switch (type) {
      'mention' => const {'@type': 'textEntityTypeMention'},
      'hashtag' => const {'@type': 'textEntityTypeHashtag'},
      'cashtag' => const {'@type': 'textEntityTypeCashtag'},
      'bot_command' => const {'@type': 'textEntityTypeBotCommand'},
      'url' => const {'@type': 'textEntityTypeUrl'},
      'email' => const {'@type': 'textEntityTypeEmailAddress'},
      'phone_number' => const {'@type': 'textEntityTypePhoneNumber'},
      'bold' => const {'@type': 'textEntityTypeBold'},
      'italic' => const {'@type': 'textEntityTypeItalic'},
      'underline' => const {'@type': 'textEntityTypeUnderline'},
      'strikethrough' => const {'@type': 'textEntityTypeStrikethrough'},
      'spoiler' => const {'@type': 'textEntityTypeSpoiler'},
      'blockquote' => const {'@type': 'textEntityTypeBlockQuote'},
      'expandable_blockquote' => const {
        '@type': 'textEntityTypeExpandableBlockQuote',
      },
      'code' => const {'@type': 'textEntityTypeCode'},
      'pre' =>
        _string(source['language']).isEmpty
            ? const {'@type': 'textEntityTypePre'}
            : {
                '@type': 'textEntityTypePreCode',
                'language': _string(source['language']),
              },
      'text_link' => {
        '@type': 'textEntityTypeTextUrl',
        'url': _string(source['url']),
      },
      'text_mention' => {
        '@type': 'textEntityTypeMentionName',
        'user_id': _int((_map(source['user']))?['id']) ?? 0,
      },
      'custom_emoji' => {
        '@type': 'textEntityTypeCustomEmoji',
        'custom_emoji_id': rememberExternalId(
          'custom_emoji',
          _string(source['custom_emoji_id']),
        ),
      },
      _ => const {'@type': 'textEntityTypeCode'},
    };
  }

  Map<String, dynamic> _photoSize(Map<String, dynamic> source) => {
    '@type': 'photoSize',
    'type': 'x',
    'photo': file(source),
    'width': _int(source['width']) ?? 0,
    'height': _int(source['height']) ?? 0,
    'progressive_sizes': const <int>[],
  };

  Map<String, dynamic> _video(Map<String, dynamic> source) => {
    '@type': 'video',
    'duration': _int(source['duration']) ?? 0,
    'width': _int(source['width']) ?? 0,
    'height': _int(source['height']) ?? 0,
    'file_name': _string(source['file_name']),
    'mime_type': _string(source['mime_type']),
    'has_stickers': false,
    'supports_streaming': true,
    'minithumbnail': null,
    'thumbnail': _thumbnail(_map(source['thumbnail'])),
    'video': file(source),
  };

  Map<String, dynamic> _animation(Map<String, dynamic> source) => {
    '@type': 'animation',
    'duration': _int(source['duration']) ?? 0,
    'width': _int(source['width']) ?? 0,
    'height': _int(source['height']) ?? 0,
    'file_name': _string(source['file_name']),
    'mime_type': _string(source['mime_type']),
    'has_stickers': false,
    'minithumbnail': null,
    'thumbnail': _thumbnail(_map(source['thumbnail'])),
    'animation': file(source),
  };

  Map<String, dynamic> _audio(Map<String, dynamic> source) => {
    '@type': 'audio',
    'duration': _int(source['duration']) ?? 0,
    'title': _string(source['title']),
    'performer': _string(source['performer']),
    'file_name': _string(source['file_name']),
    'mime_type': _string(source['mime_type']),
    'album_cover_minithumbnail': null,
    'album_cover_thumbnail': _thumbnail(_map(source['thumbnail'])),
    'external_album_covers': const <Map<String, dynamic>>[],
    'audio': file(source),
  };

  Map<String, dynamic> _document(Map<String, dynamic> source) => {
    '@type': 'document',
    'file_name': _string(source['file_name']),
    'mime_type': _string(source['mime_type']),
    'minithumbnail': null,
    'thumbnail': _thumbnail(_map(source['thumbnail'])),
    'document': file(source),
  };

  Map<String, dynamic> sticker(Map<String, dynamic> source) => _sticker(source);

  Map<String, dynamic> _sticker(Map<String, dynamic> source) {
    final animated = source['is_animated'] == true;
    final video = source['is_video'] == true;
    final setName = _string(source['set_name']);
    final customEmoji = _string(source['custom_emoji_id']);
    return {
      '@type': 'sticker',
      'id': _stableId(_string(source['file_unique_id'])),
      'set_id': rememberExternalId('sticker_set', setName),
      'width': _int(source['width']) ?? 0,
      'height': _int(source['height']) ?? 0,
      'emoji': _string(source['emoji']),
      'format': {
        '@type': video
            ? 'stickerFormatWebm'
            : animated
            ? 'stickerFormatTgs'
            : 'stickerFormatWebp',
      },
      'full_type': customEmoji.isNotEmpty
          ? {
              '@type': 'stickerFullTypeCustomEmoji',
              'custom_emoji_id': rememberExternalId(
                'custom_emoji',
                customEmoji,
              ),
              'needs_repainting': source['needs_repainting'] == true,
            }
          : const {
              '@type': 'stickerFullTypeRegular',
              'premium_animation': null,
            },
      'outline': const <Map<String, dynamic>>[],
      'thumbnail': _thumbnail(_map(source['thumbnail'])),
      'sticker': file(source),
    };
  }

  Map<String, dynamic>? _thumbnail(Map<String, dynamic>? source) =>
      source == null
      ? null
      : {
          '@type': 'thumbnail',
          'format': const {'@type': 'thumbnailFormatJpeg'},
          'width': _int(source['width']) ?? 0,
          'height': _int(source['height']) ?? 0,
          'file': file(source),
        };

  Map<String, dynamic>? _chatPhoto(Map<String, dynamic>? source) {
    if (source == null) return null;
    final smallId = _string(source['small_file_id']);
    final bigId = _string(source['big_file_id']);
    if (smallId.isEmpty && bigId.isEmpty) return null;
    final small = {
      'file_id': smallId.isNotEmpty ? smallId : bigId,
      'file_unique_id': _string(source['small_file_unique_id']),
    };
    final big = {
      'file_id': bigId.isNotEmpty ? bigId : smallId,
      'file_unique_id': _string(source['big_file_unique_id']),
    };
    return {
      '@type': 'chatPhotoInfo',
      'small': file(small),
      'big': file(big),
      'minithumbnail': null,
      'has_animation': false,
      'is_personal': false,
    };
  }

  Map<String, dynamic> _location(Map<String, dynamic> source) => {
    '@type': 'location',
    'latitude': _double(source['latitude']) ?? 0.0,
    'longitude': _double(source['longitude']) ?? 0.0,
    'horizontal_accuracy': _double(source['horizontal_accuracy']) ?? 0.0,
  };

  Map<String, dynamic> _chatType(int id, String type) => switch (type) {
    'private' => {'@type': 'chatTypePrivate', 'user_id': id},
    'group' => {'@type': 'chatTypeBasicGroup', 'basic_group_id': _peerId(id)},
    'supergroup' || 'channel' => {
      '@type': 'chatTypeSupergroup',
      'supergroup_id': _peerId(id),
      'is_channel': type == 'channel',
    },
    _ => {'@type': 'chatTypePrivate', 'user_id': id},
  };

  Map<String, dynamic> _chatPermissions() => const {
    '@type': 'chatPermissions',
    'can_send_basic_messages': true,
    'can_send_audios': true,
    'can_send_documents': true,
    'can_send_photos': true,
    'can_send_videos': true,
    'can_send_video_notes': true,
    'can_send_voice_notes': true,
    'can_send_polls': true,
    'can_send_other_messages': true,
    'can_add_link_previews': true,
    'can_change_info': false,
    'can_invite_users': false,
    'can_pin_messages': false,
    'can_create_topics': false,
  };

  Map<String, dynamic> _notificationSettings() => const {
    '@type': 'chatNotificationSettings',
    'use_default_mute_for': true,
    'mute_for': 0,
    'use_default_sound': true,
    'sound_id': -1,
    'use_default_show_preview': true,
    'show_preview': true,
    'use_default_mute_stories': true,
    'mute_stories': false,
    'use_default_story_sound': true,
    'story_sound_id': -1,
    'use_default_show_story_sender': true,
    'show_story_sender': true,
    'use_default_disable_pinned_message_notifications': true,
    'disable_pinned_message_notifications': false,
    'use_default_disable_mention_notifications': true,
    'disable_mention_notifications': false,
  };

  Map<String, dynamic> _emptyFile() => const {
    '@type': 'file',
    'id': 0,
    'size': 0,
    'expected_size': 0,
    'local': {
      '@type': 'localFile',
      'path': '',
      'can_be_downloaded': false,
      'can_be_deleted': false,
      'is_downloading_active': false,
      'is_downloading_completed': false,
      'download_offset': 0,
      'downloaded_prefix_size': 0,
      'downloaded_size': 0,
    },
    'remote': {
      '@type': 'remoteFile',
      'id': '',
      'unique_id': '',
      'is_uploading_active': false,
      'is_uploading_completed': false,
      'uploaded_size': 0,
    },
  };
}

List<Map<String, dynamic>> _uniqueUsers(List<Map<String, dynamic>> users) {
  final ids = <int>{};
  return [
    for (final value in users)
      if (ids.add(_int(value['id']) ?? 0)) value,
  ];
}

String _chatTitle(
  Map<String, dynamic> chat, {
  Map<String, dynamic>? senderChat,
}) {
  final title = _string(chat['title']);
  if (title.isNotEmpty) return title;
  final senderTitle = _string(senderChat?['title']);
  if (senderTitle.isNotEmpty) return senderTitle;
  final name = [
    _string(chat['first_name']),
    _string(chat['last_name']),
  ].where((value) => value.isNotEmpty).join(' ');
  if (name.isNotEmpty) return name;
  final username = _string(chat['username']);
  return username.isEmpty ? 'Telegram' : '@$username';
}

int _peerId(int chatId) {
  final absolute = chatId.abs();
  return absolute >= 1000000000000 ? absolute - 1000000000000 : absolute;
}

/// Bot API fields whose presence makes a message a service event.
///
/// Keep the legacy singular participant names for compatible endpoints even
/// though Telegram's current API uses `new_chat_members` and
/// `left_chat_member`.
const _botApiServiceFields = <String>{
  'new_chat_members',
  'new_chat_participant',
  'new_chat_member',
  'left_chat_member',
  'left_chat_participant',
  'chat_owner_left',
  'chat_owner_changed',
  'new_chat_title',
  'new_chat_photo',
  'delete_chat_photo',
  'group_chat_created',
  'supergroup_chat_created',
  'channel_chat_created',
  'message_auto_delete_timer_changed',
  'migrate_to_chat_id',
  'migrate_from_chat_id',
  'pinned_message',
  'successful_payment',
  'refunded_payment',
  'users_shared',
  'chat_shared',
  'gift',
  'unique_gift',
  'gift_upgrade_sent',
  'connected_website',
  'write_access_allowed',
  'proximity_alert_triggered',
  'boost_added',
  'chat_background_set',
  'checklist_tasks_done',
  'checklist_tasks_added',
  'community_chat_added',
  'community_chat_removed',
  'direct_message_price_changed',
  'forum_topic_created',
  'forum_topic_edited',
  'forum_topic_closed',
  'forum_topic_reopened',
  'general_forum_topic_hidden',
  'general_forum_topic_unhidden',
  'giveaway_created',
  'giveaway_completed',
  'managed_bot_created',
  'paid_message_price_changed',
  'poll_option_added',
  'poll_option_deleted',
  'suggested_post_approved',
  'suggested_post_approval_failed',
  'suggested_post_declined',
  'suggested_post_paid',
  'suggested_post_refunded',
  'video_chat_scheduled',
  'video_chat_started',
  'video_chat_ended',
  'video_chat_participants_invited',
  'web_app_data',
};

int _stableId(String value) {
  if (value.isEmpty) return 0;
  var hash = 0xcbf29ce484222325;
  for (final byte in value.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash;
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<Object?> _list(Object? value) => value is List ? value : const [];

String _string(Object? value) => value is String ? value : '';

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
