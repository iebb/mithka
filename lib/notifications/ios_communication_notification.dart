import 'package:flutter/services.dart';

/// Schedules iOS 15+ communication notifications through native SiriKit APIs.
///
/// A regular [DarwinNotificationAttachment] is expanded notification media; it
/// does not become the circular conversation avatar. Native code must enrich
/// the notification with an `INSendMessageIntent` for that presentation.
class IOSCommunicationNotificationBridge {
  const IOSCommunicationNotificationBridge({
    this.channel = const MethodChannel('mithka/communication_notifications'),
  });

  final MethodChannel channel;

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String conversationIdentifier,
    required String senderName,
    required String payload,
    required bool groupConversation,
    required bool playSound,
    required int chatId,
    String? chatIconPath,
  }) => channel.invokeMethod<void>('show', {
    'id': id,
    'title': title,
    'body': body,
    'conversation_identifier': conversationIdentifier,
    'sender_name': senderName,
    'payload': payload,
    'group_conversation': groupConversation,
    'play_sound': playSound,
    'chat_id': chatId,
    if (chatIconPath != null && chatIconPath.isNotEmpty)
      'chat_icon_path': chatIconPath,
  });

  Future<bool> cacheChatIcon({
    required int chatId,
    required String path,
  }) async {
    if (path.isEmpty) return false;
    try {
      return await channel.invokeMethod<bool>('cacheChatIcon', {
            'chat_id': chatId,
            'chat_icon_path': path,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
