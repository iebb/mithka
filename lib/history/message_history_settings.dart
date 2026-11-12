//
//  message_history_settings.dart
//
//  Runtime switches for the kept-message mirror (Telegram API Terms §1.4
//  feature, only compiled into opted-in self-builds). Everything defaults
//  to OFF: a fresh build records nothing until the user opts in, matching
//  the reference kept-message clients' save switches, which
//  also ship disabled.
//
//  The recording switches gate the STORE's write paths; the render switch
//  gates the IN-CHAT ghost bubbles. Turning a recording switch off does not
//  delete what was recorded — the data stays browsable in the history
//  viewer until explicitly cleared.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';

/// How a ghost bubble's deleted badge renders.
enum GhostBadgeStyle {
  /// Trash icon only — compact, the default.
  icon,

  /// Localized "已删除" text only.
  text,

  /// Icon plus text.
  both;

  String get storageValue => name;

  static GhostBadgeStyle fromPrefs(String? stored) => switch (stored) {
    'text' => GhostBadgeStyle.text,
    'both' => GhostBadgeStyle.both,
    _ => GhostBadgeStyle.icon,
  };
}

/// Runtime configuration of the kept-message mirror.
class MessageHistorySettings extends ChangeNotifier {
  MessageHistorySettings._();

  static final MessageHistorySettings shared = MessageHistorySettings._();

  static bool get isAvailable => allowTelegramTosViolations;

  static const _enableAllKey = 'message_history.enable_all';
  static const _recordDeletedKey = 'message_history.record_deleted';
  static const _recordEditsKey = 'message_history.record_edits';
  static const _recordPrivateKey = 'message_history.record_private';
  static const _recordGroupsKey = 'message_history.record_groups';
  static const _recordChannelsKey = 'message_history.record_channels';
  static const _recordBotsKey = 'message_history.record_bots';
  static const _snapshotPrivateKey = 'message_history.snapshot_private';
  static const _snapshotGroupsKey = 'message_history.snapshot_groups';
  static const _snapshotChannelsKey = 'message_history.snapshot_channels';
  static const _renderGhostsKey = 'message_history.render_ghosts';
  static const _badgeStyleKey = 'message_history.badge_style';

  bool _enableAll = false;
  bool _recordDeleted = false;
  bool _recordEdits = false;
  // Per-type switches default ON — the master switch and the deleted-record
  // switch remain the primary opt-ins, and the type dims only narrow them
  // Bot chats are the exception: recording service
  // dialogs is an explicit opt-in.
  bool _recordPrivate = true;
  bool _recordGroups = true;
  bool _recordChannels = true;
  bool _recordBots = false;
  bool _snapshotPrivate = false;
  bool _snapshotGroups = false;
  bool _snapshotChannels = false;
  bool _renderGhosts = false;
  GhostBadgeStyle _badgeStyle = GhostBadgeStyle.icon;

  /// Master switch: OFF pauses all recording (deleted, edits and media
  /// snapshots) without touching what was already kept — the
  /// pause semantics. Still-off sub-switches stay off
  /// when it turns back on.
  bool get enableAll => _enableAll && isAvailable;

  bool get recordDeleted => _recordDeleted && enableAll;
  bool get recordEdits => _recordEdits && enableAll;

  /// Per conversation-type recording (private /
  /// groups / channels). A type that is off records nothing for its
  /// chats — neither text nor media snapshots.
  bool get recordPrivate => _recordPrivate && recordDeleted;
  bool get recordGroups => _recordGroups && recordDeleted;
  bool get recordChannels => _recordChannels && recordDeleted;

  /// Bot chats record only when both the private-type switch and this one
  /// are on — a bot dialog is private, but recording service messages is a
  /// separate opt-in.
  bool get recordBots => _recordBots && recordPrivate;

  /// How a ghost bubble's deleted badge renders: the trash icon alone, the
  /// localized "已删除" text alone, or both.
  GhostBadgeStyle get badgeStyle =>
      isAvailable ? _badgeStyle : GhostBadgeStyle.icon;

  /// Media snapshots per conversation class. The classification comes from
  /// the TDLib chat type at record time; a chat whose type is unknown keeps
  /// the previous snapshot state (no new snapshots).
  bool get snapshotPrivate => _snapshotPrivate && isAvailable;
  bool get snapshotGroups => _snapshotGroups && isAvailable;
  bool get snapshotChannels => _snapshotChannels && isAvailable;

