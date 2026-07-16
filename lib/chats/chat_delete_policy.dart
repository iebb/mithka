import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';

enum ChatDeleteScope { self, allUsers }

class ChatDeleteCapabilities {
  const ChatDeleteCapabilities({
    required this.canDeleteForSelf,
    required this.canDeleteForAllUsers,
  });

  const ChatDeleteCapabilities.selfOnly()
    : canDeleteForSelf = true,
      canDeleteForAllUsers = false;

  final bool canDeleteForSelf;
  final bool canDeleteForAllUsers;

  bool get canDelete => canDeleteForSelf || canDeleteForAllUsers;
}

ChatDeleteCapabilities chatDeleteCapabilities(Map<String, dynamic> chat) {
  final self = chat.boolean('can_be_deleted_only_for_self');
  final allUsers = chat.boolean('can_be_deleted_for_all_users');
  if (self == null && allUsers == null) {
    // Compatibility with older TDLib responses which predate these fields.
    return const ChatDeleteCapabilities.selfOnly();
  }
  return ChatDeleteCapabilities(
    canDeleteForSelf: self ?? false,
    canDeleteForAllUsers: allUsers ?? false,
  );
}

Map<String, dynamic> deleteChatHistoryRequest({
  required int chatId,
  required ChatDeleteScope scope,
}) => {
  '@type': 'deleteChatHistory',
  'chat_id': chatId,
  'remove_from_chat_list': true,
  'revoke': scope == ChatDeleteScope.allUsers,
};

bool shouldLeaveBeforeDeletingChat(ChatKind kind, ChatDeleteScope scope) {
  return scope == ChatDeleteScope.self &&
      (kind == ChatKind.group || kind == ChatKind.channel);
}
