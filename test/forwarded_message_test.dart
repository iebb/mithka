import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('TDLib keeps the original channel message target for forwards', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 71,
      'chat_id': 9,
      'date': 1,
      'is_outgoing': false,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 12},
      'forward_info': {
        '@type': 'messageForwardInfo',
        'origin': {
          '@type': 'messageOriginChannel',
          'chat_id': -44,
          'message_id': 880,
          'author_signature': '',
        },
      },
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': 'Forwarded post',
          'entities': <Map<String, dynamic>>[],
        },
      },
    });

    expect(message, isNotNull);
    expect(message!.forwardFromChatId, -44);
    expect(message.forwardFromMessageId, 880);
    expect(message.hasForwardAttribution, isTrue);
  });

  test('TDLib keeps the original group chat for forwards', () {
    final message = TDParse.message({
      '@type': 'message',
      'id': 73,
      'chat_id': 9,
      'date': 1,
      'is_outgoing': false,
      'sender_id': {'@type': 'messageSenderUser', 'user_id': 12},
      'forward_info': {
        '@type': 'messageForwardInfo',
        'origin': {
          '@type': 'messageOriginChat',
          'sender_chat_id': -55,
          'author_signature': 'Original author',
        },
      },
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': 'Forwarded group message',
          'entities': <Map<String, dynamic>>[],
        },
      },
    });

    expect(message, isNotNull);
    expect(message!.forwardFromChatId, -55);
    expect(message.forwardDisplayName, 'Original author');
    expect(message.hasForwardAttribution, isTrue);
  });

  testWidgets(
    'forward attribution is visible immediately and opens its source',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);
      var opened = false;
      final message =
          ChatMessage(
              id: 72,
              isOutgoing: false,
              text: 'Forwarded post',
              date: 1,
            )
            ..forwardOrigin = 'Source channel'
            ..forwardFromChatId = -44
            ..forwardFromMessageId = 880;

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Chat',
                isGroup: true,
                onOpenForwarded: (_) => opened = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final header = find.byKey(const ValueKey('messageForwardHeader-72'));
      expect(header, findsOneWidget);
      await tester.tap(header);
      expect(opened, isTrue);
    },
  );
}
