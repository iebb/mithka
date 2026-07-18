import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

Map<String, dynamic> profileImportedContact({
  required String phoneNumber,
  required String firstName,
  String lastName = '',
}) => {
  '@type': 'importedContact',
  'phone_number': phoneNumber.trim(),
  'first_name': firstName.trim(),
  'last_name': lastName.trim(),
  'note': const {'@type': 'formattedText', 'text': '', 'entities': []},
};

Map<String, dynamic> addOrEditContactRequest({
  required int userId,
  required String phoneNumber,
  required String firstName,
  String lastName = '',
  bool sharePhoneNumber = false,
}) => {
  '@type': 'addContact',
  'user_id': userId,
  'contact': profileImportedContact(
    phoneNumber: phoneNumber,
    firstName: firstName,
    lastName: lastName,
  ),
  'share_phone_number': sharePhoneNumber,
};

Map<String, dynamic> removeContactRequest(int userId) => {
  '@type': 'removeContacts',
  'user_ids': [userId],
};

Map<String, dynamic> sharePhoneNumberRequest(int userId) => {
  '@type': 'sharePhoneNumber',
  'user_id': userId,
};

Map<String, dynamic> setUserNoteRequest(int userId, String note) => {
  '@type': 'setUserNote',
  'user_id': userId,
  'note': {'@type': 'formattedText', 'text': note.trim(), 'entities': []},
};

Map<String, dynamic> localStaticChatPhoto(String path) => {
  '@type': 'inputChatPhotoStatic',
  'photo': {'@type': 'inputFileLocal', 'path': path},
};

Map<String, dynamic> previousChatPhoto(int photoId) => {
  '@type': 'inputChatPhotoPrevious',
  'chat_photo_id': photoId,
};

Map<String, dynamic> setOwnProfilePhotoRequest({
  required Map<String, dynamic> photo,
  required bool isPublic,
}) => {'@type': 'setProfilePhoto', 'photo': photo, 'is_public': isPublic};

Map<String, dynamic> deleteOwnProfilePhotoRequest(int photoId) => {
  '@type': 'deleteProfilePhoto',
  'profile_photo_id': photoId,
};

Map<String, dynamic> setPersonalProfilePhotoRequest({
  required int userId,
  Map<String, dynamic>? photo,
}) => {
  '@type': 'setUserPersonalProfilePhoto',
  'user_id': userId,
  'photo': photo,
};

Map<String, dynamic> suggestProfilePhotoRequest({
  required int userId,
  required Map<String, dynamic> photo,
}) => {'@type': 'suggestUserProfilePhoto', 'user_id': userId, 'photo': photo};

Map<String, dynamic> suggestBirthdateRequest({
  required int userId,
  required int day,
  required int month,
  int year = 0,
}) => {
  '@type': 'suggestUserBirthdate',
  'user_id': userId,
  'birthdate': {'@type': 'birthdate', 'day': day, 'month': month, 'year': year},
};

Map<String, dynamic> setPersonalChatRequest(int chatId) => {
  '@type': 'setPersonalChat',
  'chat_id': chatId,
};

Map<String, dynamic> setGiftSettingsRequest(GiftAcceptanceSettings value) => {
  '@type': 'setGiftSettings',
  'settings': {
    '@type': 'giftSettings',
    'show_gift_button': value.showGiftButton,
    'accepted_gift_types': {
      '@type': 'acceptedGiftTypes',
      'unlimited_gifts': value.unlimitedGifts,
      'limited_gifts': value.limitedGifts,
      'upgraded_gifts': value.upgradedGifts,
      'gifts_from_channels': value.giftsFromChannels,
      'premium_subscription': value.premiumSubscription,
    },
  },
};

class GiftAcceptanceSettings {
  const GiftAcceptanceSettings({
    required this.showGiftButton,
    required this.unlimitedGifts,
    required this.limitedGifts,
    required this.upgradedGifts,
    required this.giftsFromChannels,
    required this.premiumSubscription,
  });

  factory GiftAcceptanceSettings.fromFullInfo(Map<String, dynamic> value) {
    final settings = value.obj('gift_settings');
    final accepted = settings?.obj('accepted_gift_types');
    return GiftAcceptanceSettings(
      showGiftButton: settings?.boolean('show_gift_button') ?? true,
      unlimitedGifts: accepted?.boolean('unlimited_gifts') ?? true,
      limitedGifts: accepted?.boolean('limited_gifts') ?? true,
      upgradedGifts: accepted?.boolean('upgraded_gifts') ?? true,
      giftsFromChannels: accepted?.boolean('gifts_from_channels') ?? true,
      premiumSubscription: accepted?.boolean('premium_subscription') ?? true,
    );
  }

