//
//  forum_topic_index.dart
//
//  A process-wide index of forum topics per chat. A conversation pane rebuilt
//  for another topic renders its rail from this index on the first frame,
//  instead of collapsing to a lone "All" chip until getForumTopics returns.
//

import 'package:flutter/foundation.dart';

import 'json_helpers.dart';

/// One topic's display identity plus its live unread counter.
class ForumTopicIndexEntry {
  const ForumTopicIndexEntry({
    required this.id,
    required this.name,
    this.iconCustomEmojiId = 0,
    this.iconColor = 0,
    this.unreadCount = 0,
    this.isMuted = false,
    this.lastMessageId = 0,
    this.lastReadInboxMessageId = 0,
  });

  final int id;
  final String name;
  final int iconCustomEmojiId;
  final int iconColor;
  final int unreadCount;
  final bool isMuted;

  /// The newest message id this entry has accounted for, so an observed read
  /// position reaching it can clear the counter locally.
  final int lastMessageId;
  final int lastReadInboxMessageId;

  ForumTopicIndexEntry copyWith({
    String? name,
    int? iconCustomEmojiId,
    int? iconColor,
    int? unreadCount,
    bool? isMuted,
    int? lastMessageId,
    int? lastReadInboxMessageId,
  }) => ForumTopicIndexEntry(
    id: id,
    name: name ?? this.name,
    iconCustomEmojiId: iconCustomEmojiId ?? this.iconCustomEmojiId,
    iconColor: iconColor ?? this.iconColor,
    unreadCount: unreadCount ?? this.unreadCount,
    isMuted: isMuted ?? this.isMuted,
    lastMessageId: lastMessageId ?? this.lastMessageId,
    lastReadInboxMessageId:
        lastReadInboxMessageId ?? this.lastReadInboxMessageId,
  );

  /// A live entry ahead of a freshly fetched page: its counter already
  /// includes traffic the page's snapshot predates.
  bool readsAheadOfPage(
    int pageLastReadInboxMessageId,
    int pageLastMessageId,
  ) =>
      lastReadInboxMessageId > pageLastReadInboxMessageId ||
      (lastMessageId > pageLastMessageId && unreadCount > 0);

  /// Display identity: what a rail row or picker row paints. Bookkeeping ids
  /// are excluded so read-position traffic alone never wakes a listener.
  @override
  bool operator ==(Object other) =>
      other is ForumTopicIndexEntry &&
      other.id == id &&
      other.name == name &&
      other.iconCustomEmojiId == iconCustomEmojiId &&
      other.iconColor == iconColor &&
      other.unreadCount == unreadCount &&
      other.isMuted == isMuted;

  @override
  int get hashCode =>
      Object.hash(id, name, iconCustomEmojiId, iconColor, unreadCount, isMuted);

  /// Parses a `forumTopic` object from getForumTopics/getForumTopic. Topic ids
  /// are chat-scoped, so the chat context must be supplied by the caller.
  ///
  /// In the pinned TDLib schema `last_read_inbox_message_id` and
  /// `unread_count` live on the outer topic, not on `info`.
  static ForumTopicIndexEntry? fromTopic(Map<String, dynamic> raw) {
    final info = raw.obj('info') ?? raw;
    final id =
        info.integer('forum_topic_id') ??
        raw.integer('forum_topic_id') ??
        info.int64('message_thread_id') ??
        raw.int64('message_thread_id');
    if (id == null || id == 0) return null;
    final name = info.str('name') ?? raw.str('name');
    if (name == null || name.isEmpty) return null;
    final icon = info.obj('icon') ?? raw.obj('icon');
    return ForumTopicIndexEntry(
      id: id,
      name: name,
      iconCustomEmojiId:
          icon?.int64('custom_emoji_id') ??
          info.int64('icon_custom_emoji_id') ??
          raw.int64('icon_custom_emoji_id') ??
          0,
      iconColor:
          icon?.integer('color') ??
          info.integer('icon_color') ??
          raw.integer('icon_color') ??
          0,
      unreadCount: _nonNegative(
        raw.integer('unread_count') ?? info.integer('unread_count'),
      ),
      isMuted: (raw.obj('notification_settings')?.integer('mute_for') ?? 0) > 0,
      lastMessageId: raw.obj('last_message')?.int64('id') ?? 0,
      lastReadInboxMessageId:
          raw.int64('last_read_inbox_message_id') ??
          info.int64('last_read_inbox_message_id') ??
          0,
    );
  }
}

