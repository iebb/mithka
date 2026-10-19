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

  /// Identifies the newest installed-pack load. Every load captures the value
  /// it started with, and only that exact value may publish: a newer account's
  /// load, an [invalidate] or a [reset] supersedes whatever came before it.
  int _loadGeneration = 0;

  void reset() {
    // Strand every in-flight load. Its answer describes the account the user
    // just left, so it must not repopulate this one.
    _loadGeneration++;
    isPremium = false;
    customPacks = [];
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
    // Starting a load supersedes every older one, including a load for this
    // same account that is still in flight.
    final generation = ++_loadGeneration;
    final owner = _pinOwner();
    // Nothing to pin (no signed-in account, or a slot whose client was
    // replaced mid-read): leave the store lazy rather than guess an account.
    if (owner == null) return;
    _loaded = true;
    _load(owner, generation);
  }

  /// The account this load answers for, captured before its first await.
  ///
  /// Installed pack ids and custom emoji ids are account-scoped: asking the
  /// replacement account for the previous account's set ids fails, and taking
  /// the replacement account's answer would show its packs under the wrong
  /// account. Pinning is deliberately weaker than [TdClient.retainAccountSlot]
  /// — a pack list holds no account resources, so it must never keep a logged
  /// out account's client alive.
  _PackLoadOwner? _pinOwner() {
    final client = TdClient.shared;
    if (client.isShuttingDown) return null;
    final slot = client.activeSlot;
    final clientId = client.activeClientId;
    if (clientId == 0) return null;
    // A session swap or QR reset can replace the slot's client between those
    // two reads; pinning that would load an account nobody selected.
    if (client.clientId(slot) != clientId) return null;
    return _PackLoadOwner(client, slot, clientId);
  }

  Future<void> _load(_PackLoadOwner owner, int generation) async {
    // Re-checked after every await: the root may have been reset, a newer load
    // may have started, or the owner's client may have been replaced while the
    // request was in flight.
    bool isCurrent() => generation == _loadGeneration && owner.isCurrent;

    try {
      final opt = await owner.query({
        '@type': 'getOption',
        'name': 'is_premium',
      });
      if (!isCurrent()) return;
      isPremium = opt.boolean('value') ?? false;
      notifyListeners();
    } catch (_) {
      // A failure for the previous account must not disturb this one.
      if (!isCurrent()) return;
    }
    if (!isCurrent()) return;
    if (!isPremium && !await TdClient.shared.activeAccountUsesBotApi()) return;
    if (!isCurrent()) return;

    try {
      final sets = await owner.query({
        '@type': 'getInstalledStickerSets',
        'sticker_type': {'@type': 'stickerTypeCustomEmoji'},
      });
      if (!isCurrent()) return;
      final infos = sets.objects('sets') ?? const <Map<String, dynamic>>[];
      // Fetched concurrently: one getStickerSet round trip per installed pack
      // otherwise delays the picker by the sum of them all.
      final packs = await Future.wait(
        infos.map((info) async {
          final setId = info.int64('id');
          final title = info.str('title');
          if (setId == null || title == null) return null;
          // An account switch while an earlier pack was fetched makes every
          // remaining request pointless; skip it instead of querying a client
          // this load no longer represents.
          if (!isCurrent()) return null;
          try {
            final set = await owner.query({
              '@type': 'getStickerSet',
              'set_id': setId,
            });
            if (!isCurrent()) return null;
            final emoji = parseStickers(set.objects('stickers'));
            if (emoji.isEmpty) return null;
            return CustomEmojiPack(
              id: setId,
              title: title,
              cover: _coverRef(info) ?? emoji.first.thumb,
              emoji: emoji,
            );
          } catch (_) {
            return null;
          }
        }),
      );
      if (!isCurrent()) return;
      customPacks = packs.nonNulls.toList();
      notifyListeners();
    } catch (_) {
      // A stale failure (the previous account's request erroring after the
      // switch) must not re-arm the store: the new account's own load state
      // stays untouched.
      if (!isCurrent()) return;
      _loaded = false; // allow retry on next loadIfNeeded()
    }
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

/// One account's concrete TDLib client, pinned when an installed-pack load
/// starts. Queries never resolve the foreground account.
final class _PackLoadOwner {
  _PackLoadOwner(this._client, this.slot, this.clientId);

  final TdClient _client;
  final int slot;
  final int clientId;

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) =>
      _client.queryTo(request, clientId);

  /// False once the user switched accounts, this slot's client was replaced or
  /// closed, or shutdown started.
  bool get isCurrent =>
      // Shutdown refuses queries before the slot and active-client mappings
      // necessarily disappear, so the latch belongs to "still this account".
      !_client.isShuttingDown &&
      _client.clientId(slot) == clientId &&
      _client.activeClientId == clientId;
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
