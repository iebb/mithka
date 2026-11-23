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
    this.isPinned = false,
    this.lastMessageId = 0,
    this.lastReadInboxMessageId = 0,
  });

  final int id;
  final String name;
  final int iconCustomEmojiId;
  final int iconColor;
  final int unreadCount;
  final bool isMuted;

  /// Pinned topics lead the tab strip in their pin order (the page's own
  /// order), the way the reference client keeps them in `TopicsController.sortTopics`.
  final bool isPinned;

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
    bool? isPinned,
    int? lastMessageId,
    int? lastReadInboxMessageId,
  }) => ForumTopicIndexEntry(
    id: id,
    name: name ?? this.name,
    iconCustomEmojiId: iconCustomEmojiId ?? this.iconCustomEmojiId,
    iconColor: iconColor ?? this.iconColor,
    unreadCount: unreadCount ?? this.unreadCount,
    isMuted: isMuted ?? this.isMuted,
    isPinned: isPinned ?? this.isPinned,
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
      other.isMuted == isMuted &&
      other.isPinned == isPinned;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    iconCustomEmojiId,
    iconColor,
    unreadCount,
    isMuted,
    isPinned,
  );

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
      isPinned: raw.boolean('is_pinned') ?? false,
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

/// Sorts the topics of one chat into display order without disturbing the
/// map's own order, which is the server's order (pinned topics in pin order).
///
/// Mirrors the reference client `TopicsController.sortTopics`: pinned first in pin
/// order, everything else by the newest activity. See [orderForumTopics].
List<ForumTopicIndexEntry> _inDisplayOrder(
  Map<int, ForumTopicIndexEntry> entries,
) => orderForumTopics(
  entries.values,
  isPinned: (entry) => entry.isPinned,
  lastMessageId: (entry) => entry.lastMessageId,
);

/// Orders topics the way the tab strip paints them: pinned first in the order
/// they already carry (the page's pin order), then newest activity first.
///
/// Telegram message ids are per-chat, so a topic's last message id orders it
/// against its siblings exactly. A topic whose newest message is not known yet
/// (one TDLib announced after the page, or a fresh bot topic) counts as the
/// newest — the same contract [ForumTopicIndex.addTopic] implements by
/// inserting at the head.
///
/// Shared by the index and the view model: a live update that reaches one of
/// them first must not paint a different order than the other.
List<T> orderForumTopics<T>(
  Iterable<T> topics, {
  required bool Function(T topic) isPinned,
  required int Function(T topic) lastMessageId,
}) {
  final decorated = [
    for (final (arrival, topic) in topics.indexed)
      (arrival: arrival, topic: topic),
  ];
  decorated.sort((a, b) {
    final aPinned = isPinned(a.topic);
    if (aPinned != isPinned(b.topic)) return aPinned ? -1 : 1;
    if (!aPinned) {
      final activity = _activityOf(
        lastMessageId(b.topic),
      ).compareTo(_activityOf(lastMessageId(a.topic)));
      if (activity != 0) return activity;
    }
    // Pin order and activity ties fall back to the previous order; List.sort
    // is not stable, so compare the captured slots explicitly.
    return a.arrival.compareTo(b.arrival);
  });
  return [for (final item in decorated) item.topic];
}

const int _unknownActivity = 1 << 62;

