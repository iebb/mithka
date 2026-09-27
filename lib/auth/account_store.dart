//
//  account_store.dart
//
//  UI-facing coordinator for multi-account: exposes the configured accounts
//  (with each one's identity for display), the active slot, and actions to
//  switch or add an account. Port of the Swift `AccountStore`.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/custom_emoji.dart';
import '../chat/emoji_store.dart';
import '../notifications/notification_preferences.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'account_backup_service.dart';
import 'auth_manager.dart';

/// Runs work that happens after a Bot API account has already been committed.
///
/// Cleanup and presentation refresh failures must not be surfaced as a failed
/// token login: by this point the account is saved, active, and usable.
@visibleForTesting
Future<void> guardBotAccountPostAddStep(
  FutureOr<void> Function() operation,
) async {
  try {
    await operation();
  } catch (error) {
    // Only the type is safe to report. Platform/file errors may contain local
    // paths, while HTTP errors can contain a credential-bearing request URI.
    debugPrint('Bot account post-add step failed: ${error.runtimeType}');
  }
}

class AccountSummary {
  AccountSummary({
    required this.slot,
    required this.userId,
    required this.name,
    required this.phone,
    this.avatarPath,
    this.emojiStatusId = 0,
    this.isPremium = false,
    this.isBotApi = false,
    this.botApiEndpoint,
  });
  final int slot;
  final int userId;
  final String name;
  final String phone;
  final String? avatarPath; // resolved via this account's OWN TDLib client
  final int emojiStatusId;

  /// Telegram Premium, from getMe. Cached with the rest so Premium-only
  /// entries (Business, the emoji status button) are right from the first
  /// frame instead of appearing once the account answers.
  final bool isPremium;
  final bool isBotApi;
  final Uri? botApiEndpoint;

  AccountSummary copyWith({String? avatarPath}) => AccountSummary(
    slot: slot,
    userId: userId,
    name: name,
    phone: phone,
    avatarPath: avatarPath ?? this.avatarPath,
    emojiStatusId: emojiStatusId,
    isPremium: isPremium,
    isBotApi: isBotApi,
    botApiEndpoint: botApiEndpoint,
  );

  Map<String, Object?> toJson() => {
    'slot': slot,
    'userId': userId,
    'name': name,
    'phone': phone,
    'avatarPath': avatarPath,
    'emojiStatusId': emojiStatusId,
    'isPremium': isPremium,
    'isBotApi': isBotApi,
    'botApiEndpoint': botApiEndpoint?.toString(),
  };

  static AccountSummary? fromJson(Object? json) {
    if (json is! Map) return null;
    final slot = json['slot'];
    final userId = json['userId'];
    final name = json['name'];
    if (slot is! int || userId is! int || name is! String || name.isEmpty) {
      return null;
    }
    final endpoint = json['botApiEndpoint'];
    final avatarPath = json['avatarPath'];
    final phone = json['phone'];
    final statusId = json['emojiStatusId'];
    return AccountSummary(
      slot: slot,
      userId: userId,
      name: name,
      phone: phone is String ? phone : '',
      avatarPath: avatarPath is String ? avatarPath : null,
      emojiStatusId: statusId is int ? statusId : 0,
      isPremium: json['isPremium'] == true,
      isBotApi: json['isBotApi'] == true,
      botApiEndpoint: endpoint is String ? Uri.tryParse(endpoint) : null,
    );
  }
}

/// What one slot's getMe said about the cached summary for that slot.
sealed class _SlotIdentity {
  const _SlotIdentity();
}

/// The slot answered: this is its identity now.
final class _SlotResolved extends _SlotIdentity {
  const _SlotResolved(this.summary, this.avatarFileId);
  final AccountSummary summary;
  final int? avatarFileId;
}

/// The slot is signed out or has no usable identity.
final class _SlotGone extends _SlotIdentity {
  const _SlotGone();
}

