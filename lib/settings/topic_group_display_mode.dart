//
//  topic_group_display_mode.dart
//
//  Persists how forum/topic groups open from the chat list.
//

import 'package:shared_preferences/shared_preferences.dart';

enum TopicGroupDisplayMode {
  channel,
  chat;

  bool get isChat => this == TopicGroupDisplayMode.chat;
}

final class TopicGroupDisplayPreference {
  const TopicGroupDisplayPreference._();

  static const _key = 'topicGroup.displayMode';

  static Future<TopicGroupDisplayMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_key)) {
      'chat' => TopicGroupDisplayMode.chat,
      _ => TopicGroupDisplayMode.channel,
    };
  }

  static Future<void> set(TopicGroupDisplayMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
