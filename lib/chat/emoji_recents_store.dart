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
    try {
      final prefs = await SharedPreferences.getInstance();
      _entries = decodeEntries(prefs.getString(storageKey));
    } catch (_) {
      _entries = const [];
    }
    _loaded = true;
    _loading = null;
    notifyListeners();
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

  void _record(EmojiRecentEntry entry) {
    final now = DateTime.now().millisecondsSinceEpoch;
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
    _persist();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries = const [];
    notifyListeners();
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
List<EmojiRecentEntry> rankEntries(
  List<EmojiRecentEntry> entries, {
  int limit = EmojiRecentsStore.maxEntries,
}) {
  final ranked = List<EmojiRecentEntry>.of(entries)
    ..sort((a, b) {
      if (a.count != b.count) return b.count.compareTo(a.count);
      return b.lastUsed.compareTo(a.lastUsed);
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
