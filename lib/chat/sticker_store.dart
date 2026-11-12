//
//  sticker_store.dart
//
//  Loads the user's Telegram stickers grouped by pack for the composer's
//  sticker tab. "最近" (recent) comes first; each installed set is its own
//  tab — covers load up front, a pack's full list lazily when its tab opens.
//  Port of the Swift `StickerStore`.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'custom_emoji.dart';
import 'sticker_item.dart';

class StickerPack {
  StickerPack({
    required this.id,
    required this.title,
    this.cover,
    this.stickers = const [],
    this.loaded = false,
  });
  final int id;
  final String title;
  final StickerItem? cover; // format-aware so tgs/webm set icons render
  List<StickerItem> stickers;
  bool loaded;
}

class StickerStore extends ChangeNotifier {
  StickerStore._() {
    // The installed sets are server state: a pack added from the set page,
    // another device or a server-side cleanup must reach the composer strip
    // without a restart (the pattern GifStore uses for saved animations).
    _subscription = TdClient.shared
        .updatesOfAny(const [
          'updateInstalledStickerSets',
          'updateRecentStickers',
          'updateStickerSet',
        ])
        .listen(_handleUpdate);
  }

  static final StickerStore shared = StickerStore._();

  static const int recentPackId = -1;

  List<StickerPack> packs = [];
  bool loading = false;
  bool _loaded = false;

  /// Identifies the newest pack-list load (EmojiStore's generation pattern):
  /// an in-flight load an [invalidate] or [reset] supersedes cannot publish.
  int _loadGeneration = 0;

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  void _handleUpdate(Map<String, dynamic> update) {
    switch (update['@type']) {
      case 'updateInstalledStickerSets':
      case 'updateRecentStickers':
        invalidate();
      case 'updateStickerSet':
        final setId = update.int64('set_id');
        if (setId == null) return;
        unawaited(_refreshPack(setId));
    }
  }

  /// Re-queries one installed pack whose contents changed, so an open tab
  /// shows the new stickers without a full reload. Packs not carried by the
  /// store (or still lazy) wait for the next full load.
  Future<void> _refreshPack(int setId) async {
    final index = packs.indexWhere((pack) => pack.id == setId);
    if (index < 0 || !packs[index].loaded) return;
    try {
      final set = await TdClient.shared.query({
        '@type': 'getStickerSet',
        'set_id': setId,
      });
      // A reload or reset may have replaced the list while the query was in
      // flight; the pack it was issued against is gone.
      if (packs.isEmpty || index >= packs.length || packs[index].id != setId) {
        return;
      }
      packs[index].stickers = parseStickers(set.objects('stickers'));
      packs[index].loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  /// The tab the panel opens on: the first installed set in the order TDLib
  /// returned, falling back to recents when no set is installed.
  int get defaultPackId {
    for (final pack in packs) {
      if (pack.id != recentPackId) return pack.id;
    }
    return recentPackId;
  }

  @visibleForTesting
  void replacePacksForTest(List<StickerPack> value) {
    packs = List<StickerPack>.from(value);
    loading = false;
    _loaded = true;
    notifyListeners();
  }

  void reset() {
    // Strand every in-flight load: its answer belongs to the account the
    // user just left.
    _loadGeneration++;
    packs = [];
    loading = false;
    _loaded = false;
    notifyListeners();
  }

  /// Reloads after the installed sets changed elsewhere; a store nobody has
  /// opened yet stays lazy.
  void invalidate() {
    if (!_loaded) return;
    _loaded = false;
    loadIfNeeded();
  }

  void loadIfNeeded() {
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    // Starting a load supersedes every older one, including one for this
    // same account that is still in flight.
    final generation = ++_loadGeneration;
    loading = true;
    notifyListeners();
    final result = <StickerPack>[];

    try {
      final recent = await TdClient.shared.query({
        '@type': 'getRecentStickers',
        'is_attached': false,
      });
      if (generation != _loadGeneration) return;
      final items = parseStickers(recent.objects('stickers'));
      result.add(
        StickerPack(
          id: recentPackId,
          title: AppStrings.t(AppStringKeys.stickerStoreRecent),
          cover: items.firstOrNull,
          stickers: items,
          loaded: true,
        ),
      );
    } catch (_) {
      if (generation != _loadGeneration) return;
    }

    if (result.isEmpty) {
      result.add(
        StickerPack(
          id: recentPackId,
          title: AppStrings.t(AppStringKeys.stickerStoreRecent),
          loaded: true,
        ),
      );
    }

    try {
      final sets = await TdClient.shared.query({
        '@type': 'getInstalledStickerSets',
        'sticker_type': {'@type': 'stickerTypeRegular'},
      });
      if (generation != _loadGeneration) return;
      for (final info
          in sets.objects('sets') ?? const <Map<String, dynamic>>[]) {
        final id = info.int64('id');
        final title = info.str('title');
        if (id == null || title == null) continue;
        result.add(StickerPack(id: id, title: title, cover: _coverItem(info)));
      }
    } catch (_) {
      if (generation != _loadGeneration) return;
    }

    packs = result;
    loading = false;
    notifyListeners();

    final initialPack = packs.firstWhere(
      (pack) => pack.id != recentPackId,
      orElse: () => packs.first,
    );
    if (!initialPack.loaded) {
      await loadPack(initialPack.id);
    }
  }

  Future<void> loadPack(int id) async {
    final idx = packs.indexWhere((p) => p.id == id);
    if (idx < 0 || packs[idx].loaded) return;
    try {
      final set = await TdClient.shared.query({
        '@type': 'getStickerSet',
        'set_id': id,
      });
      packs[idx].stickers = parseStickers(set.objects('stickers'));
      packs[idx].loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  /// Cover for the set-icon tab. The tab itself renders only a static thumbnail
  /// so tiny cells never spin up animated sticker decoders.
  StickerItem? _coverItem(Map<String, dynamic> info) {
    final covers = info.objects('covers');
    if (covers != null && covers.isNotEmpty) {
      final parsed = parseStickers([covers.first]);
      if (parsed.isNotEmpty) return parsed.first;
    }
    final thumb = info.obj('thumbnail');
    final file = TDParse.fileRef(thumb?.obj('file'));
    if (file == null) return null;
    final fmt = thumb?.obj('format')?.type;
    return StickerItem(
      id: file.id,
      width: 100,
      height: 100,
      emoji: '',
      isAnimated: fmt == 'thumbnailFormatTgs',
      isVideo: fmt == 'thumbnailFormatWebm',
      thumb: file,
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
