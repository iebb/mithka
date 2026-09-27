//
//  chat_sticker_packs_service.dart
//
//  Finds the sticker packs and custom-emoji packs used in one chat, or across
//  all of the user's chats. A [ChatPackScanner] walks messages newest first a
//  batch at a time — for the global finder, every chat's history merged into
//  one timeline by date — and the global scan is saved per account, so a
//  reopened finder resumes it and first catches up on newer messages.
//  Each batch collects sticker set ids (sticker messages) and custom_emoji_ids
//  (text/caption entities, single custom-emoji messages, reactions), resolves
//  the new ones to their sets, and dedupes by set id.
//

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'custom_emoji.dart';
import 'emoji_store.dart';
import 'sticker_item.dart';
import 'sticker_store.dart';

typedef TdQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class ChatUsedPack {
  ChatUsedPack({
    required this.id,
    required this.title,
    required this.isCustomEmoji,
    required this.itemCount,
    required this.uses,
    required this.lastUsed,
    required this.installed,
    this.users = 0,
    this.previews = const [],
  });

  final int id;
  final String title;
  final bool isCustomEmoji;
  final int itemCount;

  /// Uses in the messages scanned so far; grows as the scan goes back.
  int uses;

  /// Distinct senders (users or chats) behind those uses.
  int users;

  /// Unix time of the newest message that used this pack.
  int lastUsed;

  /// The first items of the set, for the row's preview strip.
  final List<StickerItem> previews;
  bool installed;
}

/// Raw set/emoji references pulled out of message JSON, before resolution.
class ChatPackReferences {
  /// Sticker set id → number of uses.
  final Map<int, int> stickerSets = {};

  /// custom_emoji_id → number of uses.
  final Map<int, int> customEmoji = {};

  /// Newest message date per sticker set id / custom_emoji_id.
  final Map<int, int> stickerSetDates = {};
  final Map<int, int> customEmojiDates = {};

  /// Who used each sticker set id / custom_emoji_id, as sender keys.
  final Map<int, Set<String>> stickerSetUsers = {};
  final Map<int, Set<String>> customEmojiUsers = {};

  Map<String, Object> toJson() => {
    'stickerSets': _counts(stickerSets),
    'customEmoji': _counts(customEmoji),
    'stickerSetDates': _counts(stickerSetDates),
    'customEmojiDates': _counts(customEmojiDates),
    'stickerSetUsers': _users(stickerSetUsers),
    'customEmojiUsers': _users(customEmojiUsers),
  };

  void restore(Map<String, dynamic> json) {
    _readCounts(json['stickerSets'], stickerSets);
    _readCounts(json['customEmoji'], customEmoji);
    _readCounts(json['stickerSetDates'], stickerSetDates);
    _readCounts(json['customEmojiDates'], customEmojiDates);
    _readUsers(json['stickerSetUsers'], stickerSetUsers);
    _readUsers(json['customEmojiUsers'], customEmojiUsers);
  }

  static Map<String, int> _counts(Map<int, int> map) => {
    for (final entry in map.entries) '${entry.key}': entry.value,
  };

  static Map<String, List<String>> _users(Map<int, Set<String>> map) => {
    for (final entry in map.entries) '${entry.key}': [...entry.value],
  };

  static void _readCounts(Object? json, Map<int, int> into) {
    if (json is! Map) return;
    json.forEach((key, value) {
      final id = int.tryParse('$key');
      if (id != null && value is int) into[id] = value;
    });
  }

  static void _readUsers(Object? json, Map<int, Set<String>> into) {
    if (json is! Map) return;
    json.forEach((key, value) {
      final id = int.tryParse('$key');
      if (id != null && value is List) {
        into[id] = value.whereType<String>().toSet();
      }
    });
  }

  void addMessage(Map<String, dynamic> message) {
    final date = message.integer('date') ?? 0;
    final senders = [?senderKey(message.obj('sender_id'))];
    final content = message.obj('content');
    switch (content?.type) {
      case 'messageSticker':
        _addSticker(content!.obj('sticker'), date, senders);
      case 'messageAnimatedEmoji':
        // A plain emoji sent alone animates from Telegram's built-in set,
        // which is not a pack anyone can add; only custom emoji count.
        final sticker = content!.obj('animated_emoji')?.obj('sticker');
        _addEmoji(
          sticker?.obj('full_type')?.int64('custom_emoji_id'),
          date,
          senders,
        );
    }
    for (final text in [content?.obj('text'), content?.obj('caption')]) {
      for (final entity
          in text?.objects('entities') ?? const <Map<String, dynamic>>[]) {
        final type = entity.obj('type');
        if (type?.type != 'textEntityTypeCustomEmoji') continue;
        _addEmoji(type!.int64('custom_emoji_id'), date, senders);
      }
    }
    final reactions = message
        .obj('interaction_info')
        ?.obj('reactions')
        ?.objects('reactions');
    for (final reaction in reactions ?? const <Map<String, dynamic>>[]) {
      final type = reaction.obj('type');
      if (type?.type != 'reactionTypeCustomEmoji') continue;
      // Every reactor is a use; TDLib names only the most recent reactors.
      _addEmoji(
        type!.int64('custom_emoji_id'),
        date,
        [
          for (final sender
              in reaction.objects('recent_sender_ids') ??
                  const <Map<String, dynamic>>[])
            ?senderKey(sender),
        ],
        count: math.max(1, reaction.integer('total_count') ?? 1),
      );
    }
  }

