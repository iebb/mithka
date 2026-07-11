import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/notification_settings_payload.dart';

void main() {
  test('mute payload keeps message previews inherited', () {
    final payload = inheritedChatNotificationSettings(muteFor: 2147483647);

    expect(payload['mute_for'], 2147483647);
    expect(payload['use_default_mute_for'], isFalse);
    expect(payload['use_default_show_preview'], isTrue);
    expect(payload['use_default_sound'], isTrue);
    expect(payload['use_default_show_story_sender'], isTrue);
  });

  test('detects the legacy partial mute payload returned by TDLib', () {
    expect(
      hasLegacyHiddenNotificationPreview({
        'use_default_mute_for': false,
        'mute_for': 0,
        'use_default_sound': false,
        'sound_id': 0,
        'use_default_show_preview': false,
        'show_preview': false,
        'use_default_mute_stories': false,
        'mute_stories': false,
        'use_default_story_sound': false,
        'story_sound_id': 0,
        'use_default_show_story_sender': false,
        'show_story_sender': false,
        'use_default_disable_pinned_message_notifications': false,
        'disable_pinned_message_notifications': false,
        'use_default_disable_mention_notifications': false,
        'disable_mention_notifications': false,
      }),
      isTrue,
    );
  });

  test('does not override an intentional preview-only preference', () {
    expect(
      hasLegacyHiddenNotificationPreview({
        'use_default_show_preview': false,
        'show_preview': false,
        'use_default_sound': true,
        'use_default_mute_stories': true,
        'use_default_story_sound': true,
        'use_default_show_story_sender': true,
        'use_default_disable_pinned_message_notifications': true,
        'use_default_disable_mention_notifications': true,
      }),
      isFalse,
    );
  });

  test('repair preserves mute while restoring inherited preview', () {
    final payload = repairedChatNotificationSettings({
      'use_default_mute_for': false,
      'mute_for': 3600,
    });

    expect(payload['use_default_mute_for'], isFalse);
    expect(payload['mute_for'], 3600);
    expect(payload['use_default_show_preview'], isTrue);
  });
}
