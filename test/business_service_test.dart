import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/business_service.dart';

void main() {
  group('BusinessRecipientsDraft', () {
    test('round-trips every recipient selector', () {
      final value = BusinessRecipientsDraft.fromJson({
        'chat_ids': ['11', 22],
        'excluded_chat_ids': [33],
        'select_existing_chats': false,
        'select_new_chats': true,
        'select_contacts': false,
        'select_non_contacts': true,
        'exclude_selected': true,
      });

      expect(value.chatIds, [11, 22]);
      expect(value.excludedChatIds, [33]);
      expect(value.toJson(), {
        '@type': 'businessRecipients',
        'chat_ids': [11, 22],
        'excluded_chat_ids': <int>[],
        'select_existing_chats': false,
        'select_new_chats': true,
        'select_contacts': false,
        'select_non_contacts': true,
        'exclude_selected': true,
      });
      expect(value.toJson(allowExcludedChats: true)['excluded_chat_ids'], [33]);
    });
  });

  test('business bot rights use the pinned TDLib field names', () {
    final payload = const BusinessBotRightsDraft(
      canDeleteSentMessages: true,
      canDeleteAllMessages: true,
      canEditName: true,
      canEditBio: true,
      canEditProfilePhoto: true,
      canEditUsername: true,
      canViewGiftsAndStars: true,
      canSellGifts: true,
      canChangeGiftSettings: true,
      canTransferAndUpgradeGifts: true,
      canTransferStars: true,
      canManageStories: true,
    ).toJson();

    expect(payload['@type'], 'businessBotRights');
    expect(payload.keys.toSet(), {
      '@type',
      'can_reply',
      'can_read_messages',
      'can_delete_sent_messages',
      'can_delete_all_messages',
      'can_edit_name',
      'can_edit_bio',
      'can_edit_profile_photo',
      'can_edit_username',
      'can_view_gifts_and_stars',
      'can_sell_gifts',
      'can_change_gift_settings',
      'can_transfer_and_upgrade_gifts',
      'can_transfer_stars',
      'can_manage_stories',
    });
    expect(payload.values.whereType<bool>().every((value) => value), isTrue);
  });

  group('quick reply payloads', () {
    test('text input matches inputMessageText', () {
      expect(businessTextInput('Hello'), {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': 'Hello',
          'entities': <Map<String, dynamic>>[],
        },
        'link_preview_options': null,
        'clear_draft': false,
      });
    });

    test('previews text and captioned media', () {
      expect(
        businessQuickReplyContentPreview({
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'Welcome'},
        }),
        'Welcome',
      );
      expect(
        businessQuickReplyContentPreview({
          '@type': 'messagePhoto',
          'caption': {'@type': 'formattedText', 'text': 'Price list'},
        }),
        'Price list',
      );
      expect(
        businessQuickReplyContentPreview({'@type': 'messageVideo'}),
        'Video',
      );
    });
  });

  test('capabilities require both Premium and runtime support', () {
    const locked = BusinessCapabilities(
      isPremium: false,
      features: {'businessFeatureQuickReplies'},
    );
    const available = BusinessCapabilities(
      isPremium: true,
      features: {'businessFeatureQuickReplies'},
    );

    expect(locked.supports('businessFeatureQuickReplies'), isTrue);
    expect(locked.canUse('businessFeatureQuickReplies'), isFalse);
    expect(available.canUse('businessFeatureQuickReplies'), isTrue);
    expect(available.supports('businessFeatureBots'), isFalse);
  });

  group('business feature resolution', () {
    test('uses the server-advertised feature list when present', () {
      expect(
        resolvedBusinessFeatures({
          'features': [
            {'@type': 'businessFeatureLocation'},
            {'@type': 'businessFeatureOpeningHours'},
          ],
        }),
        {'businessFeatureLocation', 'businessFeatureOpeningHours'},
      );
    });

    test('retains bundled features when the probe fails or is empty', () {
      expect(resolvedBusinessFeatures(null), bundledBusinessFeatures);
      expect(
        resolvedBusinessFeatures({'features': const []}),
        bundledBusinessFeatures,
      );
      expect(
        resolvedBusinessFeatures(null),
        containsAll({
          'businessFeatureLocation',
          'businessFeatureOpeningHours',
          'businessFeatureStartPage',
        }),
      );
    });
  });
}
