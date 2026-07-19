import 'dart:collection';

import '../tdlib/td_models.dart';
import 'chat_first_contact_info.dart';

class ChatSessionRenderState {
  const ChatSessionRenderState({
    required this.messages,
    required this.anchoredHistory,
    required this.olderHistoryExhausted,
    this.firstContactInfo,
  });

  final List<ChatMessage> messages;
  final bool anchoredHistory;
  final bool olderHistoryExhausted;
  final ChatFirstContactInfo? firstContactInfo;
}

/// Small in-memory LRU used to paint previously opened chats immediately.
class ChatSessionCache {
  ChatSessionCache({this.capacity = 24}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<int, ChatSessionRenderState> _states =
      LinkedHashMap<int, ChatSessionRenderState>();

  ChatSessionRenderState? read(int chatId) {
    final state = _states.remove(chatId);
    if (state != null) _states[chatId] = state;
    return state;
  }

  void store({
    required int chatId,
    required List<ChatMessage> messages,
    required bool anchoredHistory,
    bool olderHistoryExhausted = false,
    ChatFirstContactInfo? firstContactInfo,
  }) {
    _states.remove(chatId);
    if (messages.isEmpty) return;
    _states[chatId] = ChatSessionRenderState(
      messages: List<ChatMessage>.unmodifiable(messages),
      anchoredHistory: anchoredHistory,
      olderHistoryExhausted: olderHistoryExhausted,
      firstContactInfo: firstContactInfo,
    );
    while (_states.length > capacity) {
      _states.remove(_states.keys.first);
    }
  }

  void clear() => _states.clear();
}
