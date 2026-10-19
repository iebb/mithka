//
//  local_pin_store.dart
//
//  Device-only pins for the chat list: with the unlimited-local-pins setting
//  on, a chat the server would refuse to pin (the server pin cap is reached,
//  or the chat has no position in the list) is pinned on this device only.
//  Nothing is sent to Telegram — the pin is written to the preference store,
//  the row is ordered above every server pin and it renders through the same
//  `ChatSummary.isPinned` flag every other pinned chat uses.
//
//  The setting is off by default and lives entirely in this app's preference
//  store: with it off no preference is read or written and no local pin can
//  take effect, not even from state an earlier run left behind.
//
//  Entries are owned by the account that pinned them. Chat ids are
//  account-scoped, so each entry is keyed by the stable Telegram user id (the
//  view model resolves it from its account) as well as the chat id, and
//  switching accounts cannot expose one account's pins to another.
//
//  Ordering contract, in full: every local pin sorts above every server pin,
//  the most recently pinned local sorts first, and recomputing the orders for
//  the same state produces exactly the same numbers. The band is rebuilt from
//  the entries only — never from the live list — so a refresh cannot shuffle
//  the rows.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One chat kept pinned on this device only.
@immutable
class LocalPinEntry {
  const LocalPinEntry({required this.serverPinOrder, required this.pinnedAt});

  /// The largest server order the list was sorting above when the pin was
  /// recorded — at least the chat's own main-list order.
  ///
  /// Server positions are ever-increasing (a newly pinned chat sorts first),
  /// so a larger snapshot means a later pin. It is both the recency key the
  /// band orders by and the floor the next local pin has to clear.
  final int serverPinOrder;

  /// Unix seconds at pin time, breaking ties between snapshots that are equal
  /// because no server position has moved in between.
  final int pinnedAt;

  @override
  String toString() => 'LocalPinEntry($serverPinOrder:$pinnedAt)';
}

class LocalPinStore extends ChangeNotifier {
  LocalPinStore();

  /// The app-wide store; the view model and the settings switch share it.
  static final LocalPinStore shared = LocalPinStore();

  /// The switch's preference key.
  static const String unlimitedPreferenceKey = 'mithka.localPins.unlimited.v1';

  static const String _entryPrefix = 'mithka.localPins.v1.user';

  /// Band base for a local pin in a list with no positive server order to sit
  /// above — a chat that has no main-list position at all.
  static const int emptyBandBase = 4611686018427387904; // 1 << 62.

  /// Highest order a summary may carry.
  ///
  /// The band walks up from the list's largest server order by one per local,
  /// and rows sort with `compareTo` on `int`. Staying below this keeps
  /// `base + k` inside the range the sync-load path accepts, and in
  /// particular from wrapping negative, which would invert the window.
  static const int _maxOrder = 9223371469634506751;

  SharedPreferences? _prefs;
  bool _unlimited = false;
  int? _activeUserId;
  final Map<int, LocalPinEntry> _entries = {};
  int _revision = 0;
  int? _bandRevision;
  Map<int, int> _bandOrders = const {};
  int _bandBase = 0;

  bool get unlimitedEnabled => _unlimited;

  int? get activeAccountUserId => _activeUserId;

  /// The active account's local pins, keyed by chat id.
  Map<int, LocalPinEntry> get entries => Map.unmodifiable(_entries);

  /// The chats pinned on this device right now.
  Iterable<int> get pinnedChatIds => _entries.keys;

  /// The largest recorded [LocalPinEntry.serverPinOrder], 0 when there is no
  /// pin. A new pin takes at least this value, so a later pin always outranks
  /// an earlier one even when the server positions did not move in between.
  int get maxServerPinOrder {
    var max = 0;
    for (final entry in _entries.values) {
      if (entry.serverPinOrder > max) max = entry.serverPinOrder;
    }
    return max;
  }