  /// Deleted mirrored messages render in-place in the chat transcript as
  /// translucent ghost bubbles. Display-only: independent of the master
  /// recording switch, so turning recording off never hides the ghosts of
  /// what was already kept.
  bool get renderGhosts => _renderGhosts && isAvailable;

  SharedPreferences? _prefs;

  /// Called from the app bootstrap; a no-op in builds without the feature.
  void initialize(SharedPreferences prefs) {
    if (!isAvailable) return;
    _prefs = prefs;
    _enableAll = prefs.getBool(_enableAllKey) ?? false;
    _recordDeleted = prefs.getBool(_recordDeletedKey) ?? false;
    _recordEdits = prefs.getBool(_recordEditsKey) ?? false;
    _recordPrivate = prefs.getBool(_recordPrivateKey) ?? true;
    _recordGroups = prefs.getBool(_recordGroupsKey) ?? true;
    _recordChannels = prefs.getBool(_recordChannelsKey) ?? true;
    _recordBots = prefs.getBool(_recordBotsKey) ?? false;
    _snapshotPrivate = prefs.getBool(_snapshotPrivateKey) ?? false;
    _snapshotGroups = prefs.getBool(_snapshotGroupsKey) ?? false;
    _snapshotChannels = prefs.getBool(_snapshotChannelsKey) ?? false;
    _renderGhosts = prefs.getBool(_renderGhostsKey) ?? false;
    _badgeStyle = GhostBadgeStyle.fromPrefs(prefs.getString(_badgeStyleKey));
    notifyListeners();
  }

  void setEnableAll(bool value) {
    if (!isAvailable || _enableAll == value) return;
    _enableAll = value;
    _prefs?.setBool(_enableAllKey, value);
    notifyListeners();
  }

  void setRecordDeleted(bool value) {
    if (!isAvailable || _recordDeleted == value) return;
    _recordDeleted = value;
    _prefs?.setBool(_recordDeletedKey, value);
    notifyListeners();
  }

  void setRecordEdits(bool value) {
    if (!isAvailable || _recordEdits == value) return;
    _recordEdits = value;
    _prefs?.setBool(_recordEditsKey, value);
    notifyListeners();
  }

  void setRecordPrivate(bool value) {
    if (!isAvailable || _recordPrivate == value) return;
    _recordPrivate = value;
    _prefs?.setBool(_recordPrivateKey, value);
    notifyListeners();
  }

  void setRecordGroups(bool value) {
    if (!isAvailable || _recordGroups == value) return;
    _recordGroups = value;
    _prefs?.setBool(_recordGroupsKey, value);
    notifyListeners();
  }

  void setRecordChannels(bool value) {
    if (!isAvailable || _recordChannels == value) return;
    _recordChannels = value;
    _prefs?.setBool(_recordChannelsKey, value);
    notifyListeners();
  }

  void setRecordBots(bool value) {
    if (!isAvailable || _recordBots == value) return;
    _recordBots = value;
    _prefs?.setBool(_recordBotsKey, value);
    notifyListeners();
  }

  void setBadgeStyle(GhostBadgeStyle value) {
    if (!isAvailable || _badgeStyle == value) return;
    _badgeStyle = value;
    _prefs?.setString(_badgeStyleKey, value.storageValue);
    notifyListeners();
  }

  void setSnapshotPrivate(bool value) {
    if (!isAvailable || _snapshotPrivate == value) return;
    _snapshotPrivate = value;
    _prefs?.setBool(_snapshotPrivateKey, value);
    notifyListeners();
  }

  void setSnapshotGroups(bool value) {
    if (!isAvailable || _snapshotGroups == value) return;
    _snapshotGroups = value;
    _prefs?.setBool(_snapshotGroupsKey, value);
    notifyListeners();
  }

  void setSnapshotChannels(bool value) {
    if (!isAvailable || _snapshotChannels == value) return;
    _snapshotChannels = value;
    _prefs?.setBool(_snapshotChannelsKey, value);
    notifyListeners();
  }

  void setRenderGhosts(bool value) {
    if (!isAvailable || _renderGhosts == value) return;
    _renderGhosts = value;
    _prefs?.setBool(_renderGhostsKey, value);
    notifyListeners();
  }
}
