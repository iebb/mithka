//
//  sticker_store.dart
//
//  Loads the user's Telegram stickers grouped by pack for the composer's
//  sticker tab. "最近" (recent) comes first; each installed set is its own
//  tab — covers load up front, a pack's full list lazily when its tab opens.
//  Port of the Swift `StickerStore`.
//

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
  StickerStore._();
  static final StickerStore shared = StickerStore._();

  static const int recentPackId = -1;

  List<StickerPack> packs = [];
  bool loading = false;
  bool _loaded = false;

  @visibleForTesting
  void replacePacksForTest(List<StickerPack> value) {
    packs = List<StickerPack>.from(value);
    loading = false;
    _loaded = true;
    notifyListeners();
  }

  void reset() {
    packs = [];
    loading = false;
    _loaded = false;
    notifyListeners();
  }

  void loadIfNeeded() {
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    loading = true;
    notifyListeners();
    final result = <StickerPack>[];

    try {
      final recent = await TdClient.shared.query({
        '@type': 'getRecentStickers',
        'is_attached': false,
      });
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
    } catch (_) {}

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
      for (final info
          in sets.objects('sets') ?? const <Map<String, dynamic>>[]) {
        final id = info.int64('id');
        final title = info.str('title');
        if (id == null || title == null) continue;
        result.add(StickerPack(id: id, title: title, cover: _coverItem(info)));
      }
    } catch (_) {}

    packs = result;
    loading = false;
    notifyListeners();

    if (packs.isNotEmpty && !packs.first.loaded) {
      await loadPack(packs.first.id);
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
}