  /// A stable key for a message sender, or null when there is none.
  static String? senderKey(Map<String, dynamic>? sender) =>
      switch (sender?.type) {
        'messageSenderUser' => 'u${sender!.int64('user_id')}',
        'messageSenderChat' => 'c${sender!.int64('chat_id')}',
        _ => null,
      };

  void _addSticker(
    Map<String, dynamic>? sticker,
    int date,
    List<String> senders,
  ) {
    if (sticker == null) return;
    final customEmojiId = sticker.obj('full_type')?.int64('custom_emoji_id');
    if (customEmojiId != null && customEmojiId != 0) {
      _addEmoji(customEmojiId, date, senders);
      return;
    }
    _bump(
      stickerSets,
      stickerSetDates,
      stickerSetUsers,
      sticker.int64('set_id'),
      date,
      senders,
    );
  }

  void _addEmoji(int? id, int date, List<String> senders, {int count = 1}) =>
      _bump(
        customEmoji,
        customEmojiDates,
        customEmojiUsers,
        id,
        date,
        senders,
        count: count,
      );

  static void _bump(
    Map<int, int> counts,
    Map<int, int> dates,
    Map<int, Set<String>> users,
    int? id,
    int date,
    List<String> senders, {
    int count = 1,
  }) {
    if (id == null || id == 0) return;
    counts[id] = (counts[id] ?? 0) + count;
    dates[id] = math.max(dates[id] ?? 0, date);
    (users[id] ??= {}).addAll(senders);
  }
}

/// Where the global finder keeps its scan between window openings: one file
/// per Telegram user, so a reused account slot never inherits another
/// account's results.
class ChatPackScanStore {
  ChatPackScanStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  Future<File> _file(int userId) async {
    final support = await _supportDirectory();
    final owner = sha256.convert(utf8.encode('telegram-user:$userId'));
    return File('${support.path}/sticker-finder-v1/$owner.json');
  }

