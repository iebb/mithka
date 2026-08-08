//
//  search_token_suggestions.dart
//
//  What to offer while a `in:` or `from:` token is being typed.
//
//  `in:` always means a chat, so it draws on the chat list. `from:` means a
//  sender, and what counts as a plausible sender depends on whether the search
//  is already scoped: inside one chat it is that chat's participants, and
//  across the whole account it is the people the chat list already knows.
//

import '../chat/chat_search_query.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

/// One row in the token suggestion list.
class ChatSearchTokenSuggestion {
  const ChatSearchTokenSuggestion({
    required this.id,
    required this.title,
    required this.token,
    this.subtitle,
    this.photo,
  });

  final int id;
  final String title;

  /// What gets written into the field when this row is picked. A username is
  /// preferred over a display name — it is unambiguous and survives renames.
  final String token;
  final String? subtitle;
  final TdFileRef? photo;
}

/// Resolves suggestions for the token the caret is in.
class ChatSearchTokenSuggester {
  ChatSearchTokenSuggester({TdClient? client})
    : _client = client ?? TdClient.shared;

  static const int _limit = 8;

  final TdClient _client;

  Future<List<ChatSearchTokenSuggestion>> suggest(
    ChatSearchActiveToken token, {
    int? scopeChatId,
  }) => switch (token.kind) {
    ChatSearchTokenKind.chat => _chats(token.value),
    ChatSearchTokenKind.from => _senders(token.value, scopeChatId),
  };

  /// Chats for `in:`. An empty token offers the top of the chat list, so the
  /// affordance is useful before anything is typed.
  Future<List<ChatSearchTokenSuggestion>> _chats(String query) async {
    try {
      final response = await _client.query(
        query.isEmpty
            ? {
                '@type': 'getChats',
                'chat_list': {'@type': 'chatListMain'},
                'limit': _limit,
              }
            : {
                '@type': 'searchChats',
                'query': query,
                'type_filter': null,
                'limit': _limit,
              },
      );
      final ids = (response.int64Array('chat_ids') ?? const <int>[])
          .take(_limit)
          .toList(growable: false);
      // One round trip per id, but all in flight at once — Future.wait keeps
      // index order, so the suggestion order is still the server's.
      final chats = await Future.wait(ids.map(_chatSummary));
      final out = <ChatSearchTokenSuggestion>[];
      for (var i = 0; i < ids.length; i++) {
        final chat = chats[i];
        if (chat == null) continue;
        out.add(
          ChatSearchTokenSuggestion(
            id: ids[i],
            title: chat.title,
            token: chat.title,
            photo: chat.photo,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<ChatSummary?> _chatSummary(int chatId) async {
    try {
      final chat = await _client.query({'@type': 'getChat', 'chat_id': chatId});
      return TDParse.chat(chat);
    } catch (_) {
      return null;
    }
  }

  /// Senders for `from:`.
  ///
  /// An `@username` is taken at its word and resolved directly, which is the
  /// only way to name someone the chat cannot enumerate. Otherwise a scoped
  /// search asks the chat for matching members, and falls back to the senders
  /// actually present in its history — a group that hides its member list
  /// still has authors on its messages.
  Future<List<ChatSearchTokenSuggestion>> _senders(
    String query,
    int? scopeChatId,
  ) async {
    if (query.startsWith('@') && query.length > 1) {
      final resolved = await _username(query.substring(1));
      if (resolved != null) return [resolved];
    }
    if (scopeChatId != null) {
      final members = await _chatMembers(scopeChatId, query);
      if (members.isNotEmpty) return members;
      return _historySenders(scopeChatId, query);
    }
    return _contacts(query);
  }

  Future<ChatSearchTokenSuggestion?> _username(String username) async {
    try {
      final chat = await _client.query({
        '@type': 'searchPublicChat',
        'username': username,
      });
      final summary = TDParse.chat(chat);
      final userId = summary?.peerUserId;
      if (summary == null || userId == null) return null;
      return ChatSearchTokenSuggestion(
        id: userId,
        title: summary.title,
        token: '@$username',
        subtitle: '@$username',
        photo: summary.photo,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ChatSearchTokenSuggestion>> _chatMembers(
    int chatId,
    String query,
  ) async {
    try {
      final response = await _client.query({
        '@type': 'searchChatMembers',
        'chat_id': chatId,
        'query': query,
        'limit': _limit,
        'filter': null,
      });
      final members = response.objects('members') ?? const [];
      final userIds = <int>[];
      for (final member in members) {
        final sender = member.obj('member_id');
        if (sender?.type != 'messageSenderUser') continue;
        final userId = sender?.int64('user_id');
        if (userId == null || userId == 0) continue;
        userIds.add(userId);
      }
      final resolved = await Future.wait(userIds.map(_user));
      return resolved.whereType<ChatSearchTokenSuggestion>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Distinct authors of the chat's recent messages.
  ///
  /// This is the fallback for a chat whose members cannot be listed. It reads
  /// history rather than membership, so anyone who has actually spoken is
  /// offerable even when the member list is hidden.
  Future<List<ChatSearchTokenSuggestion>> _historySenders(
    int chatId,
    String query,
  ) async {
    try {
      final response = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': '',
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 100,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
      });
      final messages = response.objects('messages') ?? const [];
      final seen = <int>{};
      final senderIds = <int>[];
      for (final raw in messages) {
        final sender = raw.obj('sender_id');
        if (sender?.type != 'messageSenderUser') continue;
        final userId = sender?.int64('user_id');
        if (userId == null || userId == 0 || !seen.add(userId)) continue;
        senderIds.add(userId);
      }
      // The needle is matched against the resolved name, so every distinct
      // sender has to be fetched anyway — fetch them concurrently.
      final resolved = await Future.wait(senderIds.map(_user));
      final out = <ChatSearchTokenSuggestion>[];
      final needle = query.toLowerCase();
      for (final suggestion in resolved) {
        if (out.length >= _limit) break;
        if (suggestion == null) continue;
        if (needle.isNotEmpty &&
            !suggestion.title.toLowerCase().contains(needle) &&
            !(suggestion.subtitle ?? '').toLowerCase().contains(needle)) {
          continue;
        }
        out.add(suggestion);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<ChatSearchTokenSuggestion>> _contacts(String query) async {
    try {
      final response = await _client.query({
        '@type': 'searchContacts',
        'query': query,
        'limit': _limit,
      });
      final ids = response.int64Array('user_ids') ?? const <int>[];
      final resolved = await Future.wait(ids.take(_limit).map(_user));
      return resolved.whereType<ChatSearchTokenSuggestion>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<ChatSearchTokenSuggestion?> _user(int userId) async {
    try {
      final user = await _client.query({'@type': 'getUser', 'user_id': userId});
      final name = TDParse.userName(user);
      final username = TDParse.activeUsernames(user).firstOrNull;
      return ChatSearchTokenSuggestion(
        id: userId,
        title: name,
        // A username is stable and unambiguous; a display name is neither, so
        // it is only the token when there is nothing better.
        token: username == null || username.isEmpty ? name : '@$username',
        subtitle: username == null || username.isEmpty ? null : '@$username',
        photo: TDParse.smallPhoto(user.obj('profile_photo')),
      );
    } catch (_) {
      return null;
    }
  }
}