int _nonNegative(int? value) {
  final v = value ?? 0;
  return v < 0 ? 0 : v;
}

/// Topic ids are chat-scoped message ids, so chats are keyed per account slot.
///
/// Listeners wake only when a displayed field (name, icon, unread counter,
/// mute state) actually changes, so a rail repaints on real traffic, not on
/// bookkeeping.
class ForumTopicIndex extends ChangeNotifier {
  ForumTopicIndex._();

  static final ForumTopicIndex shared = ForumTopicIndex._();

  /// Bound on indexed chats: a session visits a handful of forums, and the
  /// index only needs the ones whose panes get rebuilt while switching.
  static const _chatCapacity = 16;

  final Map<(int, int), Map<int, ForumTopicIndexEntry>> _topics = {};
  final Map<int, Set<int>> _topicChats = {};

  List<ForumTopicIndexEntry> topicsFor(int slot, int chatId) {
    final entries = _topics[(slot, chatId)];
    if (entries == null) return const [];
    return entries.values.toList(growable: false);
  }

  ForumTopicIndexEntry? entryFor(int slot, int chatId, int topicId) =>
      _topics[(slot, chatId)]?[topicId];

  bool knowsTopics(int slot, int chatId) =>
      (_topics[(slot, chatId)]?.isNotEmpty) ?? false;

  /// Stores a complete getForumTopics page. The response is authoritative for
  /// both membership (topics deleted elsewhere drop out) and counters.
  void storeAll(int slot, int chatId, List<ForumTopicIndexEntry> entries) {
    final key = (slot, chatId);
    if (entries.isEmpty) {
      final removed = _topics.remove(key) != null;
      _topicChats[slot]?.remove(chatId);
      if (removed) notifyListeners();
      return;
    }
    var displayChanged = false;
    final topics = _topics.putIfAbsent(key, () => {});
    final keep = <int>{};
    for (final entry in entries) {
      keep.add(entry.id);
      final previous = topics[entry.id];
      // Keep the bookkeeping ids of a live entry when the page is stale: a
      // counter that already saw newer traffic must not be rewound.
      final merged =
          previous != null &&
              previous.readsAheadOfPage(
                entry.lastReadInboxMessageId,
                entry.lastMessageId,
              )
          ? previous.copyWith(
              name: entry.name,
              iconCustomEmojiId: entry.iconCustomEmojiId,
              iconColor: entry.iconColor,
              isMuted: entry.isMuted,
            )
          : entry;
      if (previous != merged) displayChanged = true;
      topics[entry.id] = merged;
    }
    displayChanged |= topics.keys.any((id) => !keep.contains(id));
    topics.removeWhere((id, _) => !keep.contains(id));
    _topicChats.putIfAbsent(slot, () => {}).add(chatId);
    _evictStaleChats();
    if (displayChanged) notifyListeners();
  }

  void _evictStaleChats() {
    var live = 0;
    for (final chatIds in _topicChats.values) {
      live += chatIds.length;
    }
    if (live <= _chatCapacity) return;
    var toDrop = live - _chatCapacity;
    final chatsBySlot = _topicChats.entries.toList();
    for (final slotEntry in chatsBySlot) {
      if (toDrop <= 0) break;
      final slot = slotEntry.key;
      for (final chatId in slotEntry.value.toList()) {
        if (toDrop <= 0) break;
        _topics.remove((slot, chatId));
        _topicChats[slot]?.remove(chatId);
        toDrop--;
      }
    }
  }

  /// Feeds TDLib objects routed by the client, mirroring [TdUserIndex.observe].
  void observe(int slot, Map<String, dynamic> object) {
    switch (object.type) {
      case 'updateNewMessage':
        _observeNewMessage(slot, object.obj('message'));
      case 'updateForumTopic':
        _observeForumTopic(
          slot,
          object.int64('chat_id'),
          object.integer('forum_topic_id'),
          object.int64('last_read_inbox_message_id'),
          object.obj('notification_settings'),
        );
      case 'updateForumTopicInfo':
        _observeForumTopicInfo(slot, object.obj('info'));
    }
  }

