import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/ios_communication_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native iOS bridge receives conversation and chat avatar metadata',
    () async {
      const channel = MethodChannel('mithka/test_communication_notifications');
      const bridge = IOSCommunicationNotificationBridge(channel: channel);
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await bridge.show(
        id: 42,
        title: 'Family',
        body: 'Dinner is ready',
        conversationIdentifier: '2:-100123',
        senderName: 'Alice',
        payload: '{"chat_id":-100123,"message_id":8}',
        groupConversation: true,
        playSound: false,
        chatIconPath: '/tmp/family.jpg',
      );

      expect(received?.method, 'show');
      expect(received?.arguments, {
        'id': 42,
        'title': 'Family',
        'body': 'Dinner is ready',
        'conversation_identifier': '2:-100123',
        'sender_name': 'Alice',
        'payload': '{"chat_id":-100123,"message_id":8}',
        'group_conversation': true,
        'play_sound': false,
        'chat_icon_path': '/tmp/family.jpg',
      });
    },
  );

  test('native iOS bridge omits an unavailable chat avatar', () async {
    const channel = MethodChannel('mithka/test_communication_no_avatar');
    const bridge = IOSCommunicationNotificationBridge(channel: channel);
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await bridge.show(
      id: 7,
      title: 'Alice',
      body: 'Hello',
      conversationIdentifier: '0:99',
      senderName: 'Alice',
      payload: '{"chat_id":99}',
      groupConversation: false,
      playSound: true,
    );

    expect((received?.arguments as Map)['chat_icon_path'], isNull);
  });
}
