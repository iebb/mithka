import '../tdlib/json_helpers.dart';

Map<String, dynamic> inheritedChatNotificationSettings({
  required int muteFor,
  bool useDefaultMuteFor = false,
}) {
  return {
    '@type': 'chatNotificationSettings',
    'use_default_mute_for': useDefaultMuteFor,
    'mute_for': muteFor,
    'use_default_sound': true,
    'use_default_show_preview': true,
    'use_default_mute_stories': true,
    'use_default_story_sound': true,
    'use_default_show_story_sender': true,
    'use_default_disable_pinned_message_notifications': true,
    'use_default_disable_mention_notifications': true,
  };
}

bool hasLegacyHiddenNotificationPreview(Map<String, dynamic>? settings) {
  if (settings == null) return false;
  return !(settings.boolean('use_default_show_preview') ?? false) &&
      !(settings.boolean('show_preview') ?? false) &&
      !(settings.boolean('use_default_sound') ?? false) &&
      (settings.int64('sound_id') ?? 0) == 0 &&
      !(settings.boolean('use_default_mute_stories') ?? false) &&
      !(settings.boolean('mute_stories') ?? false) &&
      !(settings.boolean('use_default_story_sound') ?? false) &&
      (settings.int64('story_sound_id') ?? 0) == 0 &&
      !(settings.boolean('use_default_show_story_sender') ?? false) &&
      !(settings.boolean('show_story_sender') ?? false) &&
      !(settings.boolean('use_default_disable_pinned_message_notifications') ??
          false) &&
      !(settings.boolean('disable_pinned_message_notifications') ?? false) &&
      !(settings.boolean('use_default_disable_mention_notifications') ??
          false) &&
      !(settings.boolean('disable_mention_notifications') ?? false);
}

Map<String, dynamic> repairedChatNotificationSettings(
  Map<String, dynamic> settings,
) {
  return inheritedChatNotificationSettings(
    muteFor: settings.integer('mute_for') ?? 0,
    useDefaultMuteFor: settings.boolean('use_default_mute_for') ?? false,
  );
}
