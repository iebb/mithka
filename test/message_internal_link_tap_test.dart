import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/chat/internal_chat_link_router.dart';
import 'package:mithka/chat/link_handler.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const linkedMessageId = 700 << 20;

  late StreamController<Map<String, dynamic>> updates;
  late List<Map<String, dynamic>> requests;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 3,
        accountUserId: 33,
        query: (request) async {
          requests.add(Map<String, dynamic>.from(request));
          return switch (request['@type']) {
            'getInternalLinkType'
                when request['link'] ==
                    'tg://privatepost?channel=4321&post=701' =>
              throw StateError('Simulated unsupported TDLib classification'),
            'getInternalLinkType'
                when request['link'] ==
                    'tg://privatepost?channel=1234&post=700' =>
              <String, dynamic>{
                '@type': 'internalLinkTypeMessage',
                'url': 'https://t.me/c/1234/700',
              },
            'getInternalLinkType'
                when request['link'] == 'https://t.me/safe_hot_bot?start=hot' =>
              <String, dynamic>{
                '@type': 'internalLinkTypeBotStart',
                'bot_username': 'safe_hot_bot',
                'start_parameter': 'hot',
                'autostart': true,
              },
            'getInternalLinkType' => <String, dynamic>{
              '@type': 'internalLinkTypePublicChat',
              'chat_username': 'safe_hot_results',
            },
            'getMessageLinkInfo' => <String, dynamic>{
              '@type': 'messageLinkInfo',
              'chat_id': -1001234,
              'message': <String, dynamic>{
                '@type': 'message',
                'id': linkedMessageId,
                'chat_id': -1001234,
              },
            },
            'getChat' => <String, dynamic>{
              '@type': 'chat',
              'id': request['chat_id'],
              'title': 'Safe hot result',
            },
            'searchPublicChat' => <String, dynamic>{
              '@type': 'chat',
              'id': request['username'] == 'safe_hot_bot' ? 9000 : -1005678,
              'title': request['username'] == 'safe_hot_bot'
                  ? 'Safe hot bot'
                  : 'Safe hot results',
              if (request['username'] == 'safe_hot_bot')
                'type': <String, dynamic>{
                  '@type': 'chatTypePrivate',
                  'user_id': 901,
                },
            },
            'sendBotStartMessage' => <String, dynamic>{'@type': 'message'},
            _ => throw StateError('Unexpected TDLib request: $request'),
          };
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    requests = [];
    ChatDeepLinkController.shared.consumePending();
    SharedPreferences.setMockInitialValues(const {});
  });

  tearDown(ChatDeepLinkController.shared.consumePending);

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets(
    'tapping a message text link opens its canonical target in the source account',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final theme = ThemeController(preferences);
      addTearDown(theme.dispose);
      var selectionDialogCount = 0;
      const label = 'Safe hot result';
      final message = ChatMessage(
        id: 1,
        isOutgoing: false,
        text: label,
        date: 1,
        contentType: 'messageText',
        textEntities: const [
          MessageTextEntity(
            offset: 0,
            length: label.length,
            type: 'textEntityTypeTextUrl',
            url: 'tg://privatepost?channel=1234&post=700',
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: InternalChatLinkScope(
                target: InternalChatLinkTarget(
                  chatId: 42,
                  accountSlot: 3,
                  openMessage: (_) async {},
                ),
                child: MessageBubble(
                  message: message,
                  peerTitle: 'Source chat',
                  isGroup: true,
                  onDoubleTap: (_) => selectionDialogCount += 1,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text(label, findRichText: true));
      await tester.pump();

      expect(selectionDialogCount, 0);
      expect(
        requests.where((request) => request['@type'] == 'getMessageLinkInfo'),
        [
          <String, dynamic>{
            '@type': 'getMessageLinkInfo',
            'url': 'https://t.me/c/1234/700',
          },
        ],
      );
      final opened = ChatDeepLinkController.shared.consumePending();
      expect(opened?.chatId, -1001234);
      expect(opened?.messageId, linkedMessageId);
      expect(opened?.accountSlot, 3);
    },
  );

  test('fallback Telegram post grammars convert to TDLib message IDs', () {
    expect(
      telegramFallbackMessageId('https://t.me/c/1234/700'),
      linkedMessageId,
    );
    expect(
      telegramFallbackMessageId('https://t.me/safe_hot_results/700'),
      linkedMessageId,
    );
    expect(
      telegramFallbackMessageId(
        'tg://resolve?domain=safe_hot_results&post=700',
      ),
      linkedMessageId,
    );
    expect(
      telegramFallbackMessageId('tg://privatepost?channel=1234&post=700'),
      linkedMessageId,
    );
  });

  testWidgets('privatepost falls back to its chat and shifted message ID', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    const label = 'Safe private result';
    final message = ChatMessage(
      id: 4,
      isOutgoing: false,
      text: label,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 0,
          length: label.length,
          type: 'textEntityTypeTextUrl',
          url: 'tg://privatepost?channel=4321&post=701',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: InternalChatLinkScope(
              target: InternalChatLinkTarget(
                chatId: 42,
                accountSlot: 3,
                openMessage: (_) async {},
              ),
              child: MessageBubble(
                message: message,
                peerTitle: 'Source chat',
                isGroup: true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text(label, findRichText: true));
    await tester.pump();

    final opened = ChatDeepLinkController.shared.consumePending();
    expect(opened?.chatId, -1004321);
    expect(opened?.messageId, 701 << 20);
    expect(opened?.accountSlot, 3);
  });

  testWidgets('a public-chat message link keeps the source account scope', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    const label = 'Safe hot results';
    final message = ChatMessage(
      id: 2,
      isOutgoing: false,
      text: label,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 0,
          length: label.length,
          type: 'textEntityTypeTextUrl',
          url: 'https://t.me/safe_hot_results',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: InternalChatLinkScope(
              target: InternalChatLinkTarget(
                chatId: 42,
                accountSlot: 3,
                openMessage: (_) async {},
              ),
              child: MessageBubble(
                message: message,
                peerTitle: 'Source chat',
                isGroup: true,
                onDoubleTap: (_) => fail('a single link tap must not select'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text(label, findRichText: true));
    await tester.pump();

    final opened = ChatDeepLinkController.shared.consumePending();
    expect(opened?.chatId, -1005678);
    expect(opened?.messageId, isNull);
    expect(opened?.accountSlot, 3);
  });

  testWidgets('a BotStart link triggers the bot and opens its scoped chat', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    const label = 'Safe hot bot';
    final message = ChatMessage(
      id: 3,
      isOutgoing: false,
      text: label,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 0,
          length: label.length,
          type: 'textEntityTypeTextUrl',
          url: 'https://t.me/safe_hot_bot?start=hot',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: InternalChatLinkScope(
              target: InternalChatLinkTarget(
                chatId: 42,
                accountSlot: 3,
                openMessage: (_) async {},
              ),
              child: MessageBubble(
                message: message,
                peerTitle: 'Source chat',
                isGroup: true,
                onDoubleTap: (_) => fail('a single link tap must not select'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text(label, findRichText: true));
    await tester.pump();

    final opened = ChatDeepLinkController.shared.consumePending();
    expect(
      requests.where((request) => request['@type'] == 'sendBotStartMessage'),
      [
        <String, dynamic>{
          '@type': 'sendBotStartMessage',
          'bot_user_id': 901,
          'chat_id': 9000,
          'parameter': 'hot',
        },
      ],
    );
    expect(opened?.chatId, 9000);
    expect(opened?.accountSlot, 3);
  });

  test('fallback conversion rejects absent and non-positive post IDs', () {
    expect(telegramFallbackMessageId('https://t.me/safe_hot_results'), isNull);
    expect(
      telegramFallbackMessageId('https://t.me/safe_hot_results/0'),
      isNull,
    );
    expect(
      telegramFallbackMessageId('https://t.me/safe_hot_results/-1'),
      isNull,
    );
  });
}
