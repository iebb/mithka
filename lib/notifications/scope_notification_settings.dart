//  scope_notification_settings.dart
//  Cached scope-level notification settings (mute_for) used to compute effective mute state.

import 'package:flutter/foundation.dart';
import 'package:mithka/tdlib/json_helpers.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart' show ChatKind;

/// Cached scope-level notification settings (mute_for) used to compute
/// effective mute state.
///
/// A chat that follows the default (`use_default_mute_for`) carries NO mute
/// state of its own — TDLib zeroes its `mute_for` (DialogNotificationSettings
/// ::fix_mute_until) — so the effective value lives only in the scope
/// settings. Those load asynchronously (a server round trip on first sync),
/// so consumers must treat a snapshot parsed before the cache filled as
/// provisional and re-derive when this notifier fires.
class ScopeNotificationSettings extends ChangeNotifier {
  ScopeNotificationSettings._();
  static final ScopeNotificationSettings shared = ScopeNotificationSettings._();

  static const _private = 'notificationSettingsScopePrivateChats';
  static const _group = 'notificationSettingsScopeGroupChats';
  static const _channel = 'notificationSettingsScopeChannelChats';

  final Map<String, int> _muteFor = {};
  final Map<String, bool> _showPreview = {};
  final Map<String, int> _soundId = {};

  /// Loads mute_for values for all three scopes from TDLib. Runs on every
  /// `authorizationStateReady`, so an account switch re-reads the new account's
  /// scopes instead of keeping the previous account's values.
  Future<void> load() async {
    final client = TdClient.shared;
    var loadedAny = false;
    for (final scope in const [_private, _group, _channel]) {
      try {
        final s = await client.query({
          '@type': 'getScopeNotificationSettings',
          'scope': {'@type': scope},
        });
        _muteFor[scope] = s.integer('mute_for') ?? 0;
        _showPreview[scope] = s.boolean('show_preview') ?? true;
        _soundId[scope] = s.int64('sound_id') ?? -1;
        loadedAny = true;
      } catch (_) {
        // Keep whatever is cached. A failed load must not fabricate values:
        // writing a zero here would flip chats that follow a muted scope to
        // unmuted until the next scope update arrives.
      }
    }
    if (loadedAny) notifyListeners();
  }

  /// Updates the cached mute_for for a scope (called after user changes settings).
  void update(String scope, int muteFor) {
    if (_muteFor[scope] == muteFor) return;
    _muteFor[scope] = muteFor;
    notifyListeners();
  }

  void updateShowPreview(String scope, bool showPreview) {
    if (_showPreview[scope] == showPreview) return;
    _showPreview[scope] = showPreview;
    notifyListeners();
  }

  void updateSoundId(String scope, int soundId) {
    if (_soundId[scope] == soundId) return;
    _soundId[scope] = soundId;
    notifyListeners();
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

  String scopeTagForChat(Map<String, dynamic> chat) => _scopeForChat(chat);

  /// Returns true if the chat is effectively muted (considering use_default_mute_for).
  bool isMuted(Map<String, dynamic> chat) {
    final settings = chat.obj('notification_settings');
    final useDefault = settings?.boolean('use_default_mute_for') ?? false;
    final muteFor = useDefault
        ? getMuteForScope(_scopeForChat(chat))
        : (settings?.integer('mute_for') ?? 0);
    return muteFor > 0;
  }

  bool showPreview(Map<String, dynamic> chat) {
    final settings = chat.obj('notification_settings');
    final useDefault = settings?.boolean('use_default_show_preview') ?? true;
    return useDefault
        ? (_showPreview[_scopeForChat(chat)] ?? true)
        : (settings?.boolean('show_preview') ?? true);
  }

  bool soundEnabled(Map<String, dynamic> chat) {
    final settings = chat.obj('notification_settings');
    final useDefault = settings?.boolean('use_default_sound') ?? true;
    final soundId = useDefault
        ? (_soundId[_scopeForChat(chat)] ?? -1)
        : (settings?.int64('sound_id') ?? -1);
    return soundId != 0;
  }
}