  void _observeNewMessage(int slot, Map<String, dynamic>? raw) {
    if (raw == null) return;
    final chatId = raw.int64('chat_id');
    if (chatId == null) return;
    // A message outside any topic belongs to General (id 1).
    final topicRef = raw.obj('topic_id');
    final topicId = topicRef?.type == 'messageTopicForum'
        ? topicRef?.integer('forum_topic_id')
        : 1;
    if (topicId == null) return;
    final topics = _topics[(slot, chatId)];
    final previous = topics?[topicId];
    if (topics == null || previous == null) return;
    final messageId = raw.integer('id') ?? 0;
    final outgoing = raw.boolean('is_outgoing') ?? false;
    // Reconcile with the known read/page state instead of counting every
    // arrival: a message at or below the inbox watermark is already read,
    // and an id the fetched page already represented was counted there.
    final unreadDelta = outgoing || messageId <= previous.lastReadInboxMessageId
        ? 0
        : (messageId > previous.lastMessageId ? 1 : 0);
    final next = previous.copyWith(
      unreadCount: previous.unreadCount + unreadDelta,
      lastMessageId: messageId > previous.lastMessageId ? messageId : null,
    );
    // Store the updated entry even when display equality holds: the newer
    // bookkeeping ids must survive, or a partial read's watermark is lost
    // and the next arrival over-counts.
    final displayChanged = next != previous;
    topics[topicId] = next;
    if (displayChanged) notifyListeners();
  }

  void _observeForumTopic(
    int slot,
    int? chatId,
    int? topicId,
    int? lastReadInboxMessageId,
    Map<String, dynamic>? notificationSettings,
  ) {
    if (chatId == null || topicId == null) return;
    final topics = _topics[(slot, chatId)];
    final previous = topics?[topicId];
    if (topics == null || previous == null) return;
    var next = previous;
    if (notificationSettings != null) {
      next = next.copyWith(
        isMuted: (notificationSettings.integer('mute_for') ?? 0) > 0,
      );
    }
    if (lastReadInboxMessageId != null &&
        lastReadInboxMessageId > previous.lastReadInboxMessageId) {
      next = next.copyWith(lastReadInboxMessageId: lastReadInboxMessageId);
      // Reading up to the newest known message clears the counter locally; a
      // partial read leaves it until the next topic page confirms the count.
      final readEverything =
          previous.lastMessageId != 0 &&
          lastReadInboxMessageId >= previous.lastMessageId;
      if (readEverything) next = next.copyWith(unreadCount: 0);
    }
    // Persist the new watermark even when nothing displayed moved;
    // otherwise a partial read's progress is dropped and replayed traffic
    // over-counts.
    final displayChanged = next != previous;
    topics[topicId] = next;
    if (displayChanged) notifyListeners();
  }

  void _observeForumTopicInfo(int slot, Map<String, dynamic>? info) {
    final topicId = info?.integer('forum_topic_id');
    if (info == null || topicId == null) return;
    // forumTopicInfo carries its own chat_id (chat-scoped topic ids are
    // not unique across forums); route by that identity instead of
    // guessing from the currently indexed chats.
    final chatId = info.int64('chat_id');
    if (chatId == null) return;
    final previous = _topics[(slot, chatId)]?[topicId];
    if (previous == null) return;
    final icon = info.obj('icon');
    final name = info.str('name');
    if (name == null || name.isEmpty) return;
    final next = previous.copyWith(
      name: name,
      iconCustomEmojiId:
          icon?.int64('custom_emoji_id') ?? previous.iconCustomEmojiId,
      iconColor: icon?.integer('color') ?? previous.iconColor,
    );
    if (next == previous) return;
    _topics[(slot, chatId)]![topicId] = next;
    notifyListeners();
  }

  void clearSlot(int slot) {
    final hadAny =
        _topicChats.containsKey(slot) ||
        _topics.keys.any((key) => key.$1 == slot);
    _topics.removeWhere((key, _) => key.$1 == slot);
    _topicChats.remove(slot);
    if (hadAny) notifyListeners();
  }

  void clear() {
    _topics.clear();
    _topicChats.clear();
  }
}
