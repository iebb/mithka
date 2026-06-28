//
//  account_store.dart
//
//  UI-facing coordinator for multi-account: exposes the configured accounts
//  (with each one's identity for display), the active slot, and actions to
//  switch or add an account. Port of the Swift `AccountStore`.
//

import 'dart:async';

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
    // its half-created slot can still be cleaned up.
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
  // returns to [_returnSlot] rather than leaving a half-created account entry.
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
      if (me == null || selfId == null || parsedName.isEmpty) continue;
      final name = parsedName;
      final phone = TDParse.formatPhone(me.str('phone_number'));

      String? avatarPath;
      final fileId = me.obj('profile_photo')?.obj('small')?.integer('id');
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
  /// from and discards the transient slot. No-op if there's no pending add.
  void cancelAddAccount(AuthManager auth) {
    final pending = _pendingSlot;
    if (pending == null) return;
    _pendingSlot = null;
    _persistPending();
    final slots = TdClient.shared.configuredSlots;
    final target = slots.contains(_returnSlot) && _returnSlot != pending
        ? _returnSlot
        : slots.firstWhere((s) => s != pending, orElse: () => pending);
    if (target == pending) {
      _activeSlot = TdClient.shared.replaceActiveWithFreshLoginSlot();
    } else {
      TdClient.shared.setActive(target); // must point away before removing
      _activeSlot = target;
      TdClient.shared.removeSlot(pending);
    }
    notifyListeners();
    auth.reloadAuthState();
    refresh();
  }

  /// Removes an account slot from the switcher. If this is the last slot,
  /// replace it with a clean login slot so the app lands on initial login.
  void removeAccount(int slot, AuthManager auth) {
    final slots = TdClient.shared.configuredSlots;
    if (!slots.contains(slot)) return;
    if (slots.length <= 1) {
      if (slot == _pendingSlot) {
        _pendingSlot = null;
        _persistPending();
      }
      _activeSlot = TdClient.shared.replaceActiveWithFreshLoginSlot();
      notifyListeners();
      auth.reloadAuthState();
      refresh();
      return;
    }
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

  /// Logs out the active account. When another logged-in account exists, switch
  /// to it first and remove the logged-out slot so the UI does not land on a
  /// stale account row.
  Future<void> logOutActive(AuthManager auth) async {
    final slot = _activeSlot;
    final slots = TdClient.shared.configuredSlots;
    final target = await _nextReadySlot(after: slot);
    if (target == null) {
      final oldClientId = TdClient.shared.clientId(slot);
      if (oldClientId != null) {
        try {
          await TdClient.shared
              .queryTo({'@type': 'logOut'}, oldClientId)
              .timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
      if (slot == _pendingSlot) {
        _pendingSlot = null;
        _persistPending();
      }
      _activeSlot = TdClient.shared.replaceActiveWithFreshLoginSlot();
      notifyListeners();
      auth.reloadAuthState();
      await refresh();
      return;
    }

    final oldClientId = TdClient.shared.clientId(slot);
    TdClient.shared.setActive(target);
    _activeSlot = target;
    if (slot == _pendingSlot) {
      _pendingSlot = null;
      _persistPending();
    }
    notifyListeners();
    auth.reloadAuthState();

    if (oldClientId != null) {
      try {
        await TdClient.shared
            .queryTo({'@type': 'logOut'}, oldClientId)
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }

    if (slots.length > 1 && TdClient.shared.configuredSlots.contains(slot)) {
      TdClient.shared.removeSlot(slot);
    }
    await refresh();
  }

  Future<int?> _nextReadySlot({required int after}) async {
    final slots = TdClient.shared.configuredSlots;
    if (slots.length <= 1) return null;
    final index = slots.indexOf(after);
    final candidates = <int>[
      if (index >= 0) ...slots.skip(index + 1),
      if (index >= 0) ...slots.take(index),
      if (index < 0) ...slots,
    ].where((slot) => slot != after);
    for (final slot in candidates) {
      if (await _slotIsReady(slot)) return slot;
    }
    return null;
  }

  Future<bool> _slotIsReady(int slot) async {
    final cid = TdClient.shared.clientId(slot);
    if (cid == null) return false;
    try {
      final state = await TdClient.shared
          .queryTo({'@type': 'getAuthorizationState'}, cid)
          .timeout(const Duration(seconds: 2));
      if (state.type == 'authorizationStateReady') return true;
    } catch (_) {}
    try {
      await TdClient.shared
          .queryTo({'@type': 'getMe'}, cid)
          .timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {}
    return false;
  }
}
