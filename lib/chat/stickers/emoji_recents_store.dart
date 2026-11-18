//
//  emoji_recents_store.dart
//
//  Device-local "recently used" emoji for the composer's emoji panel, mirroring
//  the recents section Telegram iOS leads its emoji pane with. Both standard
//  Unicode emoji and Premium custom emoji are tracked; a custom emoji is only
//  recorded while the active account can actually send one, so a lapsed
//  subscription cannot leave unrenderable cells in the panel.
//
//  Ranking is frequency-weighted recency, the same shape iOS uses: an entry
//  sorts by how often it was picked, then by when it was picked last, so a
//  habitual emoji survives a burst of one-off inserts.
//

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emoji_store.dart';

/// One recorded emoji. [customEmojiId] is 0 for standard Unicode emoji and the
/// Telegram `custom_emoji_id` for a Premium custom emoji, whose [emoji] then
/// holds the plain glyph it stands in for.
@immutable
class EmojiRecentEntry {
  const EmojiRecentEntry({
    required this.emoji,
    this.customEmojiId = 0,
    this.count = 1,
    this.lastUsed = 0,
  });

  final String emoji;
  final int customEmojiId;
  final int count;
  final int lastUsed;

  bool get isCustom => customEmojiId != 0;

  /// Identity of the entry: a custom emoji is its id, a standard one its text.
  String get identity => isCustom ? 'c$customEmojiId' : emoji;

  EmojiRecentEntry copyWith({int? count, int? lastUsed}) => EmojiRecentEntry(
    emoji: emoji,
    customEmojiId: customEmojiId,
    count: count ?? this.count,
    lastUsed: lastUsed ?? this.lastUsed,
  );

  Map<String, dynamic> toJson() => {
    'e': emoji,
    if (isCustom) 'id': customEmojiId.toString(),
    'c': count,
    't': lastUsed,
  };

  static EmojiRecentEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final emoji = value['e'];
    if (emoji is! String || emoji.isEmpty) return null;
    // Ids are stored as strings because a custom_emoji_id exceeds the safe
    // integer range of some JSON round-trips.
    final id = switch (value['id']) {
      final String text => int.tryParse(text) ?? 0,
      final int number => number,
      _ => 0,
    };
    return EmojiRecentEntry(
      emoji: emoji,
      customEmojiId: id,
      count: _asInt(value['c']) ?? 1,
      lastUsed: _asInt(value['t']) ?? 0,
    );
  }

  static int? _asInt(Object? value) => switch (value) {
    final int number => number,
    final double number => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };
}

class EmojiRecentsStore extends ChangeNotifier {
  EmojiRecentsStore._();
  static final EmojiRecentsStore shared = EmojiRecentsStore._();

  /// iOS keeps roughly four rows of recents; 48 leaves room for the same on a
  /// wide panel without pushing the catalog off screen.
  static const int maxEntries = 48;
  static const String storageKey = 'emojiPanelRecents.v1';

  List<EmojiRecentEntry> _entries = const [];
  bool _loaded = false;
  Future<void>? _loading;

  /// The last `lastUsed` stamp handed out. Stamps are strictly increasing:
  /// a burst of picks inside one wall-clock millisecond would otherwise all
  /// tie, leaving their order to the sort's treatment of equal keys rather
  /// than pick order.
  int _lastStamp = 0;

  /// The persisted history has not been read back yet, so a write now would
  /// replace it with the partial in-flight list. The load merges everything
  /// and writes once at the end.
  bool _persistAfterLoad = false;

  /// A clear issued while the load was in flight must survive the persisted
  /// history arriving.
  bool _clearedWhileLoading = false;

  /// Ranked recents, best first. Custom emoji are included regardless of the
  /// caller's entitlement; the panel filters what it can render.
  List<EmojiRecentEntry> get entries => _entries;

  /// The entries a non-Premium account can actually insert.
  List<EmojiRecentEntry> get renderableEntries => EmojiStore.shared.isPremium
      ? _entries
      : _entries.where((entry) => !entry.isCustom).toList(growable: false);

  bool get isEmpty => _entries.isEmpty;

