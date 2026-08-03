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
  final LinkedHashMap<({int accountSlot, int chatId}), ChatSessionRenderState>
  _states =
      LinkedHashMap<({int accountSlot, int chatId}), ChatSessionRenderState>();

  ChatSessionRenderState? read({
    required int accountSlot,
    required int chatId,
  }) {
    final key = (accountSlot: accountSlot, chatId: chatId);
    final state = _states.remove(key);
    if (state != null) _states[key] = state;
    return state;
  }

  void store({
    required int accountSlot,
    required int chatId,
    required List<ChatMessage> messages,
    required bool anchoredHistory,
    bool olderHistoryExhausted = false,
    ChatFirstContactInfo? firstContactInfo,
  }) {
    final key = (accountSlot: accountSlot, chatId: chatId);
    _states.remove(key);
    if (messages.isEmpty) return;
    _states[key] = ChatSessionRenderState(
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
