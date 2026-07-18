import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/profile/profile_contact_service.dart';

void main() {
  test(
    'contact edit uses pinned importedContact schema and phone exception',
    () {
      expect(
        addOrEditContactRequest(
          userId: 42,
          phoneNumber: ' +81 90 ',
          firstName: ' Ada ',
          lastName: ' Lovelace ',
          sharePhoneNumber: true,
        ),
        {
          '@type': 'addContact',
          'user_id': 42,
          'contact': {
            '@type': 'importedContact',
            'phone_number': '+81 90',
            'first_name': 'Ada',
            'last_name': 'Lovelace',
            'note': {'@type': 'formattedText', 'text': '', 'entities': []},
          },
          'share_phone_number': true,
        },
      );
    },
  );

  test('remove and mutual-contact phone share preserve user identifier', () {
    expect(removeContactRequest(19), {
      '@type': 'removeContacts',
      'user_ids': [19],
    });
    expect(sharePhoneNumberRequest(19), {
      '@type': 'sharePhoneNumber',
      'user_id': 19,
    });
  });

  test('private note is an exact formattedText request', () {
    expect(setUserNoteRequest(11, '  met at FOSDEM  '), {
      '@type': 'setUserNote',
      'user_id': 11,
      'note': {
        '@type': 'formattedText',
        'text': 'met at FOSDEM',
        'entities': [],
      },
    });
  });

  test('local and previous photo inputs match pinned InputChatPhoto types', () {
    expect(localStaticChatPhoto('/tmp/avatar.jpg'), {
      '@type': 'inputChatPhotoStatic',
      'photo': {'@type': 'inputFileLocal', 'path': '/tmp/avatar.jpg'},
    });
    expect(previousChatPhoto(9007199254740000), {
      '@type': 'inputChatPhotoPrevious',
      'chat_photo_id': 9007199254740000,
    });
  });

  test('own profile photo can be current, public, or deleted', () {
    final previous = previousChatPhoto(99);
    expect(setOwnProfilePhotoRequest(photo: previous, isPublic: false), {
      '@type': 'setProfilePhoto',
      'photo': previous,
      'is_public': false,
    });
    expect(setOwnProfilePhotoRequest(photo: previous, isPublic: true), {
      '@type': 'setProfilePhoto',
      'photo': previous,
      'is_public': true,
    });
    expect(deleteOwnProfilePhotoRequest(99), {
      '@type': 'deleteProfilePhoto',
      'profile_photo_id': 99,
    });
  });

  test('featured-photo preview wires owned set-avatar and delete actions', () {
    final source = File(
      'lib/profile/profile_detail_view.dart',
    ).readAsStringSync();
    expect(source, contains('profilePhotoSetAsAvatar'));
    expect(source, contains('setOwnProfilePhotoRequest('));
    expect(source, contains('previousChatPhoto(photo.id)'));
    expect(source, contains('deleteOwnProfilePhotoRequest(photo.id)'));
    expect(source, contains("ValueKey('featured-photo-delete')"));
    expect(source, contains('showAppConfirmDialog('));
  });

  test('contact personal photo can be set or cleared with null', () {
    final photo = localStaticChatPhoto('/tmp/personal.jpg');
    expect(setPersonalProfilePhotoRequest(userId: 4, photo: photo), {
      '@type': 'setUserPersonalProfilePhoto',
      'user_id': 4,
      'photo': photo,
    });
    expect(setPersonalProfilePhotoRequest(userId: 4), {
      '@type': 'setUserPersonalProfilePhoto',
      'user_id': 4,
      'photo': null,
    });
  });

  test('suggested profile photo and birthdate use dedicated methods', () {
    final photo = localStaticChatPhoto('/tmp/suggested.jpg');
    expect(suggestProfilePhotoRequest(userId: 7, photo: photo), {
      '@type': 'suggestUserProfilePhoto',
      'user_id': 7,
      'photo': photo,
    });
    expect(suggestBirthdateRequest(userId: 7, day: 10, month: 12), {
      '@type': 'suggestUserBirthdate',
      'user_id': 7,
      'birthdate': {'@type': 'birthdate', 'day': 10, 'month': 12, 'year': 0},
    });
  });

  test('personal chat can be selected or cleared with zero', () {
    expect(setPersonalChatRequest(123), {
      '@type': 'setPersonalChat',
      'chat_id': 123,
    });
    expect(setPersonalChatRequest(0), {
      '@type': 'setPersonalChat',
      'chat_id': 0,
    });
  });

  test('gift acceptance request includes every pinned gift type', () {
    const settings = GiftAcceptanceSettings(
      showGiftButton: false,
      unlimitedGifts: true,
      limitedGifts: false,
      upgradedGifts: true,
      giftsFromChannels: false,
      premiumSubscription: true,
    );
    expect(setGiftSettingsRequest(settings), {
      '@type': 'setGiftSettings',
      'settings': {
        '@type': 'giftSettings',
        'show_gift_button': false,
        'accepted_gift_types': {
          '@type': 'acceptedGiftTypes',
          'unlimited_gifts': true,
          'limited_gifts': false,
          'upgraded_gifts': true,
          'gifts_from_channels': false,
          'premium_subscription': true,
        },
      },
    });
  });

  test('gift acceptance settings parse from user full info', () {
    final value = GiftAcceptanceSettings.fromFullInfo({
      'gift_settings': {
        '@type': 'giftSettings',
        'show_gift_button': false,
        'accepted_gift_types': {
          '@type': 'acceptedGiftTypes',
          'unlimited_gifts': false,
          'limited_gifts': true,
          'upgraded_gifts': false,
          'gifts_from_channels': true,
          'premium_subscription': false,
        },
      },
    });
    expect(value.showGiftButton, isFalse);
    expect(value.unlimitedGifts, isFalse);
    expect(value.limitedGifts, isTrue);
    expect(value.upgradedGifts, isFalse);
    expect(value.giftsFromChannels, isTrue);
    expect(value.premiumSubscription, isFalse);
  });

  test('full info snapshot preserves profile variants and privacy hint', () {
    final snapshot = ProfileContactSnapshot.fromFullInfo({
      'need_phone_number_privacy_exception': true,
      'note': {'@type': 'formattedText', 'text': 'coworker', 'entities': []},
      'personal_chat_id': 501,
      'personal_photo': {'@type': 'chatPhoto', 'id': 1},
      'photo': {'@type': 'chatPhoto', 'id': 2},
      'public_photo': {'@type': 'chatPhoto', 'id': 3},
    });
    expect(snapshot.needPhoneNumberPrivacyException, isTrue);
    expect(snapshot.note, 'coworker');
    expect(snapshot.personalChatId, 501);
    expect(snapshot.personalPhotoId, 1);
    expect(snapshot.currentPhotoId, 2);
    expect(snapshot.publicPhotoId, 3);
  });
}
