import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_photo_policy.dart';

void main() {
  test('non-premium users cannot build an animated profile photo request', () {
    expect(
      animatedProfilePhotoRequest(isPremium: false, path: '/tmp/avatar.mp4'),
      isNull,
    );
  });

  test('premium animated profile photo request preserves the local file', () {
    final request = animatedProfilePhotoRequest(
      isPremium: true,
      path: '/tmp/avatar.mp4',
    );

    expect(request?['@type'], 'setProfilePhoto');
    expect(request?['is_public'], isFalse);
    final photo = request?['photo'] as Map<String, dynamic>;
    expect(photo['@type'], 'inputChatPhotoAnimation');
    expect(photo['main_frame_timestamp'], 0.0);
    expect(photo['animation'], {
      '@type': 'inputFileLocal',
      'path': '/tmp/avatar.mp4',
    });
  });

  test('empty animated avatar paths never produce an upload request', () {
    expect(animatedProfilePhotoRequest(isPremium: true, path: ''), isNull);
  });

  test('premium requirement is localized for every supported locale', () {
    for (final locale in const [
      'en',
      'de',
      'es',
      'fr',
      'ja',
      'ko',
      'zhHans',
      'zhHant',
    ]) {
      expect(
        AppStrings.tForLocale(
          locale,
          AppStringKeys.editProfileAnimatedAvatarPremiumRequired,
        ),
        isNot(AppStringKeys.editProfileAnimatedAvatarPremiumRequired),
        reason: locale,
      );
    }
  });
}
