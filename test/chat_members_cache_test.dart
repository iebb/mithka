//
//  chat_members_cache_test.dart
//
//  Switching back to an already-opened group should not replay
//  getSupergroupMembers plus a getUser per member. These pin the cache that
//  makes the strip paint immediately, and the guards that keep it honest.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_info_view.dart';
import 'package:mithka/chat/chat_members_cache.dart';

ChatMember member(int id) => ChatMember(id, 'User $id', null);

List<ChatMember> members(int count) =>
    List.generate(count, (index) => member(index + 1));

void main() {
  setUp(ChatMembersCache.shared.clear);

  group('ChatMembersCache', () {
    test('never serves one account the strip cached for another', () {
      final cache = ChatMembersCache();
      cache.store(
        accountSlot: 0,
        chatId: 42,
        members: members(3),
        memberCount: 3,
      );
      expect(cache.read(accountSlot: 1, chatId: 42), isNull);
    });

    test('clearSlot leaves the other account untouched', () {
      final cache = ChatMembersCache();
      for (final slot in [0, 1]) {
        cache.store(
          accountSlot: slot,
          chatId: 42,
          members: members(1),
          memberCount: 1,
        );
      }
      cache.clearSlot(0);
      expect(cache.read(accountSlot: 0, chatId: 42), isNull);
      expect(cache.read(accountSlot: 1, chatId: 42), isNotNull);
    });
  });
}
