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
    test('returns a stored strip for the same account and chat', () {
      final cache = ChatMembersCache();
      cache.store(
        accountSlot: 0,
        chatId: 42,
        members: members(3),
        memberCount: 180,
      );

      final hit = cache.read(accountSlot: 0, chatId: 42);
      expect(hit, isNotNull);
      expect(hit!.members.map((m) => m.id), [1, 2, 3]);
      expect(hit.memberCount, 180);
    });

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

    test('misses on a chat that was never stored', () {
      final cache = ChatMembersCache();
      cache.store(
        accountSlot: 0,
        chatId: 42,
        members: members(1),
        memberCount: 1,
      );
      expect(cache.read(accountSlot: 0, chatId: 43), isNull);
    });

    test('does not cache an empty resolve', () {
      // A failed or permission-denied page comes back empty; caching it would
      // pin a blank strip that only a restart could clear.
      final cache = ChatMembersCache();
      cache.store(
        accountSlot: 0,
        chatId: 42,
        members: const [],
        memberCount: 0,
      );
      expect(cache.read(accountSlot: 0, chatId: 42), isNull);
    });

    test('a later empty store drops the previous strip', () {
      final cache = ChatMembersCache();
      cache.store(
        accountSlot: 0,
        chatId: 42,
        members: members(2),
        memberCount: 2,
      );
      cache.store(
        accountSlot: 0,
        chatId: 42,
        members: const [],
        memberCount: 0,
      );
      expect(cache.read(accountSlot: 0, chatId: 42), isNull);
    });

    test('stored strips are unmodifiable', () {
      final cache = ChatMembersCache();
      cache.store(
        accountSlot: 0,
        chatId: 42,
        members: members(2),
        memberCount: 2,
      );
      final hit = cache.read(accountSlot: 0, chatId: 42)!;
      expect(() => hit.members.add(member(9)), throwsUnsupportedError);
    });

    test('a mutated source list does not rewrite the stored strip', () {
      final cache = ChatMembersCache();
      final source = members(2);
      cache.store(accountSlot: 0, chatId: 42, members: source, memberCount: 2);
      source.add(member(3));
      expect(cache.read(accountSlot: 0, chatId: 42)!.members, hasLength(2));
    });

    test('evicts the least recently used chat past capacity', () {
      final cache = ChatMembersCache(capacity: 2);
      for (final chatId in [1, 2, 3]) {
        cache.store(
          accountSlot: 0,
          chatId: chatId,
          members: members(1),
          memberCount: 1,
        );
      }
      expect(cache.read(accountSlot: 0, chatId: 1), isNull);
      expect(cache.read(accountSlot: 0, chatId: 2), isNotNull);
      expect(cache.read(accountSlot: 0, chatId: 3), isNotNull);
    });

    test('a read renews a chat against eviction', () {
      final cache = ChatMembersCache(capacity: 2);
      for (final chatId in [1, 2]) {
        cache.store(
          accountSlot: 0,
          chatId: chatId,
          members: members(1),
          memberCount: 1,
        );
      }
      cache.read(accountSlot: 0, chatId: 1); // 2 is now the oldest
      cache.store(
        accountSlot: 0,
        chatId: 3,
        members: members(1),
        memberCount: 1,
      );
      expect(cache.read(accountSlot: 0, chatId: 1), isNotNull);
      expect(cache.read(accountSlot: 0, chatId: 2), isNull);
    });

    test('invalidate drops one chat and leaves the rest', () {
      final cache = ChatMembersCache();
      for (final chatId in [1, 2]) {
        cache.store(
          accountSlot: 0,
          chatId: chatId,
          members: members(1),
          memberCount: 1,
        );
      }
      cache.invalidate(accountSlot: 0, chatId: 1);
      expect(cache.read(accountSlot: 0, chatId: 1), isNull);
      expect(cache.read(accountSlot: 0, chatId: 2), isNotNull);
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

  group('ChatInfoViewModel', () {
    test('paints a cached strip before any network work', () {
      ChatMembersCache.shared.store(
        accountSlot: 0,
        chatId: 77,
        members: members(4),
        memberCount: 250,
      );

      final model = ChatInfoViewModel(chatId: 77, title: 'Group');
      expect(model.members, isEmpty);

      model.load();

      // Synchronous: the strip is on screen in the first frame after load,
      // which is the whole point — no await, no round-trip.
      expect(model.members.map((m) => m.id), [1, 2, 3, 4]);
      expect(model.memberCount, 250);
      model.dispose();
    });

    test('starts empty for a chat that was never opened', () {
      final model = ChatInfoViewModel(chatId: 78, title: 'Group');
      model.load();
      expect(model.members, isEmpty);
      model.dispose();
    });
  });
}
