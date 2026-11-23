//
//  favorite_sticker_store.dart
//
//  Sticker favorites beyond Telegram's cap. The server keeps a short list
//  (5 by default, 10 for premium); with the Advanced switch on, a sticker
//  the server would drop is saved on this device only and merged into the
//  favorites the server still holds. Port of the reference client's unlimited-faved
//  stickers (MediaDataController TYPE_FAVE + NekoConfig).
//
//  The switch is off by default and lives in this app's own preference
//  store: with it off no extra entry is read or written, and entries an
//  earlier run left behind stay dormant until it is turned back on.
//
//  Entries are owned by the account that favorited them. Sticker ids are
//  account-scoped, so extras are keyed by the stable Telegram user id and
//  switching accounts never shows one account's favorites to another.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'stickers/custom_emoji.dart';
import 'stickers/sticker_item.dart';

class FavoriteStickerStore extends ChangeNotifier {
  FavoriteStickerStore._() {
    _subscription = TdClient.shared.updatesOf('updateFavoriteStickers').listen((
      update,
    ) {
      unawaited(_refreshFromServer());
    });
  }

  /// The app-wide store; the sticker panel and the settings switch share it.
  static final FavoriteStickerStore shared = FavoriteStickerStore._();

  /// The switch's preference key.
  static const String unlimitedPreferenceKey =
      'mithka.faveStickers.unlimited.v1';

  static const String _extrasKeyPrefix = 'mithka.faveStickers.v1.user.';

  SharedPreferences? _prefs;
  bool _unlimited = false;
  int? _activeUserId;

  List<StickerItem> _serverItems = const [];
  final Map<int, StickerItem> _extras = {};
  bool _fetching = false;

  /// Identifies the newest server load, like EmojiStore's generation guard:
  /// a load a reset or a reload supersedes cannot publish.
  int _loadGeneration = 0;

  /// The slot the server list was loaded for; an update from another slot
  /// (GifStore's _loadedSlot pattern) must not overwrite this one.
  int? _loadedSlot;

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  /// Server favorites plus locally-saved extras while the switch is on;
  /// server favorites only while it is off.
  List<StickerItem> get items {
    if (!_unlimited) return List.unmodifiable(_serverItems);
    final seen = <int>{};
    final merged = <StickerItem>[
      for (final item in _serverItems)
        if (seen.add(item.id)) item,
      for (final item in _extras.values)
        if (seen.add(item.id)) item,
    ];
    return merged;
  }

  bool get loading => _fetching;

  bool get unlimitedEnabled => _unlimited;

  int? get activeAccountUserId => _activeUserId;

