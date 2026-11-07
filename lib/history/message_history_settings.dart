//
//  message_history_settings.dart
//
//  Runtime switches for the kept-message mirror (Telegram API Terms §1.4
//  feature, only compiled into opted-in self-builds). Everything defaults
//  to OFF: a fresh build records nothing until the user opts in, matching
//  exteraless's EnableSaveDeletedMessages / EnableSaveEditsHistory which
//  also ship disabled.
//
//  The recording switches gate the STORE's write paths; the render switch
//  gates the IN-CHAT ghost bubbles. Turning a recording switch off does not
//  delete what was recorded — the data stays browsable in the history
//  viewer until explicitly cleared, exactly like exteraless.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';

/// Runtime configuration of the kept-message mirror.
class MessageHistorySettings extends ChangeNotifier {
  MessageHistorySettings._();

  static final MessageHistorySettings shared = MessageHistorySettings._();

  static bool get isAvailable => allowTelegramTosViolations;

  static const _recordDeletedKey = 'message_history.record_deleted';
  static const _recordEditsKey = 'message_history.record_edits';
  static const _snapshotPrivateKey = 'message_history.snapshot_private';
  static const _snapshotGroupsKey = 'message_history.snapshot_groups';
  static const _snapshotChannelsKey = 'message_history.snapshot_channels';
  static const _renderGhostsKey = 'message_history.render_ghosts';

  bool _recordDeleted = false;
  bool _recordEdits = false;
  bool _snapshotPrivate = false;
  bool _snapshotGroups = false;
  bool _snapshotChannels = false;
  bool _renderGhosts = false;

  bool get recordDeleted => _recordDeleted && isAvailable;
  bool get recordEdits => _recordEdits && isAvailable;

  /// Media snapshots per conversation class. The classification comes from
  /// the TDLib chat type at record time; a chat whose type is unknown keeps
  /// the previous snapshot state (no new snapshots).
  bool get snapshotPrivate => _snapshotPrivate && isAvailable;
  bool get snapshotGroups => _snapshotGroups && isAvailable;
  bool get snapshotChannels => _snapshotChannels && isAvailable;

  /// Deleted mirrored messages render in-place in the chat transcript as
  /// translucent ghost bubbles.
  bool get renderGhosts => _renderGhosts && isAvailable;

  SharedPreferences? _prefs;

  /// Called from the app bootstrap; a no-op in builds without the feature.
  void initialize(SharedPreferences prefs) {
    if (!isAvailable) return;
    _prefs = prefs;
    _recordDeleted = prefs.getBool(_recordDeletedKey) ?? false;
    _recordEdits = prefs.getBool(_recordEditsKey) ?? false;
    _snapshotPrivate = prefs.getBool(_snapshotPrivateKey) ?? false;
    _snapshotGroups = prefs.getBool(_snapshotGroupsKey) ?? false;
    _snapshotChannels = prefs.getBool(_snapshotChannelsKey) ?? false;
    _renderGhosts = prefs.getBool(_renderGhostsKey) ?? false;
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
