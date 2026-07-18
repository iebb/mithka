import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/group_administration_service.dart';

void main() {
  test('invite links and join requests use the current TDLib fields', () async {
    final requests = <Map<String, dynamic>>[];
    final service = GroupAdministrationService(
      query: (request) async {
        requests.add(request);
        return switch (request['@type']) {
          'getChatInviteLinkCounts' => {
            '@type': 'chatInviteLinkCounts',
            'invite_link_counts': [
              {'@type': 'chatInviteLinkCount', 'user_id': 5},
            ],
          },
          'getChatInviteLinks' => {
            '@type': 'chatInviteLinks',
            'invite_links': <Map<String, dynamic>>[],
          },
          'getChatJoinRequests' => {
            '@type': 'chatJoinRequests',
            'requests': <Map<String, dynamic>>[],
          },
          'getChatInviteLinkMembers' => {
            '@type': 'chatInviteLinkMembers',
            'members': <Map<String, dynamic>>[],
          },
          _ => {'@type': 'ok'},
        };
      },
    );

    expect((await service.inviteLinkCreatorCounts(10)).single['user_id'], 5);
    await service.inviteLinks(chatId: 10, creatorUserId: 5);
    await service.createInviteLink(
      chatId: 10,
      name: ' Team ',
      expirationDate: 123,
      memberLimit: 25,
      createsJoinRequest: false,
    );
    await service.editInviteLink(
      chatId: 10,
      inviteLink: 'https://t.me/+abc',
      name: ' Approval ',
      expirationDate: 456,
      memberLimit: 99,
      createsJoinRequest: true,
    );
    await service.inviteLinkMembers(10, 'https://t.me/+abc');
    await service.revokeInviteLink(10, 'https://t.me/+abc');
    await service.joinRequests(10);
    await service.processJoinRequest(10, 7, approve: true);
    await service.processAllJoinRequests(10, approve: false);
    await service.setJoinByRequest(30, true);

    expect(requests[0], {'@type': 'getChatInviteLinkCounts', 'chat_id': 10});
    expect(requests[1], {
      '@type': 'getChatInviteLinks',
      'chat_id': 10,
      'creator_user_id': 5,
      'is_revoked': false,
      'offset_date': 0,
      'offset_invite_link': '',
      'limit': 100,
    });
    expect(requests[2]['name'], 'Team');
    expect(requests[2]['member_limit'], 25);
    expect(requests[3]['creates_join_request'], isTrue);
    expect(requests[3]['member_limit'], 0);
    expect(requests[4]['only_with_expired_subscription'], isFalse);
    expect(requests[4]['offset_member'], isNull);
    expect(requests[5]['@type'], 'revokeChatInviteLink');
    expect(requests[6]['offset_request'], isNull);
    expect(requests[7]['approve'], isTrue);
    expect(requests[8]['@type'], 'processChatJoinRequests');
    expect(requests[8]['approve'], isFalse);
    expect(requests[9], {
      '@type': 'toggleSupergroupJoinByRequest',
      'supergroup_id': 30,
      'join_by_request': true,
      'guard_bot_user_id': 0,
      'apply_to_invite_links': true,
    });
  });

  test('advanced controls send exact current request shapes', () async {
    final requests = <Map<String, dynamic>>[];
    final service = GroupAdministrationService(
      query: (request) async {
        requests.add(request);
        return {'@type': 'ok'};
      },
    );

    await service.setSlowMode(10, 30);
    await service.setProtectedContent(10, true);
    await service.setAvailableReactions(10, {
      '@type': 'chatAvailableReactionsSome',
      'reactions': [
        {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
      ],
      'max_reaction_count': 2,
    });
    await service.setDiscussionGroup(10, 20);
    await service.setHiddenMembers(30, true);
    await service.setAggressiveAntiSpam(30, true);
    await service.setAutomaticTranslation(30, true);
    await service.setMemberTag(10, 40, ' Helper ');

    expect(requests.map((request) => request['@type']), [
      'setChatSlowModeDelay',
      'toggleChatHasProtectedContent',
      'setChatAvailableReactions',
      'setChatDiscussionGroup',
      'toggleSupergroupHasHiddenMembers',
      'toggleSupergroupHasAggressiveAntiSpamEnabled',
      'toggleSupergroupHasAutomaticTranslation',
      'setChatMemberTag',
    ]);
    expect(requests[0]['slow_mode_delay'], 30);
    expect(requests[2]['available_reactions'], {
      '@type': 'chatAvailableReactionsSome',
      'reactions': [
        {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
      ],
      'max_reaction_count': 2,
    });
    expect(requests[3]['discussion_chat_id'], 20);
    expect(requests[5]['has_aggressive_anti_spam_enabled'], isTrue);
    expect(requests[6]['has_automatic_translation'], isTrue);
    expect(requests[7]['tag'], 'Helper');
  });

  test(
    'profile and core channel or group toggles use pinned request fields',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = GroupAdministrationService(
        query: (request) async {
          requests.add(request);
          return {'@type': 'ok'};
        },
      );

      await service.setDescription(10, ' Community description ');
      await service.setPhoto(10, '/tmp/group.jpg');
      await service.removePhoto(10);
      await service.setSignedMessages(
        supergroupId: 30,
        signMessages: true,
        showMessageSender: true,
      );
      await service.setAllHistoryAvailable(30, true);
      await service.setForumMode(
        supergroupId: 30,
        isForum: true,
        hasForumTabs: true,
      );
      await service.setForumMode(
        supergroupId: 30,
        isForum: false,
        hasForumTabs: true,
      );

      expect(requests[0], {
        '@type': 'setChatDescription',
        'chat_id': 10,
        'description': 'Community description',
      });
      expect(requests[1], {
        '@type': 'setChatPhoto',
        'chat_id': 10,
        'photo': {
          '@type': 'inputChatPhotoStatic',
          'photo': {'@type': 'inputFileLocal', 'path': '/tmp/group.jpg'},
        },
      });
      expect(requests[2], {
        '@type': 'setChatPhoto',
        'chat_id': 10,
        'photo': null,
      });
      expect(requests[3], {
        '@type': 'toggleSupergroupSignMessages',
        'supergroup_id': 30,
        'sign_messages': true,
        'show_message_sender': true,
      });
      expect(requests[4], {
        '@type': 'toggleSupergroupIsAllHistoryAvailable',
        'supergroup_id': 30,
        'is_all_history_available': true,
      });
      expect(requests[5], {
        '@type': 'toggleSupergroupIsForum',
        'supergroup_id': 30,
        'is_forum': true,
        'has_forum_tabs': true,
      });
      expect(requests[6]['is_forum'], isFalse);
      expect(requests[6]['has_forum_tabs'], isFalse);
    },
  );

  test('invite link listing follows TDLib pagination offsets', () async {
    final requests = <Map<String, dynamic>>[];
    final service = GroupAdministrationService(
      query: (request) async {
        requests.add(request);
        final first = request['offset_invite_link'] == '';
        return {
          '@type': 'chatInviteLinks',
          'invite_links': first
              ? List.generate(
                  100,
                  (index) => {
                    '@type': 'chatInviteLink',
                    'date': 200 - index,
                    'invite_link': 'link-$index',
                  },
                )
              : [
                  {
                    '@type': 'chatInviteLink',
                    'date': 100,
                    'invite_link': 'last-link',
                  },
                ],
        };
      },
    );

    final links = await service.inviteLinks(chatId: 10, creatorUserId: 5);

    expect(links, hasLength(101));
    expect(requests, hasLength(2));
    expect(requests.last['offset_date'], 101);
    expect(requests.last['offset_invite_link'], 'link-99');
  });

  test(
    'forum topic, statistics, and boost entry requests are complete',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = GroupAdministrationService(
        query: (request) async {
          requests.add(request);
          return {'@type': 'ok'};
        },
      );

      await service.createForumTopic(
        chatId: 10,
        name: ' News ',
        color: 0x6FB9F0,
      );
      await service.editForumTopic(
        chatId: 10,
        forumTopicId: 12,
        name: 'Updates',
        customEmojiId: 44,
      );
      await service.toggleForumTopicPinned(10, 12, true);
      await service.reorderPinnedForumTopics(10, [12, 9]);
      await service.statistics(10, dark: true);
      await service.boostStatus(10);
      await service.boostLink(10);
      await service.boosts(10);
      await service.premiumGiveawayOptions(10);
      await service.starGiveawayOptions();

      expect((requests[0]['icon'] as Map)['color'], 0x6FB9F0);
      expect(requests[0]['is_name_implicit'], isFalse);
      expect(requests[1]['edit_icon_custom_emoji'], isTrue);
      expect(requests[1]['icon_custom_emoji_id'], 44);
      expect(requests[3]['forum_topic_ids'], [12, 9]);
      expect(requests[4], {
        '@type': 'getChatStatistics',
        'chat_id': 10,
        'is_dark': true,
      });
      expect(requests.map((request) => request['@type']).skip(5), [
        'getChatBoostStatus',
        'getChatBoostLink',
        'getChatBoosts',
        'getPremiumGiveawayPaymentOptions',
        'getStarGiveawayPaymentOptions',
      ]);
    },
  );
}
