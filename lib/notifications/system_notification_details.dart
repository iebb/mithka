import 'package:flutter_local_notifications/flutter_local_notifications.dart';

NotificationDetails systemNotificationDetailsForChatIcon(
  String? chatIconPath, {
  String? conversationTitle,
  String? messageBody,
  bool groupConversation = false,
  bool playSound = true,
  bool showOnLockScreen = true,
}) {
  final hasChatIcon = chatIconPath != null && chatIconPath.isNotEmpty;
  final sender = Person(
    name: conversationTitle,
    key: conversationTitle,
    icon: hasChatIcon ? BitmapFilePathAndroidIcon(chatIconPath) : null,
  );
  final messagingStyle = conversationTitle != null && messageBody != null
      ? MessagingStyleInformation(
          const Person(name: 'You', key: 'self'),
          conversationTitle: conversationTitle,
          groupConversation: groupConversation,
          messages: [Message(messageBody, DateTime.now(), sender)],
        )
      : null;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'Incoming Mithka messages',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      playSound: playSound,
      visibility: showOnLockScreen
          ? NotificationVisibility.private
          : NotificationVisibility.secret,
      largeIcon: hasChatIcon ? FilePathAndroidBitmap(chatIconPath) : null,
      styleInformation: messagingStyle,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: playSound,
    ),
  );
}
