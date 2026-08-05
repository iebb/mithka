//
//  chat_members_cache.dart
//
//  Resolving a group's member strip costs one getSupergroupMembers plus a
//  getUser per member, awaited in sequence. Paying that again every time the
//  user switches back to a chat they already opened is the whole reason the
//  strip appears to rebuild itself. Keep the resolved list per chat so a
//  revisit paints immediately and the network pass only revalidates.
//

import 'dart:collection';

import 'chat_info_view.dart' show ChatMember;

class ChatMembersSnapshot {
  const ChatMembersSnapshot({required this.members, required this.memberCount});

  final List<ChatMember> members;

  /// The group's full size, which is larger than [members] — the strip only
  /// resolves the first page.
  final int memberCount;
}

/// Small in-memory LRU of resolved member strips, keyed per account so two
/// signed-in accounts that share a chat id never read each other's entries.
class ChatMembersCache {
  ChatMembersCache({this.capacity = 32}) : assert(capacity > 0);

  static final ChatMembersCache shared = ChatMembersCache();

  final int capacity;
  final LinkedHashMap<({int accountSlot, int chatId}), ChatMembersSnapshot>
  _entries =
      LinkedHashMap<({int accountSlot, int chatId}), ChatMembersSnapshot>();

  ChatMembersSnapshot? read({required int accountSlot, required int chatId}) {
    final key = (accountSlot: accountSlot, chatId: chatId);
    final entry = _entries.remove(key);
    if (entry != null) _entries[key] = entry;
    return entry;
  }

  void store({
    required int accountSlot,
    required int chatId,
    required List<ChatMember> members,
    required int memberCount,
  }) {
    final key = (accountSlot: accountSlot, chatId: chatId);
    _entries.remove(key);
    // An empty resolve is usually a failed or permission-denied page rather
    // than a genuinely empty group; caching it would pin the blank state.
    if (members.isEmpty) return;
    _entries[key] = ChatMembersSnapshot(
      members: List<ChatMember>.unmodifiable(members),
      memberCount: memberCount,
    );
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void invalidate({required int accountSlot, required int chatId}) =>
      _entries.remove((accountSlot: accountSlot, chatId: chatId));

  void clearSlot(int accountSlot) =>
      _entries.removeWhere((key, _) => key.accountSlot == accountSlot);

  void clear() => _entries.clear();
}
