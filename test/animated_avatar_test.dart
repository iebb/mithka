import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/tdlib/animated_avatar_repository.dart';
import 'package:mithka/tdlib/avatar_animation_index.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('avatar players require an active visible surface', () {
    expect(
      avatarAnimationIsEligible(
        surfaceAllowsAnimation: true,
        themeAllowsAnimation: true,
        tickerEnabled: true,
        appIsActive: true,
      ),
      isTrue,
    );
    for (final blocked in [
      (surface: false, theme: true, ticker: true, app: true),
      (surface: true, theme: false, ticker: true, app: true),
      (surface: true, theme: true, ticker: false, app: true),
      (surface: true, theme: true, ticker: true, app: false),
    ]) {
      expect(
        avatarAnimationIsEligible(
          surfaceAllowsAnimation: blocked.surface,
          themeAllowsAnimation: blocked.theme,
          tickerEnabled: blocked.ticker,
          appIsActive: blocked.app,
        ),
        isFalse,
      );
    }
  });

  test('profile photo parser preserves animated avatar metadata', () {
    final photo = TDParse.smallPhoto({
      '@type': 'profilePhoto',
      'id': '987654321',
      'has_animation': true,
      'small': {
        '@type': 'file',
        'id': 2345,
        'local': {'path': '/tmp/avatar.jpg', 'is_downloading_completed': true},
      },
    });

    expect(photo, isNotNull);
    expect(photo!.id, 2345);
    expect(photo.hasAnimation, isTrue);
    expect(photo.photoId, 987654321);
  });

  test('animation index associates animated user and chat photos by slot', () {
    const slot = 91;
    AvatarAnimationIndex.shared.observe(slot, {
      '@type': 'user',
      'id': '101',
      'profile_photo': {
        '@type': 'profilePhoto',
        'has_animation': true,
        'small': {'@type': 'file', 'id': 7001},
      },
    });
    AvatarAnimationIndex.shared.observe(slot, {
      '@type': 'updateChatPhoto',
      'chat_id': '-202',
      'photo': {
        '@type': 'chatPhotoInfo',
        'has_animation': true,
        'small': {'@type': 'file', 'id': 7002},
      },
    });

    final user = AvatarAnimationIndex.shared.ownerFor(slot, 7001);
    final chat = AvatarAnimationIndex.shared.ownerFor(slot, 7002);
    expect(user?.kind, AvatarOwnerKind.user);
    expect(user?.id, 101);
    expect(chat?.kind, AvatarOwnerKind.chat);
    expect(chat?.id, -202);
  });

  test('chat photo resolves the small MPEG-4 animation first', () {
    final animation = animatedAvatarFileFromChatPhoto({
      '@type': 'chatPhoto',
      'small_animation': {
        '@type': 'animatedChatPhoto',
        'file': {
          '@type': 'file',
          'id': 8101,
          'local': {
            'path': '/tmp/avatar-small.mp4',
            'is_downloading_completed': true,
          },
        },
      },
      'animation': {
        '@type': 'animatedChatPhoto',
        'file': {'@type': 'file', 'id': 8102},
      },
    });

    expect(animation?.id, 8101);
    expect(animation?.localPath, '/tmp/avatar-small.mp4');
  });

  test(
    'animated avatars default on and can be suppressed persistently',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      expect(theme.animateAvatars, isTrue);

      theme.animateAvatars = false;
      expect(theme.animateAvatars, isFalse);
      expect(ThemeController(prefs).animateAvatars, isFalse);
    },
  );
}
