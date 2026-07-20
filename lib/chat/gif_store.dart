//
//  gif_store.dart
//
//  Loads Telegram's saved animations for the composer's GIF tab.
//

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'gif_item.dart';

List<GifItem> parseSavedAnimations(List<Map<String, dynamic>>? animations) {
  if (animations == null) return const [];
  final result = <GifItem>[];
  for (final animation in animations) {
    final file = animation.obj('animation');
    final fileRef = TDParse.fileRef(file);
    if (file == null || fileRef == null) continue;
    final thumbnail = TDParse.fileRef(
      animation.obj('thumbnail')?.obj('file'),
      miniThumb: TDParse.decodeMiniThumb(animation.obj('minithumbnail')),
    );
    result.add(
      GifItem(
        id: fileRef.id,
        remoteId: file.obj('remote')?.str('id'),
        duration: animation.integer('duration') ?? 0,
        width: animation.integer('width') ?? 0,
        height: animation.integer('height') ?? 0,
        mimeType: animation.str('mime_type') ?? '',
        file: fileRef,
        thumbnail: thumbnail,
      ),
    );
  }
  return result;
}

typedef InlineGifSearchPage = ({List<GifItem> items, String nextOffset});

InlineGifSearchPage parseInlineGifSearchPage(Map<String, dynamic> response) {
  final queryId = response.int64('inline_query_id');
  if (queryId == null || queryId <= 0) {
    return (items: const <GifItem>[], nextOffset: '');
  }
  final items = <GifItem>[];
  final seen = <int>{};
  for (final result
      in response.objects('results') ?? const <Map<String, dynamic>>[]) {
    if (result.type != 'inlineQueryResultAnimation') continue;
    final resultId = result.str('id')?.trim();
    final animation = result.obj('animation');
    if (resultId == null || resultId.isEmpty || animation == null) continue;
    final parsed = parseSavedAnimations([animation]);
    if (parsed.isEmpty || !seen.add(parsed.first.id)) continue;
    items.add(
      parsed.first.asInlineResult(queryId: queryId, resultId: resultId),
    );
  }
  return (
    items: List<GifItem>.unmodifiable(items),
    nextOffset: response.str('next_offset') ?? '',
  );
}

class GifStore extends ChangeNotifier {
  GifStore._() {
    _subscription = TdClient.shared.subscribe().listen((update) {
      if (update.type == 'updateSavedAnimations') {
        unawaited(_load(force: true));
      }
    });
  }

  static final GifStore shared = GifStore._();

  List<GifItem> items = const [];
  bool loading = false;
  bool _loaded = false;
  int? _loadedSlot;
  late final StreamSubscription<Map<String, dynamic>> _subscription;

  @visibleForTesting
  void replaceItemsForTest(List<GifItem> value) {
    _loadedSlot = TdClient.shared.activeSlot;
    _loaded = true;
    loading = false;
    items = List<GifItem>.unmodifiable(value);
    notifyListeners();
  }

  void loadIfNeeded() {
    final slot = TdClient.shared.activeSlot;
    if (_loadedSlot != slot) {
      _loadedSlot = slot;
      _loaded = false;
      items = const [];
    }
    if (_loaded) return;
    _loaded = true;
    unawaited(_load());
  }

  Future<void> _load({bool force = false}) async {
    final slot = TdClient.shared.activeSlot;
    if (!force && loading && _loadedSlot == slot) return;
    _loadedSlot = slot;
    loading = true;
    notifyListeners();
    try {
      final response = await TdClient.shared.query({
        '@type': 'getSavedAnimations',
      });
      if (_loadedSlot != slot || TdClient.shared.activeSlot != slot) return;
      items = parseSavedAnimations(response.objects('animations'));
      _loaded = true;
    } catch (_) {
      if (_loadedSlot == slot) _loaded = false;
    } finally {
      if (_loadedSlot == slot) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
