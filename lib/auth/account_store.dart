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

import '../chat/custom_emoji.dart';
import '../chat/emoji_store.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'account_backup_service.dart';
import 'auth_manager.dart';

class AccountSummary {
  AccountSummary({
    required this.slot,
    required this.userId,
    required this.name,
    required this.phone,
    this.avatarPath,
  });
  final int slot;
  final int userId;
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
      if (u.type == 'updateAuthorizationState') {
        final state = u.obj('authorization_state');
        if (state?.type == 'authorizationStateReady') {
          unawaited(_removePendingSessionReplacementSource());
        }
        return;
      }
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
  int? _pendingSessionReplacementSourceSlot;
  int? _pendingSessionReplacementTargetSlot;
  bool _removingSessionReplacementSource = false;

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

  void _activeAccountChanged() {
    CustomEmojiCenter.shared.reset();
    EmojiStore.shared.reset();
  }

  Future<void> _removePendingSessionReplacementSource() async {
    final source = _pendingSessionReplacementSourceSlot;
    if (source == null || _removingSessionReplacementSource) return;
    if (source == _activeSlot) return;
    if (!TdClient.shared.configuredSlots.contains(source)) {
      _pendingSessionReplacementSourceSlot = null;
      _pendingSessionReplacementTargetSlot = null;
      return;
    }
    _removingSessionReplacementSource = true;
    try {
      TdClient.shared.removeSlot(source);
      await TdClient.shared.deleteSlotData(source);
      _pendingSessionReplacementSourceSlot = null;
      _pendingSessionReplacementTargetSlot = null;
      await refresh();
    } finally {
      _removingSessionReplacementSource = false;
    }
  }

  /// True while an add-account login is in progress on the active slot.
  bool get hasPendingAdd => _pendingSlot != null && _pendingSlot == _activeSlot;

  /// True while the active account slot is the replacement session being
  /// created from a restored session. QR confirmation is handled internally by
  /// the restored source slot, so the login UI should only show follow-up auth
  /// steps such as 2FA/code entry.
  bool get isActiveSessionReplacementPending =>
      _pendingSessionReplacementSourceSlot != null &&
      _pendingSessionReplacementTargetSlot == _activeSlot;

  /// Display name of the account we'd return to if the pending add is aborted.
  String? get returnAccountName {
    if (!hasPendingAdd) return null;
    for (final s in _summaries) {
      if (s.slot == _returnSlot) return s.name;
    }
    return null;
  }

  /// If the app was killed while adding an account, do not strand the next
  /// launch on that empty login slot when the original account is still ready.
  Future<void> recoverPendingAddOnStartup(AuthManager auth) async {
    final pending = _pendingSlot;
    if (pending == null) return;

    for (var i = 0; i < 25; i += 1) {
      if (TdClient.shared.configuredSlots.contains(pending)) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (_pendingSlot != pending ||
        !TdClient.shared.configuredSlots.contains(pending)) {
      return;
    }
    if (TdClient.shared.activeSlot != pending) return;

    final preferredReturn =
        TdClient.shared.configuredSlots.contains(_returnSlot) &&
            _returnSlot != pending &&
            await _slotIsReady(_returnSlot)
        ? _returnSlot
        : null;
    final target = preferredReturn ?? await _nextReadySlot(after: pending);
    if (target == null || target == pending) return;

    _pendingSlot = null;
    _persistPending();
    TdClient.shared.setActive(target);
    _activeAccountChanged();
    _activeSlot = target;
    TdClient.shared.removeSlot(pending);
    await TdClient.shared.deleteSlotData(pending);
    notifyListeners();
    auth.reloadAuthState();
    await refresh();
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
          userId: selfId,
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
    _activeAccountChanged();
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
    _activeAccountChanged();
    _activeSlot = slot;
    notifyListeners();
    auth.reloadAuthState();
    refresh();
  }

  Future<TdFreshSessionResult> createFreshSessionFromRestoredSlot(
    int sourceSlot,
    AuthManager auth,
  ) async {
    final result = await TdClient.shared.createFreshSessionFromSlot(sourceSlot);
    _activeAccountChanged();
    _activeSlot = result.slot;
    _pendingSessionReplacementTargetSlot = result.slot;
    if (result.needsInteractiveLogin) {
      _pendingSessionReplacementSourceSlot = sourceSlot;
    } else {
      _pendingSessionReplacementSourceSlot = sourceSlot;
      await _removePendingSessionReplacementSource();
    }
    notifyListeners();
    auth.reloadAuthState();
    await refresh();
    return result;
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
      _activeAccountChanged();
    } else {
      TdClient.shared.setActive(target); // must point away before removing
      _activeAccountChanged();
      _activeSlot = target;
      TdClient.shared.removeSlot(pending);
    }
    notifyListeners();
    auth.reloadAuthState();
    refresh();
  }