int _activityOf(int lastMessageId) =>
    lastMessageId == 0 ? _unknownActivity : lastMessageId;

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

  /// Chats whose topic page has landed at least once (an empty page counts).
  /// A chat outside this set has no known membership yet, so a topic it
  /// announces must wait for its page instead of being inserted.
  final Set<(int, int)> _loadedChats = {};

  /// The topics in display order — the order the tab strip, the rail and the
  /// topic list paint.
  ///
  /// Pinned topics lead, in the order the page laid their pins out; the rest
  /// follow newest-activity-first. A new message moves its topic up without a
  /// `getForumTopics` round-trip, so the strip reorders as traffic lands.
  List<ForumTopicIndexEntry> topicsFor(int slot, int chatId) {
    final entries = _topics[(slot, chatId)];
    if (entries == null) return const [];
    return _inDisplayOrder(entries);
  }

  ForumTopicIndexEntry? entryFor(int slot, int chatId, int topicId) =>
      _topics[(slot, chatId)]?[topicId];

  bool knowsTopics(int slot, int chatId) =>
      (_topics[(slot, chatId)]?.isNotEmpty) ?? false;

  /// Adds a topic the paged list predates — one created by the bot or on
  /// another device after the page loaded. New topics lead the list: they
  /// carry the newest activity, so appending one would park it past a long
  /// tab strip. Returns whether the topic was new to the index.
  ///
  /// Ignored for a chat whose page never landed: its membership is unknown,
  /// and its own page answers first (the page is authoritative).
  bool addTopic(int slot, int chatId, ForumTopicIndexEntry entry) {
    final key = (slot, chatId);
    if (!_loadedChats.contains(key)) return false;
    final topics = _topics[key];
    if (topics != null && topics.containsKey(entry.id)) return false;
    _topics[key] = {entry.id: entry, ...?topics};
    _topicChats.putIfAbsent(slot, () => {}).add(chatId);
    _evictStaleChats();
    notifyListeners();
    return true;
  }

  /// Stores a complete getForumTopics page. The response is authoritative for
  /// both membership (topics deleted elsewhere drop out) and counters.
  void storeAll(int slot, int chatId, List<ForumTopicIndexEntry> entries) {
    final key = (slot, chatId);
    _loadedChats.add(key);
    if (entries.isEmpty) {
      final removed = _topics.remove(key) != null;
      _topicChats[slot]?.remove(chatId);
      if (removed) notifyListeners();
      return;
    }
    var displayChanged = false;
    final previousTopics = _topics[key] ?? const <int, ForumTopicIndexEntry>{};
    // Rebuild in the page's order instead of patching the old map: the page
    // is authoritative for membership AND for the pin order (TDLib returns
    // pinned topics in their pinned order), and [_inDisplayOrder] leans on
    // that order for the pinned block.
    final topics = <int, ForumTopicIndexEntry>{};
    for (final entry in entries) {
      final previous = previousTopics[entry.id];
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
              isPinned: entry.isPinned,
            )
          : entry;
      if (previous != merged) displayChanged = true;
      topics[entry.id] = merged;
    }
    displayChanged |=
        previousTopics.length != topics.length ||
        topics.keys.any((id) => !previousTopics.containsKey(id));
    _topics[key] = topics;
    _topicChats.putIfAbsent(slot, () => {}).add(chatId);
    _evictStaleChats();
    // Chats whose page was empty never enter _topicChats, so bound their
    // bookkeeping separately; a dropped chat re-registers on its next page.
    while (_loadedChats.length > _chatCapacity * 4) {
      _loadedChats.remove(_loadedChats.first);
    }
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
        _loadedChats.remove((slot, chatId));
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
          object.boolean('is_pinned'),
        );
      case 'updateForumTopicInfo':
        _observeForumTopicInfo(slot, object.obj('info'));
    }
  }

  void _observeNewMessage(int slot, Map<String, dynamic>? raw) {
    if (raw == null) return;
    final chatId = raw.int64('chat_id');
    if (chatId == null) return;
    // A message outside any topic belongs to General (id 1) — but only in a
    // real forum supergroup, where TDLib omits `topic_id` there. A bot topic
    // chat has no General topic (id 1 errors) and its messages always carry
    // an explicit reference, so an unattributed message is unattributable,
    // not General. The chat's user kind is not known here, so a bot chat's
    // unscoped arrival updates nothing until it names its topic.
    final topicRef = raw.obj('topic_id');
    final topicId = topicRef?.type == 'messageTopicForum'
        ? topicRef?.integer('forum_topic_id')
        : raw.boolean('is_outgoing') == false && chatId > 0
        ? null
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
    // An outgoing message leaves every counter alone but still moves its
    // topic to the front of the strip, so a newer id counts as a change: it
    // is what [topicsFor] orders by.
    final orderChanged = next.lastMessageId > previous.lastMessageId;
    topics[topicId] = next;
    if (displayChanged || orderChanged) notifyListeners();
  }

  void _observeForumTopic(
    int slot,
    int? chatId,
    int? topicId,
    int? lastReadInboxMessageId,
    Map<String, dynamic>? notificationSettings,
    bool? isPinned,
  ) {
    if (chatId == null || topicId == null) return;
    final topics = _topics[(slot, chatId)];
    final previous = topics?[topicId];
    if (topics == null || previous == null) return;
    var next = previous;
    if (isPinned != null && isPinned != previous.isPinned) {
      next = next.copyWith(isPinned: isPinned);
    }
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
    final icon = info.obj('icon');
    final name = info.str('name');
    if (name == null || name.isEmpty) return;
    final previous = _topics[(slot, chatId)]?[topicId];
    if (previous == null) {
      // TDLib announces every topic it learns about; one the paged list does
      // not carry is new (created by the bot or on another device), not an
      // edit. Insert it so open tabs and topic lists gain it live.
      addTopic(
        slot,
        chatId,
        ForumTopicIndexEntry(
          id: topicId,
          name: name,
          iconCustomEmojiId:
              icon?.int64('custom_emoji_id') ??
              info.int64('icon_custom_emoji_id') ??
              0,
          iconColor: icon?.integer('color') ?? info.integer('icon_color') ?? 0,
        ),
      );
      return;
    }
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

  /// Records that [readMessageId] was successfully marked read for a topic.
  ///
  /// A scoped `viewMessages` with `force_read` advances the topic's inbox
  /// watermark to the viewed message, so the index must remember it: without
  /// this, the next stale getForumTopics page would look newer than the
  /// locally known read state and resurrect a counter the read cleared.
  /// [lastMessageId] is the newest message the caller knew when it read, which
  /// may be newer than the index's own bookkeeping.
  void recordRead(
    int slot,
    int chatId,
    int topicId, {
    required int readMessageId,
    int lastMessageId = 0,
  }) {
    if (readMessageId <= 0) return;
    final topics = _topics[(slot, chatId)];
    final previous = topics?[topicId];
    if (topics == null || previous == null) return;
    var next = previous;
    if (lastMessageId > next.lastMessageId) {
      next = next.copyWith(lastMessageId: lastMessageId);
    }
    if (readMessageId > next.lastReadInboxMessageId) {
      next = next.copyWith(lastReadInboxMessageId: readMessageId);
    }
    // A read that reaches the newest known message clears the counter; a
    // partial read leaves the remainder for the next page to confirm.
    if (next.lastMessageId != 0 &&
        next.lastReadInboxMessageId >= next.lastMessageId &&
        next.unreadCount != 0) {
      next = next.copyWith(unreadCount: 0);
    }
    // Persist the watermark even when nothing displayed moved: it is what
    // keeps a later stale page from regressing the read position.
    final displayChanged = next != previous;
    topics[topicId] = next;
    if (displayChanged) notifyListeners();
  }

  /// Restores [restoreCount] only while the topic still holds the exact read
  /// state captured before an optimistic clear.
  ///
  /// A failed bulk read may roll back only its own topic. If an authoritative
  /// updateForumTopic advanced the watermark (or new traffic moved the newest
  /// message) while the request was in flight, that state wins and nothing is
  /// restored. A null expectation means the index had no entry when the clear
  /// happened; restoring is then only allowed while it still has none.
  bool restoreUnreadCountIfUnmoved(
    int slot,
    int chatId,
    int topicId, {
    required int restoreCount,
    int? expectedUnreadCount,
    int? expectedLastReadInboxMessageId,
    int? expectedLastMessageId,
  }) {
    final topics = _topics[(slot, chatId)];
    final entry = topics?[topicId];
    if (entry == null) {
      return expectedLastReadInboxMessageId == null &&
          expectedLastMessageId == null;
    }
    if (expectedLastReadInboxMessageId == null ||
        expectedLastMessageId == null) {
      // A page or update taught the index this topic mid-batch: its state
      // moved, so the pre-batch counter is no longer trustworthy.
      return false;
    }
    if (entry.lastReadInboxMessageId != expectedLastReadInboxMessageId ||
        entry.lastMessageId != expectedLastMessageId ||
        (expectedUnreadCount != null &&
            entry.unreadCount != expectedUnreadCount)) {
      return false;
    }
    if (entry.unreadCount == restoreCount) return true;
    topics![topicId] = entry.copyWith(unreadCount: _nonNegative(restoreCount));
    notifyListeners();
    return true;
  }

  /// Rewrites the unread counter of the named topics in place. The index is
  /// what every topic surface paints from, so a bulk read must not wait for a
  /// page refresh to show its effect. Returns whether anything changed.
  bool setUnreadCounts(int slot, int chatId, Map<int, int> counts) {
    final topics = _topics[(slot, chatId)];
    if (topics == null || counts.isEmpty) return false;
    var changed = false;
    for (final entry in counts.entries) {
      final previous = topics[entry.key];
      if (previous == null || previous.unreadCount == entry.value) continue;
      topics[entry.key] = previous.copyWith(
        unreadCount: _nonNegative(entry.value),
      );
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
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
