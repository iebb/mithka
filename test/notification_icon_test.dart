import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/system_notification_details.dart';

void main() {
  test('system notification details use the chat photo on each platform', () {
    final details = systemNotificationDetailsForChatIcon(
      '/tmp/chat.jpg',
      conversationTitle: 'Alice',
      messageBody: 'Hello',
    );

    final androidIcon = details.android?.largeIcon;
    expect(androidIcon, isA<FilePathAndroidBitmap>());
    expect((androidIcon as FilePathAndroidBitmap).data, '/tmp/chat.jpg');
    final style = details.android?.styleInformation;
    expect(style, isA<MessagingStyleInformation>());
    final messagingStyle = style! as MessagingStyleInformation;
    expect(messagingStyle.conversationTitle, 'Alice');
    expect(messagingStyle.groupConversation, isFalse);
    expect(messagingStyle.messages, hasLength(1));
    expect(messagingStyle.messages!.single.text, 'Hello');
    expect(
      messagingStyle.messages!.single.person?.icon,
      isA<BitmapFilePathAndroidIcon>(),
    );
    // iOS conversation avatars are supplied through INSendMessageIntent by
    // the native bridge. A Darwin attachment is only expanded rich media.
    expect(details.iOS?.attachments, isNull);
  });

  test('system notification details identify group conversations', () {
    final details = systemNotificationDetailsForChatIcon(
      '/tmp/group.jpg',
      conversationTitle: 'Family',
      messageBody: 'Dinner is ready',
      groupConversation: true,
    );

    final style =
        details.android?.styleInformation as MessagingStyleInformation;
    expect(style.groupConversation, isTrue);
  });

  test('system notification details keep the default icon as fallback', () {
    final details = systemNotificationDetailsForChatIcon(null);

    expect(details.android?.largeIcon, isNull);
    expect(details.iOS?.attachments, isNull);
  });

  test('system notification details honor sound and lock-screen privacy', () {
    final details = systemNotificationDetailsForChatIcon(
      null,
      playSound: false,
      showOnLockScreen: false,
    );

    expect(details.android?.playSound, isFalse);
    expect(details.android?.visibility, NotificationVisibility.secret);
    expect(details.iOS?.presentSound, isFalse);
  });
}
