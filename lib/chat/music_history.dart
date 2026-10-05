import 'dart:convert';

/// Cap for the persisted recently-played chats list; older entries beyond
/// this many are dropped on every update.
const playedMusicChatsLimit = 20;

class PlayedMusicChat {
  const PlayedMusicChat({
    required this.chatId,
    required this.title,
    required this.lastPlayedAt,
  });

  final int chatId;
  final String title;
  final int lastPlayedAt;

  Map<String, Object> toJson() => {
    'chat_id': chatId,
    'title': title,
    'last_played_at': lastPlayedAt,
  };

  static PlayedMusicChat? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final chatId = _asInt(value['chat_id']);
    final title = value['title']?.toString().trim() ?? '';
    final lastPlayedAt = _asInt(value['last_played_at']);
    if (chatId == null || chatId == 0 || title.isEmpty) return null;
    return PlayedMusicChat(
      chatId: chatId,
      title: title,
      lastPlayedAt: lastPlayedAt ?? 0,
    );
  }
}

List<PlayedMusicChat> updatePlayedMusicChats(
  Iterable<PlayedMusicChat> existing,
  PlayedMusicChat played, {
  int limit = playedMusicChatsLimit,
}) {
  final updated = <PlayedMusicChat>[
    played,
    for (final item in existing)
      if (item.chatId != played.chatId) item,
  ];
  updated.sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
  if (updated.length > limit) updated.removeRange(limit, updated.length);
  return List.unmodifiable(updated);
}

List<String> encodePlayedMusicChats(Iterable<PlayedMusicChat> chats) =>
    chats.map((chat) => jsonEncode(chat.toJson())).toList(growable: false);

List<PlayedMusicChat> decodePlayedMusicChats(Iterable<String> values) {
  final decoded = <PlayedMusicChat>[];
  final seen = <int>{};
  for (final value in values) {
    try {
      final chat = PlayedMusicChat.fromJson(jsonDecode(value));
      if (chat != null && seen.add(chat.chatId)) decoded.add(chat);
    } catch (_) {}
  }
  decoded.sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
  return List.unmodifiable(decoded);
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
