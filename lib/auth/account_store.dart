//
//  account_store.dart
//
//  UI-facing coordinator for multi-account: exposes the configured accounts
//  (with each one's identity for display), the active slot, and actions to
//  switch or add an account. Port of the Swift `AccountStore`.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'auth_manager.dart';

class AccountSummary {
  AccountSummary({
    required this.slot,
    required this.name,
    required this.phone,
    this.avatarPath,
  });
  final int slot;
  final String name;
  final String phone;
  final String? avatarPath; // resolved via this account's OWN TDLib client
}

class AccountStore extends ChangeNotifier {
  AccountStore(SharedPreferences prefs)
    : _prefs = prefs,
      _activeSlot = prefs.getInt('drachma.activeSlot') ?? 0 {
    // Restore an add-account that was in progress when the app was killed, so
    // its half-created slot can still be cleaned up rather than lingering as
    // "未登录".
    _pendingSlot = prefs.getInt(_pendingKey);
    _returnSlot = prefs.getInt(_returnKey) ?? 0;
    // Refresh the switcher when one of our own accounts changes (e.g. after a
    // name edit) — TDLib emits updateUser for us. Filtered to known self-ids so
    // it doesn't fire for every contact seen in chats.
    TdClient.shared.subscribe().listen((u) {
      if (u.type != 'updateUser') return;
      final uid = u.obj('user')?.int64('id');
      if (uid != null && _selfIds.contains(uid)) refresh();
    });
  }

  static const _pendingKey = 'drachma.pendingSlot';
  static const _returnKey = 'drachma.pendingReturnSlot';

  final SharedPreferences _prefs;
  int _activeSlot;
  List<AccountSummary> _summaries = [];
  final Set<int> _selfIds = {}; // our own user ids across accounts

  // An in-progress "add account": the freshly-created slot whose login has not
  // completed, and the slot we should fall back to if the user aborts. While
  // this is set, backing out of the login flow discards [_pendingSlot] and
  // returns to [_returnSlot] rather than leaving a half-created "未登录" entry.
  // Persisted so it survives an app kill mid-login.
  int? _pendingSlot;
  int _returnSlot = 0;

  void _persistPending() {
    final p = _pendingSlot;
    if (p == null) {
      _prefs.remove(_pendingKey);
      _prefs.remove(_returnKey);
    } else {
      _prefs.setInt(_pendingKey, p);
      _prefs.setInt(_returnKey, _returnSlot);
    }
  }

  int get activeSlot => _activeSlot;
  List<AccountSummary> get summaries => _summaries;

  /// True while an add-account login is in progress on the active slot.
  bool get hasPendingAdd => _pendingSlot != null && _pendingSlot == _activeSlot;

  /// Display name of the account we'd return to if the pending add is aborted.
  String? get returnAccountName {
    if (!hasPendingAdd) return null;
    for (final s in _summaries) {
      if (s.slot == _returnSlot) return s.name;
    }
    return null;
  }

  /// Re-reads each account's identity (getMe per client) for the switcher.
  Future<void> refresh() async {
    _activeSlot = TdClient.shared.activeSlot;
    final result = <AccountSummary>[];
    for (final slot in TdClient.shared.configuredSlots) {
      final cid = TdClient.shared.clientId(slot);
      if (cid == null) continue;
      Map<String, dynamic>? me;
      try {
        me = await TdClient.shared.queryTo({'@type': 'getMe'}, cid);
      } catch (_) {}
      final selfId = me?.int64('id');
      if (selfId != null) {
        _selfIds.add(selfId);
        // The pending add has finished logging in — it's a real account now.
        if (slot == _pendingSlot) {
          _pendingSlot = null;
          _persistPending();
        }
      }
      final parsedName = me != null ? TDParse.userName(me) : '';
      final name = parsedName.isEmpty
          ? (slot == _activeSlot ? '未登录账号' : '未登录')
          : parsedName;
      final phone = TDParse.formatPhone(me?.str('phone_number'));

      String? avatarPath;
      final fileId = me?.obj('profile_photo')?.obj('small')?.integer('id');
      if (fileId != null) {
        try {
          final res = await TdClient.shared.queryTo({
            '@type': 'downloadFile',
            'file_id': fileId,
            'priority': 1,
            'offset': 0,
            'limit': 0,
            'synchronous': true,
          }, cid);
          final path = res.obj('local')?.str('path');
          if (path != null && path.isNotEmpty) avatarPath = path;
        } catch (_) {}
      }
      result.add(
        AccountSummary(
          slot: slot,
          name: name,
          phone: phone,
          avatarPath: avatarPath,
        ),
      );
    }
    _summaries = result;
    notifyListeners();
  }

  /// Switches to an existing account and re-gates auth on it.
  void switchTo(int slot, AuthManager auth) {
    if (slot == _activeSlot) return;
    TdClient.shared.setActive(slot);
    _activeSlot = slot;
    notifyListeners();
    auth.reloadAuthState();
    refresh();
  }

  /// Creates a fresh account and switches to it (lands on the login flow).
  /// Remembers the current account so an aborted login can return to it.
  void addAccount(AuthManager auth) {
    _returnSlot = _activeSlot;
    final slot = TdClient.shared.addSlot();
    _pendingSlot = slot;
    _persistPending();
    TdClient.shared.setActive(slot);
    _activeSlot = slot;
    notifyListeners();
    auth.reloadAuthState();
    refresh();
  }

  /// Aborts an in-progress "add account": switches back to the account we came
  /// from and discards the transient slot, so no half-created "未登录" entry is
  /// left behind. No-op if there's no pending add.
  void cancelAddAccount(AuthManager auth) {
    final pending = _pendingSlot;
    if (pending == null) return;
    _pendingSlot = null;
    _persistPending();
    final slots = TdClient.shared.configuredSlots;
    final target = slots.contains(_returnSlot) && _returnSlot != pending
        ? _returnSlot
        : slots.firstWhere((s) => s != pending, orElse: () => pending);
    if (target == pending) return; // nothing to fall back to — keep the slot
    TdClient.shared.setActive(target); // must point away before removing
    _activeSlot = target;
    TdClient.shared.removeSlot(pending);
    notifyListeners();
    auth.reloadAuthState();
    refresh();
  }

  /// Removes an account slot from the switcher (e.g. a leftover "未登录" entry
  /// or a no-longer-wanted logged-out account). If the slot is currently active,
  /// switches to another account first. Refuses to remove the only account.
  void removeAccount(int slot, AuthManager auth) {
    final slots = TdClient.shared.configuredSlots;
    if (slots.length <= 1 || !slots.contains(slot)) return;
    if (slot == _activeSlot) {
      final target = slots.firstWhere((s) => s != slot);
      TdClient.shared.setActive(target);
      _activeSlot = target;
      auth.reloadAuthState();
    }
    if (slot == _pendingSlot) {
      _pendingSlot = null;
      _persistPending();
    }
    TdClient.shared.removeSlot(slot);
    notifyListeners();
    refresh();
  }
}