  final bool showGiftButton;
  final bool unlimitedGifts;
  final bool limitedGifts;
  final bool upgradedGifts;
  final bool giftsFromChannels;
  final bool premiumSubscription;

  GiftAcceptanceSettings copyWith({
    bool? showGiftButton,
    bool? unlimitedGifts,
    bool? limitedGifts,
    bool? upgradedGifts,
    bool? giftsFromChannels,
    bool? premiumSubscription,
  }) => GiftAcceptanceSettings(
    showGiftButton: showGiftButton ?? this.showGiftButton,
    unlimitedGifts: unlimitedGifts ?? this.unlimitedGifts,
    limitedGifts: limitedGifts ?? this.limitedGifts,
    upgradedGifts: upgradedGifts ?? this.upgradedGifts,
    giftsFromChannels: giftsFromChannels ?? this.giftsFromChannels,
    premiumSubscription: premiumSubscription ?? this.premiumSubscription,
  );
}

class ProfileContactSnapshot {
  const ProfileContactSnapshot({
    required this.needPhoneNumberPrivacyException,
    required this.note,
    required this.personalChatId,
    required this.personalPhotoId,
    required this.currentPhotoId,
    required this.publicPhotoId,
  });

  factory ProfileContactSnapshot.fromFullInfo(Map<String, dynamic> value) =>
      ProfileContactSnapshot(
        needPhoneNumberPrivacyException:
            value.boolean('need_phone_number_privacy_exception') ?? false,
        note: value.obj('note')?.str('text') ?? '',
        personalChatId: value.int64('personal_chat_id') ?? 0,
        personalPhotoId: value.obj('personal_photo')?.int64('id') ?? 0,
        currentPhotoId: value.obj('photo')?.int64('id') ?? 0,
        publicPhotoId: value.obj('public_photo')?.int64('id') ?? 0,
      );

  final bool needPhoneNumberPrivacyException;
  final String note;
  final int personalChatId;
  final int personalPhotoId;
  final int currentPhotoId;
  final int publicPhotoId;
}

class ProfileContactService {
  const ProfileContactService([this._client]);

  final TdClient? _client;
  TdClient get _td => _client ?? TdClient.shared;

  Future<void> addOrEdit({
    required int userId,
    required String phoneNumber,
    required String firstName,
    String lastName = '',
    bool sharePhoneNumber = false,
  }) async {
    await _td.query(
      addOrEditContactRequest(
        userId: userId,
        phoneNumber: phoneNumber,
        firstName: firstName,
        lastName: lastName,
        sharePhoneNumber: sharePhoneNumber,
      ),
    );
  }

  Future<void> remove(int userId) async {
    await _td.query(removeContactRequest(userId));
  }

  Future<void> sharePhone(int userId) async {
    await _td.query(sharePhoneNumberRequest(userId));
  }

  Future<void> setNote(int userId, String note) async {
    await _td.query(setUserNoteRequest(userId, note));
  }

  Future<void> setPersonalPhoto(int userId, String path) async {
    await _td.query(
      setPersonalProfilePhotoRequest(
        userId: userId,
        photo: localStaticChatPhoto(path),
      ),
    );
  }

  Future<void> deletePersonalPhoto(int userId) async {
    await _td.query(setPersonalProfilePhotoRequest(userId: userId));
  }

  Future<void> suggestPhoto(int userId, String path) async {
    await _td.query(
      suggestProfilePhotoRequest(
        userId: userId,
        photo: localStaticChatPhoto(path),
      ),
    );
  }

  Future<void> suggestBirthdate(
    int userId, {
    required int day,
    required int month,
    int year = 0,
  }) async {
    await _td.query(
      suggestBirthdateRequest(
        userId: userId,
        day: day,
        month: month,
        year: year,
      ),
    );
  }

  Future<void> setPersonalChat(int chatId) async {
    await _td.query(setPersonalChatRequest(chatId));
  }

  Future<void> setGiftSettings(GiftAcceptanceSettings value) async {
    await _td.query(setGiftSettingsRequest(value));
  }
}