  /// Removes an account slot from the switcher. If this is the last slot,
  /// replace it with a clean login slot so the app lands on initial login.
  Future<void> removeAccount(int slot, AuthManager auth) async {
    final slots = TdClient.shared.configuredSlots;
    if (!slots.contains(slot)) return;
    if (slots.length <= 1) {
      if (slot == _pendingSlot) {
        _pendingSlot = null;
        _persistPending();
      }
      _activeSlot = TdClient.shared.replaceActiveWithFreshLoginSlot();
      _activeAccountChanged();
      await TdClient.shared.deleteSlotData(slot);
      notifyListeners();
      auth.reloadAuthState();
      await refresh();
      return;
    }
    if (slot == _activeSlot) {
      final target = slots.firstWhere((s) => s != slot);
      TdClient.shared.setActive(target);
      _activeAccountChanged();
      _activeSlot = target;
      auth.reloadAuthState();
    }
    if (slot == _pendingSlot) {
      _pendingSlot = null;
      _persistPending();
    }
    TdClient.shared.removeSlot(slot);
    await TdClient.shared.deleteSlotData(slot);
    notifyListeners();
    await refresh();
  }

  /// Logs out the active account. When another logged-in account exists, switch
  /// to it first and remove the logged-out slot so the UI does not land on a
  /// stale account row.
  Future<void> logOutActive(AuthManager auth) =>
      logOutAccount(_activeSlot, auth);

  /// Revokes the Telegram session for [slot], then removes local data and the
  /// matching Keychain account backup.
  Future<void> logOutAccount(int slot, AuthManager auth) async {
    final userId = await _userIdForSlot(slot);
    final slots = TdClient.shared.configuredSlots;
    if (!slots.contains(slot)) return;
    final oldClientId = TdClient.shared.clientId(slot);
    final isActiveSlot = slot == _activeSlot;
    final target = isActiveSlot ? await _nextReadySlot(after: slot) : null;

    if (isActiveSlot && target != null) {
      TdClient.shared.setActive(target);
      _activeAccountChanged();
      _activeSlot = target;
      if (slot == _pendingSlot) {
        _pendingSlot = null;
        _persistPending();
      }
      notifyListeners();
      auth.reloadAuthState();
    }

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

    if (isActiveSlot && target == null) {
      _activeSlot = TdClient.shared.replaceActiveWithFreshLoginSlot();
      _activeAccountChanged();
      notifyListeners();
      auth.reloadAuthState();
    } else if (TdClient.shared.configuredSlots.contains(slot)) {
      TdClient.shared.removeSlot(slot);
    }
    await TdClient.shared.deleteSlotData(slot);
    if (userId != null) {
      await AccountBackupService.shared.deleteAccountId('$userId');
    }
    await refresh();
  }

  Future<int?> _userIdForSlot(int slot) async {
    for (final summary in _summaries) {
      if (summary.slot == slot) return summary.userId;
    }
    final cid = TdClient.shared.clientId(slot);
    if (cid == null) return null;
    try {
      final me = await TdClient.shared
          .queryTo({'@type': 'getMe'}, cid)
          .timeout(const Duration(seconds: 2));
      return me.int64('id');
    } catch (_) {
      return null;
    }
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