  /// Loads the persisted list once. Safe to call from `initState`: the panel
  /// listens to this store and picks the list up when it arrives.
  Future<void> loadIfNeeded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    List<EmojiRecentEntry>? persisted;
    try {
      final prefs = await SharedPreferences.getInstance();
      persisted = decodeEntries(prefs.getString(storageKey));
    } catch (_) {
      persisted = const [];
    }
    // A clear that raced the read wins over the history: the user meant to
    // drop it, not to resurrect it. But mutations made after the clear are
    // newer than the read, so they survive it — only the persisted history
    // is rejected, not the whole in-memory list.
    if (_clearedWhileLoading) {
      _entries = rankEntries(_entries);
    } else {
      // Mutations made while the read was in flight are the newer half of
      // the truth; merge them with the history instead of replacing either.
      _entries = _mergeEntries(persisted, _entries);
    }
    _loaded = true;
    _loading = null;
    final persist = _persistAfterLoad;
    _persistAfterLoad = false;
    _clearedWhileLoading = false;
    notifyListeners();
    if (persist) _persist();
  }

  /// Newest-wins merge of a late read with entries already in memory: counts
  /// add, the fresher `lastUsed` wins, and ranking re-sorts the union.
  static List<EmojiRecentEntry> _mergeEntries(
    List<EmojiRecentEntry> older,
    List<EmojiRecentEntry> newer,
  ) {
    if (older.isEmpty) return newer;
    if (newer.isEmpty) return older;
    final byIdentity = <String, EmojiRecentEntry>{
      for (final entry in older) entry.identity: entry,
    };
    for (final entry in newer) {
      final existing = byIdentity[entry.identity];
      byIdentity[entry.identity] = existing == null
          ? entry
          : entry.copyWith(
              count: existing.count + entry.count,
              lastUsed: math.max(existing.lastUsed, entry.lastUsed),
            );
    }
    return rankEntries(byIdentity.values.toList());
  }

  /// Records a standard Unicode emoji insert.
  void record(String emoji) {
    if (emoji.isEmpty) return;
    _record(EmojiRecentEntry(emoji: emoji));
  }

  /// Records a Premium custom emoji insert, dropped for accounts that cannot
  /// send one so recents never advertise an unavailable glyph.
  void recordCustom(int customEmojiId, String emoji, {bool? isPremium}) {
    if (customEmojiId == 0 || emoji.isEmpty) return;
    if (!(isPremium ?? EmojiStore.shared.isPremium)) return;
    _record(EmojiRecentEntry(emoji: emoji, customEmojiId: customEmojiId));
  }

  /// Monotonic pick timestamp: the wall clock only provides a lower bound,
  /// because an in-test burst of records can land in the same millisecond.
  int _nextStamp() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastStamp = _lastStamp >= now ? _lastStamp + 1 : now;
    return _lastStamp;
  }

  void _record(EmojiRecentEntry entry) {
    final now = _nextStamp();
    final next = <EmojiRecentEntry>[
      entry.copyWith(count: 1, lastUsed: now),
      for (final existing in _entries)
        if (existing.identity != entry.identity) existing,
    ];
    // An emoji picked again moves up on frequency, so the count carries over.
    final previous = _entries
        .where((existing) => existing.identity == entry.identity)
        .firstOrNull;
    if (previous != null) {
      next[0] = entry.copyWith(count: previous.count + 1, lastUsed: now);
    }
    _entries = rankEntries(next);
    notifyListeners();
    _schedulePersist();
  }

  void clear() {
    // While the load is in flight the visible list can be empty even though
    // persisted history is about to arrive; the clear must still register.
    if (_entries.isEmpty && _loading == null) return;
    _entries = const [];
    notifyListeners();
    _schedulePersist();
  }

  /// Defers the disk write until the load settles: overwriting the persisted
  /// history with the partial in-flight list is exactly the data loss the
  /// race produced before.
  void _schedulePersist() {
    if (_loading != null) {
      _persistAfterLoad = true;
      // An empty visible list here is a clear, not a fresh install.
      if (_entries.isEmpty) _clearedWhileLoading = true;
      return;
    }
    _persist();
  }

  void _persist() {
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) {
            if (_entries.isEmpty) {
              return prefs.remove(storageKey);
            }
            return prefs.setString(storageKey, encodeEntries(_entries));
          })
          .catchError((Object _) => false),
    );
  }

  /// Drops all state and forgets what was loaded; tests re-seed from a mock
  /// preference store after this.
  @visibleForTesting
  void resetForTesting() {
    _entries = const [];
    _loaded = false;
    _loading = null;
    _persistAfterLoad = false;
    _clearedWhileLoading = false;
  }

  @visibleForTesting
  void seedForTesting(List<EmojiRecentEntry> entries) {
    _entries = rankEntries(entries);
    _loaded = true;
    notifyListeners();
  }
}

/// Frequency first, then recency, capped at [limit] — the lowest-ranked
/// entries fall off the end.
///
/// The comparator is made total by an identity tie-break: entries that tie on
/// both count and `lastUsed` (a burst of picks within one clock tick, or a
/// seed with unset timestamps) then order by identity, so the ranking is a
/// pure function of the data instead of `List.sort`'s unstable shuffle of
/// equal elements.
List<EmojiRecentEntry> rankEntries(
  List<EmojiRecentEntry> entries, {
  int limit = EmojiRecentsStore.maxEntries,
}) {
  final ranked = List<EmojiRecentEntry>.of(entries)
    ..sort((a, b) {
      if (a.count != b.count) return b.count.compareTo(a.count);
      if (a.lastUsed != b.lastUsed) return b.lastUsed.compareTo(a.lastUsed);
      return a.identity.compareTo(b.identity);
    });
  return ranked.length > limit
      ? List<EmojiRecentEntry>.unmodifiable(ranked.take(limit))
      : List<EmojiRecentEntry>.unmodifiable(ranked);
}

String encodeEntries(List<EmojiRecentEntry> entries) =>
    jsonEncode([for (final entry in entries) entry.toJson()]);

List<EmojiRecentEntry> decodeEntries(String? source) {
  if (source == null || source.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) return const [];
    final entries = <EmojiRecentEntry>[];
    final seen = <String>{};
    for (final value in decoded) {
      final entry = EmojiRecentEntry.fromJson(value);
      if (entry == null || !seen.add(entry.identity)) continue;
      entries.add(entry);
    }
    return rankEntries(entries);
  } catch (_) {
    return const [];
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
