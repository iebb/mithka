import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/app_localizations.dart';

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
          Person(
            name: AppStrings.t(AppStringKeys.notificationSelfSenderName),
            key: 'self',
          ),
          conversationTitle: conversationTitle,
          groupConversation: groupConversation,
          messages: [Message(messageBody, DateTime.now(), sender)],
        )
      : null;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      'messages',
      AppStrings.t(AppStringKeys.notificationChannelMessagesName),
      channelDescription: AppStrings.t(
        AppStringKeys.notificationChannelMessagesDescription,
      ),
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
