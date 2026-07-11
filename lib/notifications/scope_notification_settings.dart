//  scope_notification_settings.dart
//  Cached scope-level notification settings (mute_for) used to compute effective mute state.

import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/json_helpers.dart';
import 'package:mithka/tdlib/td_models.dart' show ChatKind;

class ScopeNotificationSettings {
  ScopeNotificationSettings._();
  static final ScopeNotificationSettings shared = ScopeNotificationSettings._();

  static const _private = 'notificationSettingsScopePrivateChats';
  static const _group = 'notificationSettingsScopeGroupChats';
  static const _channel = 'notificationSettingsScopeChannelChats';

  final Map<String, int> _muteFor = {};
  bool _loaded = false;

  /// Loads mute_for values for all three scopes from TDLib.
  Future<void> load() async {
    final client = TdClient.shared;
    for (final scope in const [_private, _group, _channel]) {
      try {
        final s = await client.query({
          '@type': 'getScopeNotificationSettings',
          'scope': {'@type': scope},
        });
        _muteFor[scope] = s.integer('mute_for') ?? 0;
      } catch (_) {
        _muteFor[scope] = _muteFor[scope] ?? 0;
      }
    }
    _loaded = true;
  }

  /// Updates the cached mute_for for a scope (called after user changes settings).
  void update(String scope, int muteFor) {
    _muteFor[scope] = muteFor;
  }

  /// Returns cached mute_for for a stored scope identifier.
  int getMuteForScope(String tag) => _muteFor[tag] ?? 0;

  /// Maps a [ChatKind] to its stored scope identifier.
  String scopeTagForKind(ChatKind kind) {
    switch (kind) {
      case ChatKind.privateChat:
        return _private;
      case ChatKind.group:
        return _group;
      case ChatKind.channel:
        return _channel;
      default:
        return _private;
    }
  }

  /// Determines the scope key for a given chat map.
  String _scopeForChat(Map<String, dynamic> chat) {
    final type = chat.obj('type');
    switch (type?.type) {
      case 'chatTypePrivate':
      case 'chatTypeSecret':
        return _private;
      case 'chatTypeBasicGroup':
        return _group;
      case 'chatTypeSupergroup':
        // Supergroup objects contain an `is_channel` flag.
        final isChannel = type?.boolean('is_channel') ?? false;
        return isChannel ? _channel : _group;
      default:
        // Fallback to private.
        return _private;
    }
  }

  /// Returns true if the chat is effectively muted (considering use_default_mute_for).
  bool isMuted(Map<String, dynamic> chat) {
    final settings = chat.obj('notification_settings');
    final useDefault = settings?.boolean('use_default_mute_for') ?? false;
    final muteFor = useDefault
        ? _scopeMuteFor(_scopeForChat(chat))
        : (settings?.integer('mute_for') ?? 0);
    return muteFor > 0;
  }
}