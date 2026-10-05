import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/music_history.dart';

void main() {
  test('played music chats are deduplicated and ordered by recency', () {
    final updated = updatePlayedMusicChats(
      const [
        PlayedMusicChat(chatId: 1, title: 'Older title', lastPlayedAt: 10),
        PlayedMusicChat(chatId: 2, title: 'Second chat', lastPlayedAt: 20),
      ],
      const PlayedMusicChat(
        chatId: 1,
        title: 'Updated title',
        lastPlayedAt: 30,
      ),
    );

    expect(updated.map((chat) => chat.chatId), [1, 2]);
    expect(updated.first.title, 'Updated title');
  });

  test(
    'played music chat persistence ignores malformed and duplicate rows',
    () {
      final encoded = encodePlayedMusicChats(const [
        PlayedMusicChat(chatId: 7, title: 'First', lastPlayedAt: 100),
        PlayedMusicChat(chatId: 8, title: 'Second', lastPlayedAt: 200),
        PlayedMusicChat(chatId: 7, title: 'Duplicate', lastPlayedAt: 300),
      ]);

      final decoded = decodePlayedMusicChats([...encoded, 'not-json']);

      expect(decoded.map((chat) => chat.chatId), [8, 7]);
      expect(decoded.last.title, 'First');
    },
  );

  test('played music chats are capped at the persistence limit', () {
    final existing = List.generate(
      playedMusicChatsLimit,
      (i) => PlayedMusicChat(chatId: i + 1, title: 'Chat $i', lastPlayedAt: i),
    );

    final updated = updatePlayedMusicChats(
      existing,
      const PlayedMusicChat(chatId: 999, title: 'New chat', lastPlayedAt: 1000),
    );

    expect(updated, hasLength(playedMusicChatsLimit));
    expect(updated.first.chatId, 999);
    // Oldest entries fall off the end to make room for the new one.
    expect(updated.map((chat) => chat.chatId), isNot(contains(1)));
    expect(updated.last.lastPlayedAt, lessThan(updated.first.lastPlayedAt));
  });
}