  /// Loads the switch and this account's extras.
  ///
  /// Called once the preferences are available. Without it the store stays
  /// dormant: the server list is never fetched, extras are never read, and
  /// every unlimited path is off — so the feature cannot half-work before
  /// its switch is wired.
  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _unlimited = prefs.getBool(unlimitedPreferenceKey) ?? false;
    _loadAccountExtras();
  }

  /// Turns the switch on or off.
  ///
  /// Turning it off keeps any saved extras dormant in the preference store
  /// until it is turned back on; nothing is read or written while it is off.
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

  /// Scopes the store to an account, like [LocalPinStore].
  void setActiveAccountUserId(int? userId) {
    if (_activeUserId == userId) return;
    _activeUserId = userId;
    _loadAccountExtras();
    _serverItems = const [];
    notifyListeners();
  }

  /// Whether [fileId] is a favorite (server or, with the switch on, local).
  bool isFavorite(int fileId) {
    for (final item in _serverItems) {
      if (item.id == fileId) return true;
    }
    if (!_unlimited) return false;
    return _extras.containsKey(fileId);
  }

  /// Refreshes the server favorites for the current account scope.
  ///
  /// Called when the sticker surface opens (the composer sticker panel or
  /// the store page); re-fetching on open keeps the favorites section in
  /// sync with other devices, mirroring how the reference client batches
  /// getFavoriteStickers with its sticker loads.
  void loadIfNeeded() {
    unawaited(_refreshFromServer());
  }

  /// Fetches the server favorites. A fetch a reset, re-scope or newer fetch
  /// supersedes cannot publish.
  Future<void> _refreshFromServer() async {
    final generation = ++_loadGeneration;
    final slot = TdClient.shared.activeSlot;
    _loadedSlot = slot;
    _fetching = true;
    try {
      final response = await TdClient.shared.query({
        '@type': 'getFavoriteStickers',
      });
      if (generation != _loadGeneration || _loadedSlot != slot) return;
      _serverItems = parseStickers(response.objects('stickers'));
    } catch (_) {
      // A failed fetch leaves the last good list in place; the next panel
      // open retries.
    } finally {
      if (generation == _loadGeneration) {
        _fetching = false;
        notifyListeners();
      }
    }
  }

  /// Favorites [item].
  ///
  /// The server request is always sent — when the server accepts it the
  /// refetched list is the truth. When the item is missing from the refetched
  /// list (the cap was reached) and the switch is on, the item is kept on
  /// this device instead.
  Future<void> add(StickerItem item) async {
    try {
      await TdClient.shared.query({
        '@type': 'addFavoriteSticker',
        'sticker': {'@type': 'inputFileId', 'id': item.id},
      });
    } catch (_) {
      return;
    }
    await _refreshFromServer();
    if (_unlimited && !isFavorite(item.id)) {
      await _persistExtra(item);
      notifyListeners();
    }
  }

  /// Unfavorites [item]: the server entry goes, and so does any local extra.
  Future<void> remove(StickerItem item) async {
    try {
      await TdClient.shared.query({
        '@type': 'removeFavoriteSticker',
        'sticker': {'@type': 'inputFileId', 'id': item.id},
      });
    } catch (_) {
      return;
    }
    await _refreshFromServer();
    if (_extras.remove(item.id) != null) {
      await _removeExtraKey(item.id);
    }
    notifyListeners();
  }

  /// Reads this account's extras out of the preference store. Inert while
  /// the switch is off: nothing is read and nothing is written.
  void _loadAccountExtras() {
    _loadGeneration++;
    _extras.clear();
    final prefs = _prefs;
    final userId = _activeUserId;
    if (prefs == null || userId == null) return;
    final value = prefs.getString(_extrasKey(userId));
    if (value == null || value.isEmpty) return;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return;
      for (final entry in decoded) {
        if (entry is! List || entry.length != 8) continue;
        final tuple = entry
            .map((field) => field is int || field is String ? field : null)
            .toList();
        final item = _decodeEntry(tuple);
        if (item != null) _extras[item.id] = item;
      }
    } catch (_) {}
  }

  static StickerItem? _decodeEntry(List<dynamic> entry) {
    if (entry.length != 8) return null;
    final fileId = entry[0] as int?;
    final width = entry[2] as int?;
    final height = entry[3] as int?;
    if (fileId == null || width == null || height == null) return null;
    final thumbFileId = entry[7] as int?;
    return StickerItem(
      id: fileId,
      remoteId: entry[1] as String?,
      width: width,
      height: height,
      emoji: (entry[4] as String?) ?? '',
      isAnimated: entry[5] == true || entry[5] == 1,
      isVideo: entry[6] == true || entry[6] == 1,
      thumb: thumbFileId == null || thumbFileId == 0
          ? null
          : TdFileRef(id: thumbFileId),
    );
  }

  static String _extrasKey(int userId) => '$_extrasKeyPrefix$userId';

  static List<dynamic> _encodeEntry(StickerItem item) => [
    item.id,
    item.remoteId,
    item.width,
    item.height,
    item.emoji,
    item.isAnimated ? 1 : 0,
    item.isVideo ? 1 : 0,
    item.thumb?.id ?? 0,
  ];

  Future<void> _persistExtra(StickerItem item) async {
    _extras[item.id] = item;
    await _writeExtras();
  }

  Future<void> _removeExtraKey(int fileId) async {
    await _writeExtras();
  }

  Future<void> _writeExtras() async {
    final prefs = _prefs;
    final userId = _activeUserId;
    if (prefs == null || userId == null) return;
    await prefs.setString(
      _extrasKey(userId),
      jsonEncode([for (final item in _extras.values) _encodeEntry(item)]),
    );
  }

  @visibleForTesting
  void resetForTest() {
    _loadGeneration++;
    _serverItems = const [];
    _extras.clear();
    _fetching = false;
    _activeUserId = null;
    _loadedSlot = TdClient.shared.activeSlot;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