  /// Loads the switch and this account's pins.
  ///
  /// Called once the preferences are available. Without it the store stays
  /// dormant and every local-pin path is off, so the feature cannot half-work
  /// before its switch is wired.
  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _unlimited = prefs.getBool(unlimitedPreferenceKey) ?? false;
    _loadAccountEntries();
  }

  /// Turns the switch on or off.
  ///
  /// Turning the switch off keeps the entries in the preference store — they
  /// are dormant until it is turned back on — and the caller drops the band
  /// orders by syncing the list, because the pins stop applying client-side.
  Future<void> setUnlimitedEnabled(bool enabled) async {
    if (_unlimited == enabled) return;
    _unlimited = enabled;
    final prefs = _prefs;
    if (prefs != null) {
      if (enabled) {
        await prefs.setBool(unlimitedPreferenceKey, true);
      } else {
        await prefs.remove(unlimitedPreferenceKey);
      }
    }
    notifyListeners();
  }

  /// Scopes the store to an account, like `GroupRemarkController` does.
  ///
  /// Chat ids are account-scoped, so entries are read from the new account's
  /// keys from here on; the previous account's entries stay untouched. This is
  /// also the load path after startup: [initialize] usually runs before the
  /// account is known, and the first `set meId` is what brings the account's
  /// saved pins in.
  void setActiveAccountUserId(int? userId) {
    if (_activeUserId == userId) return;
    _activeUserId = userId;
    // A new scope retires every write that was issued under the old one.
    _loadGeneration++;
    _loadAccountEntries();
  }

  bool isLocallyPinned(int chatId) =>
      unlimitedEnabled && _entries.containsKey(chatId);

  LocalPinEntry? entryFor(int chatId) =>
      unlimitedEnabled ? _entries[chatId] : null;

  /// Whether a pin can be recorded at all.
  ///
  /// A chat with no positive position — not in a list this account can see —
  /// has nothing to sort by, so a local pin would have no place to sit.
  static bool isEligible({required int order}) => order > 0;

  /// Pins [chatId] on this device.
  ///
  /// No-op when the switch is off, when no account is active, or when
  /// [serverPinOrder] is not eligible — the caller passes the largest server
  /// order the list was sorting above, so the band lands above it.
  Future<void> pin(
    int chatId, {
    required int serverPinOrder,
    required int pinnedAt,
  }) async {
    if (!unlimitedEnabled) return;
    final userId = _activeUserId;
    if (userId == null) return;
    if (!isEligible(order: serverPinOrder)) return;

    final existing = _entries[chatId];
    if (existing != null &&
        existing.serverPinOrder == serverPinOrder &&
        existing.pinnedAt == pinnedAt) {
      return;
    }

    final entry = LocalPinEntry(
      serverPinOrder: serverPinOrder,
      pinnedAt: pinnedAt,
    );
    _entries[chatId] = entry;
    if (serverPinOrder > _bandBase) _bandBase = serverPinOrder;
    _invalidateBand();
    await _prefs?.setString(_key(userId, chatId), _encode(entry));
    notifyListeners();
  }

  /// The generation of the account scope the store was last loaded under.
  ///
  /// Every write re-checks it against the captured one, so a write issued for
  /// one account can never land on the keys of the account that replaced it
  /// while the request was in flight.
  int _loadGeneration = 0;

  /// Parks the preference write of [unpin] until completed; tests only.
  @visibleForTesting
  Completer<void>? debugUnpinBarrier;

  /// The current load generation.
  ///
  /// A caller that spans an await captures it and hands it back to [unpin], so
  /// a preference write can never land on the keys of the account that
  /// replaced the one it started with.
  int get loadGeneration => _loadGeneration;

  /// Drops the device-only pin for [chatId]. No-op when it is not pinned.
  ///
  /// [expectedGeneration] pins the pass that issued this write: when the
  /// store was re-scoped meanwhile the write is abandoned, because the
  /// preference key it computed addresses the replacement account.
  Future<void> unpin(int chatId, {int? expectedGeneration}) async {
    if (!unlimitedEnabled) return;
    final userId = _activeUserId;
    if (userId == null) return;
    if (_entries.remove(chatId) == null) return;
    _invalidateBand();
    final prefs = _prefs;
    // Host tests park this write to reproduce a native preference round trip
    // that is still in flight when the account changes underneath it.
    final barrier = debugUnpinBarrier;
    if (barrier != null) await barrier.future;
    if (prefs != null) {
      await prefs.remove(_key(userId, chatId));
    }
    if (expectedGeneration != null && _loadGeneration != expectedGeneration) {
      // The account changed under this write: the row is already gone from the
      // old scope, and the new scope is authoritative from here.
      return;
    }
    notifyListeners();
  }

  /// Drops every entry whose chat is not in [liveMainListChatIds].
  ///
  /// One preference write per dropped entry and a single notification for the
  /// pass. Callers pass chats they have reason to believe left the list; a
  /// chat that is merely not loaded yet must NOT be in the dropped set, or a
  /// pin would silently disappear on a partially loaded list.
  Future<void> pruneTo(Iterable<int> liveMainListChatIds) async {
    if (!unlimitedEnabled) return;
    final userId = _activeUserId;
    if (userId == null) return;
    final live = liveMainListChatIds.toSet();
    final stale = _entries.keys.where((id) => !live.contains(id)).toList();
    if (stale.isEmpty) return;
    for (final id in stale) {
      _entries.remove(id);
      await _prefs?.remove(_key(userId, id));
    }
    _invalidateBand();
    notifyListeners();
  }

  /// The sort order for [chatId]: the band order while it is pinned here,
  /// [liveOrder] otherwise.
  ///
  /// The band is `base + 1 + k`, where `base` is the largest recorded
  /// [LocalPinEntry.serverPinOrder] and the k-th local is counted with the
  /// oldest pin first — so every local sits above the server orders known when
  /// it was pinned and the newest local is above the other locals. The result
  /// depends only on the stored entries, so the same state always produces the
  /// same orders and a refresh cannot reshuffle the rows.
  int effectiveOrder(int chatId, int liveOrder) {
    if (!unlimitedEnabled) return liveOrder;
    if (!_entries.containsKey(chatId)) return liveOrder;
    return _band()[chatId] ?? liveOrder;
  }

  Map<int, int> _band() {
    if (_bandRevision == _revision) return _bandOrders;
    if (_entries.isEmpty) {
      _bandOrders = const {};
      _bandRevision = _revision;
      return _bandOrders;
    }

    // Oldest pin first; the chat id breaks ties so the mapping is a pure
    // function of the entries.
    final ordered = _entries.entries.toList()
      ..sort((a, b) {
        final byPinnedAt = a.value.pinnedAt.compareTo(b.value.pinnedAt);
        if (byPinnedAt != 0) return byPinnedAt;
        return a.key.compareTo(b.key);
      });

    // The base never walks back down: it is the largest order any recorded
    // pin has seen, including entries that were dropped since, so bands handed
    // out earlier are never handed out again and the rows they sort cannot
    // reshuffle when the list changes under them. With no positive server
    // order to clear, the band starts above the whole 32-bit server space.
    var base = _bandBase > 0 ? _bandBase : emptyBandBase;
    if (base + ordered.length > _maxOrder) base = _maxOrder - ordered.length;

    final orders = <int, int>{};
    for (var index = 0; index < ordered.length; index++) {
      orders[ordered[index].key] = base + 1 + index;
    }
    _bandOrders = orders;
    _bandRevision = _revision;
    return _bandOrders;
  }

  void _invalidateBand() {
    _revision++;
    _bandRevision = null;
  }

  /// Reads this account's pins out of the preference store.
  void _loadAccountEntries() {
    _loadGeneration++;
    _entries.clear();
    _bandBase = 0;
    _invalidateBand();
    final prefs = _prefs;
    final userId = _activeUserId;
    if (prefs == null || userId == null) return;

    final prefix = '$_entryPrefix$userId.';
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final chatId = int.tryParse(key.substring(prefix.length));
      final entry = _decode(prefs.getString(key));
      if (chatId == null || entry == null) continue;
      _entries[chatId] = entry;
      if (entry.serverPinOrder > _bandBase) _bandBase = entry.serverPinOrder;
    }
    _invalidateBand();
  }

  static String _key(int userId, int chatId) => '$_entryPrefix$userId.$chatId';

  static String _encode(LocalPinEntry entry) =>
      '${entry.serverPinOrder}:${entry.pinnedAt}';

  static LocalPinEntry? _decode(String? value) {
    if (value == null) return null;
    final separator = value.indexOf(':');
    if (separator <= 0) return null;
    final order = int.tryParse(value.substring(0, separator));
    final pinnedAt = int.tryParse(value.substring(separator + 1));
    if (order == null || pinnedAt == null) return null;
    return LocalPinEntry(serverPinOrder: order, pinnedAt: pinnedAt);
  }
}
