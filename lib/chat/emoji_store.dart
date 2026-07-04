//
//  emoji_store.dart
//
//  Backs the composer's emoji panel. Standard emoji are plain Unicode
//  (EmojiCatalog); Telegram **Premium** users also get animated custom emoji,
//  loaded here grouped by their installed custom-emoji sets so the panel shows
//  one tab per pack. Port of the Swift `EmojiStore`.
//

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'custom_emoji.dart';
import 'sticker_item.dart';

class CustomEmojiPack {
  CustomEmojiPack({
    required this.id,
    required this.title,
    this.cover,
    required this.emoji,
  });
  final int id;
  final String title;
  final TdFileRef? cover;
  final List<StickerItem> emoji;
}

class EmojiStore extends ChangeNotifier {
  EmojiStore._();
  static final EmojiStore shared = EmojiStore._();

  bool isPremium = false;
  List<CustomEmojiPack> customPacks = [];
  bool _loaded = false;

  void reset() {
    isPremium = false;
    customPacks = [];
    _loaded = false;
    notifyListeners();
  }

  void loadIfNeeded() {
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final opt = await TdClient.shared.query({
        '@type': 'getOption',
        'name': 'is_premium',
      });
      isPremium = opt.boolean('value') ?? false;
      notifyListeners();
    } catch (_) {}
    if (!isPremium) return;

    try {
      final sets = await TdClient.shared.query({
        '@type': 'getInstalledStickerSets',
        'sticker_type': {'@type': 'stickerTypeCustomEmoji'},
      });
      final infos = sets.objects('sets') ?? const <Map<String, dynamic>>[];
      final result = <CustomEmojiPack>[];
      for (final info in infos) {
        final setId = info.int64('id');
        final title = info.str('title');
        if (setId == null || title == null) continue;
        try {
          final set = await TdClient.shared.query({
            '@type': 'getStickerSet',
            'set_id': setId,
          });
          final emoji = parseStickers(set.objects('stickers'));
          if (emoji.isEmpty) continue;
          result.add(
            CustomEmojiPack(
              id: setId,
              title: title,
              cover: _coverRef(info) ?? emoji.first.thumb,
              emoji: emoji,
            ),
          );
        } catch (_) {}
      }
      customPacks = result;
      notifyListeners();
    } catch (_) {}
  }

  TdFileRef? _coverRef(Map<String, dynamic> info) {
    final thumb = TDParse.fileRef(info.obj('thumbnail')?.obj('file'));
    if (thumb != null) return thumb;
    final covers = info.objects('covers');
    if (covers != null && covers.isNotEmpty) {
      return parseStickers([covers.first]).firstOrNull?.thumb;
    }
    return null;
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
