//
//  chat_description_cache.dart
//
//  A supergroup's or channel's description only ever comes from
//  getSupergroupFullInfo, and Telegram flood-limits that method: TDLib answers
//  a limited query once the wait is over, 30 seconds or more later. An info
//  page that waits for it shows no description at all in the meantime, so keep
//  the last known text per chat and paint it while the fresh copy is in flight.
//

import 'dart:collection';

import 'package:shared_preferences/shared_preferences.dart';

/// Last known group and channel descriptions, keyed per account slot so two
/// signed-in accounts that share a chat id never read each other's text.
class ChatDescriptionCache {
  ChatDescriptionCache({this.capacity = 64}) : assert(capacity > 0);

  static final ChatDescriptionCache shared = ChatDescriptionCache();

  static const _preferencePrefix = 'mithka.chatDescription.v1';

  /// Hot front for the most recently read chats. The persisted copy survives a
  /// restart, this one keeps a revisit inside a session off the disk read.
  final int capacity;
  final LinkedHashMap<({int accountSlot, int chatId}), String> _entries =
      LinkedHashMap<({int accountSlot, int chatId}), String>();

  Future<String?> read({required int accountSlot, required int chatId}) async {
    final key = (accountSlot: accountSlot, chatId: chatId);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_preferenceKey(key));
    if (stored == null || stored.isEmpty) return null;
    _retain(key, stored);
    return stored;
  }

  /// Remembers [description]. An empty text forgets the chat instead, so a
  /// description cleared on the server never survives here as a stale card.
  Future<void> store({
    required int accountSlot,
    required int chatId,
    required String description,
  }) async {
    final key = (accountSlot: accountSlot, chatId: chatId);
    final text = description.trim();
    final preferences = await SharedPreferences.getInstance();
    if (text.isEmpty) {
      _entries.remove(key);
      await preferences.remove(_preferenceKey(key));
      return;
    }
    if (_entries[key] == text &&
        preferences.getString(_preferenceKey(key)) == text) {
      // Unchanged: touch the recency order without writing to disk again.
      _retain(key, text);
      return;
    }
    _retain(key, text);
    await preferences.setString(_preferenceKey(key), text);
  }

  /// Drops every account's descriptions. Slots are reused by whoever signs in
  /// next, so a leftover text could otherwise surface under another account's
  /// chat.
  Future<void> clear() async {
    _entries.clear();
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences
        .getKeys()
        .where((key) => key.startsWith(_preferencePrefix))
        .toList();
    for (final key in keys) {
      await preferences.remove(key);
    }
  }

  void _retain(({int accountSlot, int chatId}) key, String text) {
    _entries.remove(key);
    _entries[key] = text;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  static String _preferenceKey(({int accountSlot, int chatId}) key) =>
      '$_preferencePrefix.slot.${key.accountSlot}.chat.${key.chatId}';
}