  Future<Map<String, dynamic>?> read(int userId) async {
    try {
      final file = await _file(userId);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(int userId, Map<String, dynamic> state) async {
    try {
      final file = await _file(userId);
      await file.parent.create(recursive: true);
      // Write aside, then rename: a crash mid-write never leaves half a file.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(state), flush: true);
      await temp.rename(file.path);
    } catch (_) {}
  }
}

class ChatStickerPacksService {
  ChatStickerPacksService({
    TdQuery? query,
    ChatPackScanStore? store,
    int Function()? now,
  }) : _query = query ?? TdClient.shared.query,
       _store = store ?? ChatPackScanStore(),
       _now = now ?? _unixNow;

  final TdQuery _query;
  final ChatPackScanStore _store;
  final int Function() _now;

  static int _unixNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// One chat's history, newest first. Not kept between openings: a single
  /// chat rescans in moments.
  ChatPackScanner chatScanner(int chatId) =>
      ChatPackScanner._(_query, walks: [_Walk.chat(chatId)]);

  /// Every chat in the main list and the archive, merged by message date.
  ///
  /// Resumes this account's previous scan and puts a new walk in front of
  /// it covering only messages sent since that scan began, so a reopened
  /// finder shows what it found before, counts what arrived since, and
  /// counts nothing twice.
  Future<ChatPackScanner> openGlobalScanner() async {
    int? userId;
    try {
      userId = (await _query({'@type': 'getMe'})).int64('id');
    } catch (_) {}
    final saved = userId == null ? null : await _store.read(userId);
    final scanner =
        (saved == null ? null : ChatPackScanner._restore(_query, saved)) ??
        ChatPackScanner._(_query, walks: []);
    final owner = userId;
    if (owner != null) {
      scanner._persist = (state) => _store.write(owner, state);
    }
    final now = _now();
    if (now > scanner._top) {
      scanner._walks.insert(0, _Walk.global(floor: scanner._top, ceiling: now));
      scanner._top = now;
    }
    return scanner;
  }

  Future<bool> install(ChatUsedPack pack) async {
    try {
      await _query({
        '@type': 'changeStickerSet',
        'set_id': pack.id,
        'is_installed': true,
        'is_archived': false,
      });
      pack.installed = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Installs every pack not yet installed; returns how many succeeded.
  Future<int> installAll(Iterable<ChatUsedPack> packs) async {
    var added = 0;
    for (final pack in packs.where((p) => !p.installed).toList()) {
      if (await install(pack)) added += 1;
    }
    if (added > 0) refreshComposerStores();
    return added;
  }

  static void refreshComposerStores() {
    StickerStore.shared.invalidate();
    EmojiStore.shared.invalidate();
  }
}

/// Upper bound for a chat whose newest message date is not known yet.
const int _unknownDate = 1 << 62;

class _ChatCursor {
  _ChatCursor(this.chatId, this.upperBound);

  final int chatId;

  /// No message still to be handed out is newer than this.
  int upperBound;

  /// Where the next page is read from.
  int fromMessageId = 0;

  /// The last message handed out. A restored scan reads from here, so
  /// messages fetched but not yet handed out are read again, not lost.
  int resumeFromId = 0;

  /// Nothing left to fetch.
  bool exhausted = false;

  /// The newest id of the unbroken run this cursor has processed so far, so
  /// each message it hands out extends one index range instead of opening
  /// a new one.
  int? runHigh;
  final Queue<Map<String, dynamic>> buffer = Queue();

  bool get live => buffer.isNotEmpty || !exhausted;
  int get head =>
      buffer.isNotEmpty ? (buffer.first.integer('date') ?? 0) : upperBound;

  Map<String, Object?> toJson() => {
    'chat': chatId,
    'bound': upperBound,
    'from': resumeFromId,
    'run': runHigh,
    'done': exhausted && buffer.isEmpty,
  };

  static _ChatCursor? fromJson(Object? json) {
    if (json is! Map) return null;
    final chat = json['chat'];
    final bound = json['bound'];
    final from = json['from'];
    if (chat is! int || bound is! int || from is! int) return null;
    final run = json['run'];
    return _ChatCursor(chat, bound)
      ..fromMessageId = from
      ..resumeFromId = from
      ..runHigh = run is int ? run : null
      ..exhausted = json['done'] == true;
  }
}

class _ChatListSource {
  _ChatListSource(this.listType);

  /// chatListMain or chatListArchive.
  final String listType;
  int loaded = 0;
  bool exhausted = false;

  /// Every chat not loaded yet had its last message at or before this.
  int boundary = _unknownDate;

  Map<String, dynamic> get chatList => {'@type': listType};

  Map<String, Object> toJson() => {
    'list': listType,
    'loaded': loaded,
    'done': exhausted,
    'boundary': boundary,
  };

  static _ChatListSource? fromJson(Object? json) {
    if (json is! Map) return null;
    final list = json['list'];
    final loaded = json['loaded'];
    final boundary = json['boundary'];
    if (list is! String || loaded is! int || boundary is! int) return null;
    return _ChatListSource(list)
      ..loaded = loaded
      ..boundary = boundary
      ..exhausted = json['done'] == true;
  }
}

/// Message ids already processed, per chat, as inclusive id ranges.
///
/// Every chat is read newest first in unbroken runs, so a chat holds a
/// handful of ranges however many messages it has. A message inside a range
/// is never counted again, and a read that lands in one jumps below it
/// rather than paging through messages already seen.
class _ReadIndex {
  final Map<int, List<(int, int)>> _ranges = {};

  (int, int)? rangeOf(int chatId, int id) {
    for (final range in _ranges[chatId] ?? const <(int, int)>[]) {
      if (range.$1 <= id && id <= range.$2) return range;
    }
    return null;
  }

  void add(int chatId, int low, int high) {
    var merged = (math.min(low, high), math.max(low, high));
    final kept = <(int, int)>[];
    for (final range in _ranges[chatId] ?? const <(int, int)>[]) {
      if (range.$1 <= merged.$2 && merged.$1 <= range.$2) {
        merged = (math.min(range.$1, merged.$1), math.max(range.$2, merged.$2));
      } else {
        kept.add(range);
      }
    }
    _ranges[chatId] = kept..add(merged);
  }

  bool hasRanges(int chatId) => _ranges[chatId]?.isNotEmpty ?? false;

  int get rangeCount =>
      _ranges.values.fold(0, (total, ranges) => total + ranges.length);

  Map<String, List<List<int>>> toJson() => {
    for (final entry in _ranges.entries)
      '${entry.key}': [
        for (final range in entry.value) [range.$1, range.$2],
      ],
  };

  void restore(Object? json) {
    if (json is! Map) return;
    json.forEach((key, value) {
      final chatId = int.tryParse('$key');
      if (chatId == null || value is! List) return;
      for (final range in value) {
        if (range is List &&
            range.length == 2 &&
            range[0] is int &&
            range[1] is int) {
          add(chatId, range[0] as int, range[1] as int);
        }
      }
    });
  }
}

/// Messages fetched past a walk's floor, starting right below [after].
class _Spill {
  const _Spill({
    required this.after,
    required this.messages,
    required this.nextFrom,
    required this.exhausted,
  });

  final int after;
  final List<Map<String, dynamic>> messages;
  final int nextFrom;
  final bool exhausted;
}

/// One newest-first walk over the messages dated in (floor, ceiling].
///
/// A reopened finder adds a walk above the previous one's ceiling, so walks
/// never overlap: each message is counted by exactly one of them.
class _Walk {
  _Walk({
    required this.floor,
    required this.ceiling,
    List<_ChatCursor> cursors = const [],
    List<_ChatListSource> sources = const [],
    Set<int> knownChats = const {},
  }) : cursors = [...cursors],
       sources = [...sources],
       knownChats = {...knownChats, for (final c in cursors) c.chatId};

  factory _Walk.global({required int floor, required int ceiling}) => _Walk(
    floor: floor,
    ceiling: ceiling,
    sources: [
      _ChatListSource('chatListMain'),
      _ChatListSource('chatListArchive'),
    ],
  );

  factory _Walk.chat(int chatId) => _Walk(
    floor: 0,
    ceiling: _unknownDate,
    cursors: [_ChatCursor(chatId, _unknownDate)],
  );

  final int floor;
  final int ceiling;
  final List<_ChatCursor> cursors;
  final List<_ChatListSource> sources;
  final Set<int> knownChats;
  bool exhausted = false;

  Map<String, Object?> toJson() => {
    'floor': floor,
    'ceiling': ceiling,
    'cursors': [for (final c in cursors) c.toJson()],
    'sources': [for (final s in sources) s.toJson()],
    'chats': [...knownChats],
  };

  static _Walk? fromJson(Object? json) {
    if (json is! Map) return null;
    final floor = json['floor'];
    final ceiling = json['ceiling'];
    final cursors = json['cursors'];
    final sources = json['sources'];
    final chats = json['chats'];
    if (floor is! int || ceiling is! int) return null;
    if (cursors is! List || sources is! List || chats is! List) return null;
    return _Walk(
      floor: floor,
      ceiling: ceiling,
      cursors: cursors
          .map(_ChatCursor.fromJson)
          .whereType<_ChatCursor>()
          .toList(),
      sources: sources
          .map(_ChatListSource.fromJson)
          .whereType<_ChatListSource>()
          .toList(),
      knownChats: chats.whereType<int>().toSet(),
    );
  }
}

/// Walks messages newest first and keeps the packs found so far.
///
/// Pack details come from getStickerSet, which Telegram rate-limits. They
/// are looked up by a background worker a few at a time, rows on screen
/// first, and never block the scan. A rate limit pauses the worker for as
/// long as Telegram asks; only "this set does not exist" is final.
class ChatPackScanner {
  ChatPackScanner._(this._query, {required List<_Walk> walks})
    : _walks = [...walks];

  static const int batchSize = 400;
  static const int previewCount = 16;
  static const int _pageSize = 100;
  static const int _chatPage = 50;
  static const int _fetchConcurrency = 6;
  static const int _setConcurrency = 4;
  static const int _maxAttempts = 3;
  static const int _stateVersion = 2;
  static const Duration _saveInterval = Duration(seconds: 3);
  static const Duration _setTimeout = Duration(seconds: 20);

  final TdQuery _query;

  /// Newest window first.
  final List<_Walk> _walks;
  final ChatPackReferences _refs = ChatPackReferences();
  final _ReadIndex _read = _ReadIndex();

  /// Messages a newer walk fetched below its floor, per chat: exactly the
  /// page an older walk needs next once it reaches the same point, handed
  /// over instead of fetched again.
  final Map<int, _Spill> _spills = {};
  final LinkedHashMap<int, ChatUsedPack> _packs = LinkedHashMap();

  /// Between a batch's first read and its counts landing in [_refs]: a save
  /// now would record cursor positions and index ranges past messages not
  /// yet counted, and a reopened scan would skip them. Saves wait.
  bool _loading = false;
  bool _saveAfterLoad = false;

  /// Packs looked up this session: previews and added state are current.
  /// The rest came from the saved scan and refresh when they are shown.
  final Set<int> _fresh = {};
  final Set<int> _unresolvableSets = {};
  final Map<int, int> _emojiSets = {};
  final Set<int> _unresolvableEmoji = {};

  /// Set ids waiting for getStickerSet, most urgent first.
  final LinkedHashSet<int> _queue = LinkedHashSet();
  final Set<int> _inFlight = {};
  final Map<int, int> _attempts = {};
  Completer<void>? _worker;
  DateTime? _pausedUntil;
  bool _closed = false;

  /// Called whenever a looked-up pack changes the list.
  void Function()? onChanged;

  /// The newest ceiling any walk has had; a reopened scan starts above it.
  int _top = 0;
  Future<void> Function(Map<String, dynamic> state)? _persist;
  DateTime? _lastSaved;
  Future<void>? _saving;
  bool _saveAgain = false;

  int scannedMessages = 0;

  @visibleForTesting
  int get readRangeCount => _read.rangeCount;

  /// True once every walk has read its window to the end.
  bool get exhausted => _walks.every((walk) => walk.exhausted);

  /// Packs found so far, in discovery order (newest use first).
  List<ChatUsedPack> get stickers => [
    for (final p in _packs.values)
      if (!p.isCustomEmoji) p,
  ];
  List<ChatUsedPack> get emoji => [
    for (final p in _packs.values)
      if (p.isCustomEmoji) p,
  ];

  static ChatPackScanner? _restore(TdQuery query, Map<String, dynamic> json) {
    final version = json['version'];
    if (version != 1 && version != _stateVersion) return null;
    final walks = json['walks'];
    final refs = json['refs'];
    final top = json['top'];
    if (walks is! List || refs is! Map<String, dynamic> || top is! int) {
      return null;
    }
    final scanner = ChatPackScanner._(
      query,
      walks: walks.map(_Walk.fromJson).whereType<_Walk>().toList(),
    );
    scanner._top = top;
    scanner.scannedMessages = json.integer('scannedMessages') ?? 0;
    scanner._refs.restore(refs);
    scanner._read.restore(json['read']);
    final emojiSets = json['emojiSets'];
    if (emojiSets is Map) {
      emojiSets.forEach((key, value) {
        final emojiId = int.tryParse('$key');
        if (emojiId != null && value is int) {
          scanner._emojiSets[emojiId] = value;
        }
      });
    }
    // Version 1 marked rate-limited lookups as unresolvable too; those lists
    // cannot be trusted, so a version 1 scan looks everything up again.
    if (version == _stateVersion) {
      scanner._unresolvableSets.addAll(
        (json['unresolvableSets'] as List? ?? const []).whereType<int>(),
      );
      scanner._unresolvableEmoji.addAll(
        (json['unresolvableEmoji'] as List? ?? const []).whereType<int>(),
      );
    }
    final packs = json['packs'];
    if (packs is Map) {
      packs.forEach((key, value) {
        final id = int.tryParse('$key');
        if (id == null || value is! Map) return;
        final title = value['t'];
        final count = value['n'];
        if (title is! String || count is! int) return;
        scanner._packs[id] = ChatUsedPack(
          id: id,
          title: title,
          isCustomEmoji: value['e'] == true,
          itemCount: count,
          uses: 0,
          lastUsed: 0,
          installed: value['i'] == true,
        );
      });
    }
    return scanner;
  }

  Map<String, dynamic> toJson() => {
    'version': _stateVersion,
    'top': _top,
    'scannedMessages': scannedMessages,
    'refs': _refs.toJson(),
    'read': _read.toJson(),
    'emojiSets': {
      for (final entry in _emojiSets.entries) '${entry.key}': entry.value,
    },
    'unresolvableSets': [..._unresolvableSets],
    'unresolvableEmoji': [..._unresolvableEmoji],
    // Enough to list, sort and filter a reopened scan with no network; the
    // previews come back as rows are shown.
    'packs': {
      for (final pack in _packs.values)
        '${pack.id}': {
          't': pack.title,
          'n': pack.itemCount,
          'e': pack.isCustomEmoji,
          'i': pack.installed,
        },
    },
    // A finished walk only matters through its ceiling, which [_top] keeps.
    'walks': [
      for (final walk in _walks)
        if (!walk.exhausted) walk.toJson(),
    ],
  };

  /// Saves the scan for the next opening, at most every few seconds unless
  /// [force]d. Scanners that are not kept (one chat) do nothing.
  Future<void> save({bool force = false}) async {
    final persist = _persist;
    if (persist == null) return;
    if (_loading) {
      _saveAfterLoad = true;
      return;
    }
    final now = DateTime.now();
    final last = _lastSaved;
    if (!force && last != null && now.difference(last) < _saveInterval) return;
    _lastSaved = now;
    // One write at a time: a save asked for mid-write becomes one more
    // write of the newest state, never two writes racing on the file.
    final running = _saving;
    if (running != null) {
      _saveAgain = true;
      return running;
    }
    final saving = _saving = () async {
      do {
        _saveAgain = false;
        await persist(toJson());
      } while (_saveAgain);
    }();
    try {
      await saving;
    } finally {
      _saving = null;
    }
  }

  /// Puts back what a restored scan found: counts and saved pack details at
  /// once, with no network. Packs saved before their details were kept are
  /// queued for lookup.
  Future<void> resolveKnown() async {
    _recount();
    _enqueueUnknown();
  }

  /// Scans the next [messages] messages and folds them into the packs.
  Future<void> loadMore({int messages = batchSize}) async {
    final batch = <Map<String, dynamic>>[];
    _loading = true;
    try {
      for (final walk in _walks) {
        if (batch.length >= messages) break;
        if (walk.exhausted) continue;
        batch.addAll(await _next(walk, messages - batch.length));
      }
    } finally {
      for (final message in batch) {
        _refs.addMessage(message);
      }
      scannedMessages += batch.length;
      _loading = false;
      if (_saveAfterLoad) {
        _saveAfterLoad = false;
        unawaited(save(force: true));
      }
    }
    await _resolveEmoji();
    _recount();
    _enqueueUnknown();
  }

  /// A row for [id] is on screen: look it up next if its preview and added
  /// state are not current yet.
  void requestPack(int id) {
    if (_fresh.contains(id) ||
        _inFlight.contains(id) ||
        _unresolvableSets.contains(id)) {
      return;
    }
    // Most recent request first: that is the row the user just scrolled to.
    final rest = [..._queue]..remove(id);
    _queue
      ..clear()
      ..add(id)
      ..addAll(rest);
    _startWorker();
  }

  /// Completes once every queued lookup has finished.
  Future<void> settle() async {
    while (_worker != null) {
      await _worker!.future;
    }
  }

  /// Stops the lookup worker; the page is gone.
  void close() {
    _closed = true;
    onChanged = null;
  }

  /// Queues sets the refs mention but no pack stands for yet, most used
  /// first.
  void _enqueueUnknown() {
    final uses = _setUses();
    final unknown =
        uses.keys
            .where(
              (id) =>
                  !_packs.containsKey(id) &&
                  !_unresolvableSets.contains(id) &&
                  !_inFlight.contains(id) &&
                  !_queue.contains(id),
            )
            .toList()
          ..sort((a, b) => uses[b]!.compareTo(uses[a]!));
    if (unknown.isEmpty) return;
    _queue.addAll(unknown);
    _startWorker();
  }

  void _startWorker() {
    if (_worker != null || _closed || _queue.isEmpty) return;
    final worker = _worker = Completer<void>();
    unawaited(
      _work().whenComplete(() {
        _worker = null;
        worker.complete();
      }),
    );
  }

  Future<void> _work() async {
    while (_queue.isNotEmpty && !_closed) {
      final wait = _pausedUntil?.difference(DateTime.now());
      if (wait != null && wait > Duration.zero) await Future.delayed(wait);
      final batch = _queue.take(_setConcurrency).toList();
      _queue.removeAll(batch);
      _inFlight.addAll(batch);
      final results = await Future.wait(batch.map(_loadSet));
      _inFlight.removeAll(batch);
      var changed = false;
      for (var i = 0; i < batch.length; i++) {
        final id = batch[i];
        switch (results[i]) {
          case _SetLoaded(:final pack):
            final previous = _packs[id];
            if (previous != null) {
              pack
                ..uses = previous.uses
                ..lastUsed = previous.lastUsed
                ..users = previous.users;
            }
            _packs[id] = pack;
            _fresh.add(id);
            changed = true;
          case _SetGone():
            _unresolvableSets.add(id);
            changed = _packs.remove(id) != null || changed;
          case _SetRateLimited(:final retryAfter):
            _pausedUntil = DateTime.now().add(retryAfter);
            _queue.add(id);
          case _SetFailed():
            final attempts = (_attempts[id] ?? 0) + 1;
            _attempts[id] = attempts;
            // Try again later this session; a saved pack keeps its details.
            if (attempts < _maxAttempts) _queue.add(id);
        }
      }
      if (changed) {
        _recount();
        onChanged?.call();
        // Lookups keep landing after the scan is paused or done; keep the
        // saved details up with them.
        unawaited(save());
      }
    }
  }

  Future<List<Map<String, dynamic>>> _next(_Walk walk, int count) async {
    final out = <Map<String, dynamic>>[];
    while (out.length < count) {
      await _loadChatsIfNeeded(walk);
      final newest = _newest(walk);
      if (newest == null || newest.head <= walk.floor) {
        walk.exhausted = true;
        for (final cursor in walk.cursors) {
          _spill(cursor, cursor.resumeFromId);
        }
        break;
      }
      if (newest.buffer.isEmpty) {
        await _fetchAround(walk, newest);
        continue;
      }
      final message = newest.buffer.removeFirst();
      final date = message.integer('date') ?? 0;
      final id = message.int64('id');
      final above = newest.resumeFromId;
      newest.upperBound = date;
      newest.resumeFromId = id ?? newest.resumeFromId;
      if (date <= walk.floor) {
        // Older than this window: an older walk has it, or had it. Hand
        // what was fetched to the next walk down instead of dropping it.
        newest.buffer.addFirst(message);
        _spill(newest, above);
        newest.exhausted = true;
        newest.runHigh = null;
        continue;
      }
      if (id == null) continue;
      // Already processed, by this walk or another: never counted twice.
      if (_read.rangeOf(newest.chatId, id) != null) {
        _extendRun(newest, id);
        continue;
      }
      // Newer than this window: a newer walk counts it. Not processed yet,
      // so it breaks the run.
      if (date > walk.ceiling) {
        newest.runHigh = null;
        continue;
      }
      _extendRun(newest, id);
      out.add(message);
    }
    return out;
  }

  /// Hands [cursor]'s fetched, unused messages — all below this walk's
  /// floor — to whichever older walk next reads this chat from right below
  /// [after], the last message this walk handed out.
  void _spill(_ChatCursor cursor, int after) {
    if (cursor.buffer.isNotEmpty && after != 0) {
      _spills[cursor.chatId] = _Spill(
        after: after,
        messages: [...cursor.buffer],
        nextFrom: cursor.fromMessageId,
        exhausted: cursor.exhausted,
      );
    }
    cursor.buffer.clear();
  }

  void _extendRun(_ChatCursor cursor, int id) {
    final high = cursor.runHigh ??= id;
    _read.add(cursor.chatId, id, high);
  }

  _ChatCursor? _newest(_Walk walk) {
    _ChatCursor? best;
    for (final cursor in walk.cursors) {
      if (!cursor.live) continue;
      if (best == null || cursor.head > best.head) best = cursor;
    }
    return best;
  }

  /// Loads more of each chat list while an unloaded chat could hold a message
  /// newer than every loaded one, and newer than the walk's floor.
  Future<void> _loadChatsIfNeeded(_Walk walk) async {
    for (final source in walk.sources) {
      while (!source.exhausted &&
          source.boundary > walk.floor &&
          (_newest(walk)?.head ?? -1) < source.boundary) {
        await _loadChats(walk, source);
      }
    }
  }

  Future<void> _loadChats(_Walk walk, _ChatListSource source) async {
    final limit = source.loaded + _chatPage;
    try {
      final res = await _query({
        '@type': 'getChats',
        'chat_list': source.chatList,
        'limit': limit,
      });
      final ids = res.int64Array('chat_ids') ?? const <int>[];
      final grew = ids.length > source.loaded;
      source.loaded = ids.length;
      if (ids.length < limit || !grew) source.exhausted = true;
      // Every id, not just the tail: the list reorders as chats get new
      // messages, and a restored walk must still pick up a chat that moved
      // above the part it had loaded.
      final fresh = [
        for (final id in ids)
          if (!walk.knownChats.contains(id)) id,
      ];
      final latest = await Future.wait(fresh.map(_lastMessage));
      for (var i = 0; i < fresh.length; i++) {
        walk.knownChats.add(fresh[i]);
        final (date, latestId) = latest[i];
        final cursor = _ChatCursor(fresh[i], date);
        if (date <= walk.floor) cursor.exhausted = true;
        // The newest messages were processed already (by a newer walk):
        // start below them instead of reading them again.
        final seen = latestId == 0 ? null : _read.rangeOf(fresh[i], latestId);
        if (seen != null) {
          cursor
            ..fromMessageId = seen.$1
            ..runHigh = seen.$2;
        }
        walk.cursors.add(cursor);
      }
      // Pinned chats lead the list whatever their dates, so the list's tail
      // is the one that bounds the chats still to come.
      if (ids.isNotEmpty) source.boundary = (await _lastMessage(ids.last)).$1;
    } catch (_) {
      source.exhausted = true;
    }
  }

  /// The chat's newest message: (date, id), or zeros when it has none.
  Future<(int, int)> _lastMessage(int chatId) async {
    try {
      final chat = await _query({'@type': 'getChat', 'chat_id': chatId});
      final last = chat.obj('last_message');
      return (last?.integer('date') ?? 0, last?.int64('id') ?? 0);
    } catch (_) {
      return (0, 0);
    }
  }

  /// Fetches the next page for [cursor] and, in parallel, for the other
  /// empty chats likely to be needed next, so a merge does not wait on one
  /// round trip per chat.
  Future<void> _fetchAround(_Walk walk, _ChatCursor cursor) async {
    final waiting =
        walk.cursors
            .where((c) => c != cursor && c.buffer.isEmpty && !c.exhausted)
            .toList()
          ..sort((a, b) => b.head.compareTo(a.head));
    await Future.wait(
      [cursor, ...waiting.take(_fetchConcurrency - 1)].map(_fetch),
    );
  }

  Future<void> _fetch(_ChatCursor cursor) async {
    if (cursor.fromMessageId == 0 && _read.hasRanges(cursor.chatId)) {
      // A restored walk reading this chat from the top: if its newest
      // messages were processed since, start below them without a fetch.
      final (_, latestId) = await _lastMessage(cursor.chatId);
      final seen = latestId == 0
          ? null
          : _read.rangeOf(cursor.chatId, latestId);
      if (seen != null) {
        cursor
          ..fromMessageId = seen.$1
          ..runHigh ??= seen.$2;
      }
    }
    final spill = _spills[cursor.chatId];
    if (spill != null && spill.after == cursor.fromMessageId) {
      _spills.remove(cursor.chatId);
      cursor.buffer.addAll(spill.messages);
      cursor.fromMessageId = spill.nextFrom;
      if (spill.exhausted && spill.messages.isEmpty) cursor.exhausted = true;
      return;
    }
    try {
      final page = await _query({
        '@type': 'getChatHistory',
        'chat_id': cursor.chatId,
        'from_message_id': cursor.fromMessageId,
        'offset': 0,
        'limit': _pageSize,
        'only_local': false,
      });
      final messages =
          page.objects('messages') ?? const <Map<String, dynamic>>[];
      var added = 0;
      int? skipDownTo;
      for (final message in messages) {
        final id = message.int64('id');
        if (id == null) continue;
        // The page can repeat the message it started from.
        if (cursor.fromMessageId != 0 && id >= cursor.fromMessageId) continue;
        // Inside a range already processed: the first one is handed out so
        // the run links up with the range; the rest are not read at all.
        if (skipDownTo != null && id >= skipDownTo) continue;
        final seen = _read.rangeOf(cursor.chatId, id);
        if (seen != null) skipDownTo = seen.$1;
        cursor.buffer.add(message);
        cursor.fromMessageId = seen?.$1 ?? id;
        added += 1;
      }
      if (added == 0) cursor.exhausted = true;
    } catch (_) {
      cursor.exhausted = true;
    }
  }

  Future<void> _resolveEmoji() async {
    final emojiIds = [
      for (final id in _refs.customEmoji.keys)
        if (!_emojiSets.containsKey(id) && !_unresolvableEmoji.contains(id)) id,
    ];
    for (var i = 0; i < emojiIds.length; i += 200) {
      final batch = emojiIds.sublist(i, math.min(i + 200, emojiIds.length));
      try {
        final res = await _query({
          '@type': 'getCustomEmojiStickers',
          'custom_emoji_ids': batch.map((e) => e.toString()).toList(),
        });
        for (final sticker
            in res.objects('stickers') ?? const <Map<String, dynamic>>[]) {
          final setId = sticker.int64('set_id');
          final emojiId = sticker.obj('full_type')?.int64('custom_emoji_id');
          if (setId == null || setId == 0 || emojiId == null) continue;
          _emojiSets[emojiId] = setId;
        }
        // Asked and not answered: these ids have no sticker behind them.
        for (final id in batch) {
          if (!_emojiSets.containsKey(id)) _unresolvableEmoji.add(id);
        }
      } catch (_) {
        // Rate limited or offline: the next batch asks again.
        return;
      }
    }
  }

  /// Uses per set id, stickers and resolved custom emoji together.
  Map<int, int> _setUses() {
    final uses = Map<int, int>.of(_refs.stickerSets);
    _refs.customEmoji.forEach((emojiId, count) {
      final setId = _emojiSets[emojiId];
      if (setId != null) uses[setId] = (uses[setId] ?? 0) + count;
    });
    return uses;
  }

  Future<_SetLookup> _loadSet(int id) async {
    try {
      final set = await _query({
        '@type': 'getStickerSet',
        'set_id': id,
      }).timeout(_setTimeout);
      final title = set.str('title');
      if (title == null) return const _SetGone();
      final items = parseStickers(set.objects('stickers'));
      return _SetLoaded(
        ChatUsedPack(
          id: id,
          title: title,
          isCustomEmoji:
              set.obj('sticker_type')?.type == 'stickerTypeCustomEmoji',
          itemCount: items.length,
          uses: 0,
          lastUsed: 0,
          installed: set.boolean('is_installed') ?? false,
          previews: items.take(previewCount).toList(growable: false),
        ),
      );
    } on TdError catch (error) {
      final retryAfter = rateLimitRetryAfter(error);
      if (retryAfter != null) return _SetRateLimited(retryAfter);
      // A 400 is Telegram saying the set is invalid or gone for good.
      return error.code == 400 ? const _SetGone() : const _SetFailed();
    } catch (_) {
      return const _SetFailed();
    }
  }

  /// Recomputes every pack's totals from the cumulative references.
  void _recount() {
    final uses = _setUses();
    final dates = Map<int, int>.of(_refs.stickerSetDates);
    final users = {
      for (final entry in _refs.stickerSetUsers.entries)
        entry.key: {...entry.value},
    };
    _refs.customEmoji.forEach((emojiId, count) {
      final setId = _emojiSets[emojiId];
      if (setId == null) return;
      dates[setId] = math.max(
        dates[setId] ?? 0,
        _refs.customEmojiDates[emojiId] ?? 0,
      );
      (users[setId] ??= {}).addAll(_refs.customEmojiUsers[emojiId] ?? const {});
    });
    for (final pack in _packs.values) {
      pack.uses = uses[pack.id] ?? 0;
      pack.lastUsed = dates[pack.id] ?? 0;
      pack.users = users[pack.id]?.length ?? 0;
    }
  }
}

/// How one getStickerSet lookup went.
sealed class _SetLookup {
  const _SetLookup();
}

final class _SetLoaded extends _SetLookup {
  const _SetLoaded(this.pack);
  final ChatUsedPack pack;
}

/// Telegram says the set does not exist.
final class _SetGone extends _SetLookup {
  const _SetGone();
}

final class _SetRateLimited extends _SetLookup {
  const _SetRateLimited(this.retryAfter);
  final Duration retryAfter;
}

/// Timed out, offline, or another passing failure.
final class _SetFailed extends _SetLookup {
  const _SetFailed();
}

/// How long Telegram asks to wait, if [error] is a rate limit: TDLib reports
/// "Too Many Requests: retry after N" (429) or a FLOOD_WAIT_N message.
Duration? rateLimitRetryAfter(TdError error) {
  final match =
      RegExp(r'retry after (\d+)').firstMatch(error.message) ??
      RegExp(r'FLOOD_WAIT_(\d+)').firstMatch(error.message);
  if (match != null) return Duration(seconds: int.parse(match.group(1)!));
  return error.code == 429 ? const Duration(seconds: 5) : null;
}

enum ChatPackSort { usage, recent, name, size }

/// Stable sort, so equal keys keep their discovery order.
List<ChatUsedPack> sortPacks(
  List<ChatUsedPack> packs,
  ChatPackSort sort, {
  required bool descending,
}) {
  int compare(ChatUsedPack a, ChatUsedPack b) => switch (sort) {
    ChatPackSort.usage => a.uses.compareTo(b.uses),
    ChatPackSort.recent => a.lastUsed.compareTo(b.lastUsed),
    ChatPackSort.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    ChatPackSort.size => a.itemCount.compareTo(b.itemCount),
  };
  final indexed = [for (var i = 0; i < packs.length; i++) (i, packs[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    if (c != 0) return descending ? -c : c;
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Title filter plus an optional "not added yet" filter.
List<ChatUsedPack> filterPacks(
  List<ChatUsedPack> packs, {
  String query = '',
  bool onlyMissing = false,
}) {
  final needle = query.trim().toLowerCase();
  return [
    for (final pack in packs)
      if ((!onlyMissing || !pack.installed) &&
          (needle.isEmpty || pack.title.toLowerCase().contains(needle)))
        pack,
  ];
}