/// The slot could not be asked (no client yet, a transient error); keep
/// whatever was cached rather than blanking the account.
final class _SlotUnknown extends _SlotIdentity {
  const _SlotUnknown();
}

class AccountStore extends ChangeNotifier {
  AccountStore(SharedPreferences prefs)
    : _prefs = prefs,
      _activeSlot = prefs.getInt('drachma.activeSlot') ?? 0,
      _summaries = _readCachedSummaries(prefs) {
    // The cached identities let the first frame show the right name and
    // avatar. Without them the window starts as "Mithka", then remounts when
    // getMe lands, because its identity key changes from no user to a user.
    _selfIds.addAll(_summaries.map((summary) => summary.userId));
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
          unawaited(refresh());
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
  static const _summariesKey = 'drachma.accountSummaries';

  static List<AccountSummary> _readCachedSummaries(SharedPreferences prefs) {
    final raw = prefs.getString(_summariesKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(AccountSummary.fromJson)
          .whereType<AccountSummary>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _writeCachedSummaries() {
    unawaited(
      _prefs.setString(
        _summariesKey,
        jsonEncode([for (final summary in _summaries) summary.toJson()]),
      ),
    );
  }

  final SharedPreferences _prefs;
  int _activeSlot;
  List<AccountSummary> _summaries;
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
  bool get activeIsBotApi => TdClient.shared.isBotApiSlot(_activeSlot);

  /// Whether the active account has Telegram Premium, as last seen.
  bool get activeIsPremium {
    for (final summary in _summaries) {
      if (summary.slot == _activeSlot) return summary.isPremium;
    }
    return false;
  }

  int? get activeUserId {
    for (final summary in _summaries) {
      if (summary.slot == _activeSlot) return summary.userId;
    }
    return null;
  }

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
    await AccountBackupService.shared.clearPendingLoginConsent(slot: pending);
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
  ///
  /// The active account goes first and every slot is published as soon as
  /// it resolves, so a slow secondary account (or a profile photo download)
  /// never holds back the name in the title bar.
  Future<void> refresh() async {
    _activeSlot = TdClient.shared.activeSlot;
    final slots = TdClient.shared.configuredSlots;
    final ordered = [
      if (slots.contains(_activeSlot)) _activeSlot,
      ...slots.where((slot) => slot != _activeSlot),
    ];
    final resolved = <int, AccountSummary?>{};

    void publish() {
      final cached = {for (final summary in _summaries) summary.slot: summary};
      _summaries = [
        for (final slot in slots)
          if (resolved.containsKey(slot)) ?resolved[slot] else ?cached[slot],
      ];
      // Saved as each slot resolves: a secondary account that never answers
      // must not keep the active one out of the next launch's cache.
      _writeCachedSummaries();
      notifyListeners();
    }

    for (final slot in ordered) {
      switch (await _identityForSlot(slot)) {
        case _SlotResolved(:final summary, :final avatarFileId):
          resolved[slot] = summary;
          publish();
          final avatarPath = await _downloadAvatar(slot, avatarFileId);
          if (avatarPath != null && avatarPath != summary.avatarPath) {
            resolved[slot] = summary.copyWith(avatarPath: avatarPath);
            publish();
          }
        case _SlotGone():
          resolved[slot] = null;
          publish();
        case _SlotUnknown():
          break;
      }
    }
    publish();
  }

  Future<_SlotIdentity> _identityForSlot(int slot) async {
    final cid = TdClient.shared.clientId(slot);
    if (cid == null) return const _SlotUnknown();
    Map<String, dynamic> me;
    try {
      me = await TdClient.shared.queryTo({'@type': 'getMe'}, cid);
    } on TdError catch (error) {
      return error.code == 401 ? const _SlotGone() : const _SlotUnknown();
    } catch (_) {
      return const _SlotUnknown();
    }
    final selfId = me.int64('id');
    if (selfId != null) {
      _selfIds.add(selfId);
      // The pending add has finished logging in — it's a real account now.
      if (slot == _pendingSlot) {
        _pendingSlot = null;
        _persistPending();
      }
    }
    final name = TDParse.userName(me);
    if (selfId == null || name.isEmpty) return const _SlotGone();
    final botApiAccount = TdClient.shared.botApiAccount(slot);
    final phone = botApiAccount == null
        ? TDParse.formatPhone(me.str('phone_number'))
        : [
            if (botApiAccount.username.isNotEmpty) '@${botApiAccount.username}',
            botApiAccount.endpoint.host,
          ].join(' · ');
    // Until the photo is on disk, keep the one cached for this same user.
    String? cachedAvatar;
    for (final summary in _summaries) {
      if (summary.slot == slot && summary.userId == selfId) {
        cachedAvatar = summary.avatarPath;
      }
    }
    final avatarFileId = me.obj('profile_photo')?.obj('small')?.integer('id');
    return _SlotResolved(
      AccountSummary(
        slot: slot,
        userId: selfId,
        name: name,
        phone: phone,
        avatarPath: avatarFileId == null ? null : cachedAvatar,
        emojiStatusId: TDParse.emojiStatusCustomEmojiId(me.obj('emoji_status')),
        isPremium: me.boolean('is_premium') ?? false,
        isBotApi: botApiAccount != null,
        botApiEndpoint: botApiAccount?.endpoint,
      ),
      avatarFileId,
    );
  }

  Future<String?> _downloadAvatar(int slot, int? fileId) async {
    final cid = TdClient.shared.clientId(slot);
    if (cid == null || fileId == null) return null;
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
      return path == null || path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
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

  /// Adds a Telegram Bot API account and switches to it after token validation.
  /// A transient native login slot is discarded; an existing signed-in user
  /// account remains configured alongside the bot.
  Future<int> addBotAccount({
    required String token,
    required String endpoint,
    required AuthManager auth,
  }) async {
    final sourceSlot = _activeSlot;
    final sourceWasReady = await _slotIsReady(sourceSlot);
    final slot = await TdClient.shared.addBotApiAccount(
      token: token,
      endpoint: endpoint,
    );
    _activeAccountChanged();
    _activeSlot = slot;
    await guardBotAccountPostAddStep(() async {
      if (!sourceWasReady &&
          sourceSlot != slot &&
          !TdClient.shared.isBotApiSlot(sourceSlot) &&
          TdClient.shared.configuredSlots.contains(sourceSlot)) {
        if (sourceSlot == _pendingSlot) {
          _pendingSlot = null;
          _persistPending();
        }
        TdClient.shared.removeSlot(sourceSlot);
        await TdClient.shared.deleteSlotData(sourceSlot);
      }
    });
    notifyListeners();
    auth.reloadAuthState();
    await guardBotAccountPostAddStep(refresh);
    return slot;
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
    unawaited(
      AccountBackupService.shared.clearPendingLoginConsent(slot: pending),
    );
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
    final userId = await _userIdForSlot(slot);
    if (slots.length <= 1) {
      if (slot == _pendingSlot) {
        _pendingSlot = null;
        _persistPending();
      }
      _activeSlot = TdClient.shared.replaceActiveWithFreshLoginSlot();
      _activeAccountChanged();
      await TdClient.shared.deleteSlotData(slot);
      if (userId != null) {
        await AccountBackupService.shared.deleteAccountId('$userId');
        await NotificationPreferences.shared.removeAccount(userId);
      }
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
    if (userId != null) {
      await AccountBackupService.shared.deleteAccountId('$userId');
      await NotificationPreferences.shared.removeAccount(userId);
    }
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

    if (oldClientId != null && !TdClient.shared.isBotApiSlot(slot)) {
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
      await NotificationPreferences.shared.removeAccount(userId);
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
