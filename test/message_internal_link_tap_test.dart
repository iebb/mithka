import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/chat/internal_chat_link_router.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const linkedMessageId = 700 << 20;
  const mainWebAppUrl = 'https://t.me/shuishui_tghzbot?startapp=rule_1';

  late StreamController<Map<String, dynamic>> updates;
  late List<Map<String, dynamic>> requests;
  late bool mainWebAppAvailable;
  late bool mainWebAppCanBeAddedToAttachmentMenu;
  late bool mainWebAppIsInstalled;

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
            'getInternalLinkType' when request['link'] == mainWebAppUrl =>
              <String, dynamic>{
                '@type': 'internalLinkTypeMainWebApp',
                'bot_username': 'shuishui_tghzbot',
                'start_parameter': 'rule_1',
                'mode': <String, dynamic>{'@type': 'webAppOpenModeFullSize'},
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
            'searchPublicChat' when request['username'] == 'shuishui_tghzbot' =>
              <String, dynamic>{
                '@type': 'chat',
                'id': 9100,
                'title': 'Water bot',
                'type': <String, dynamic>{
                  '@type': 'chatTypePrivate',
                  'user_id': 911,
                },
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
            'getUser' when request['user_id'] == 911 => <String, dynamic>{
              '@type': 'user',
              'id': 911,
              'first_name': 'Water bot',
              'last_name': '',
              'type': <String, dynamic>{
                '@type': 'userTypeBot',
                'has_main_web_app': mainWebAppAvailable,
                'can_be_added_to_attachment_menu':
                    mainWebAppCanBeAddedToAttachmentMenu,
              },
            },
            'getUserFullInfo' when request['user_id'] == 911 =>
              <String, dynamic>{
                '@type': 'userFullInfo',
                'bot_info': <String, dynamic>{
                  '@type': 'botInfo',
                  'menu_button': <String, dynamic>{
                    '@type': 'botMenuButton',
                    'text': 'Website mutual aid',
                    'url': 'menu://https://tghz.20110202.top/',
                  },
                },
              },
            'getMe' => <String, dynamic>{'@type': 'user', 'id': 33},
            'getMainWebApp' => <String, dynamic>{
              '@type': 'mainWebApp',
              'url': 'https://mini.example/app?tgWebAppData=test-signed-data',
            },
            'getAttachmentMenuBot' => <String, dynamic>{
              '@type': 'attachmentMenuBot',
              'name': 'Water bot',
              'is_added': mainWebAppIsInstalled,
              'request_write_access': false,
            },
            'openWebApp' => <String, dynamic>{
              '@type': 'webAppInfo',
              'url': 'https://tghz.20110202.top/?tgWebAppData=menu-signed-data',
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
    mainWebAppAvailable = true;
    mainWebAppCanBeAddedToAttachmentMenu = false;
    mainWebAppIsInstalled = false;
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
      final selectionKey = GlobalKey<SelectionAreaState>();
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
                  mobileTextSelectionAreaKey: selectionKey,
                ),
              ),
            ),
          ),
        ),
      );
      expect(selectionKey.currentState, isNotNull);

      await tester.tap(find.text(label, findRichText: true));
      await tester.pump();

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

  testWidgets('a main Web App link requires attachment-menu consent', (
    tester,
  ) async {
    mainWebAppCanBeAddedToAttachmentMenu = true;
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final message = ChatMessage(
      id: 6,
      isOutgoing: false,
      text: mainWebAppUrl,
      date: 1,
      contentType: 'messageText',
      textEntities: const [
        MessageTextEntity(
          offset: 0,
          length: mainWebAppUrl.length,
          type: 'textEntityTypeUrl',
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
              ),
            ),
          ),
        ),
      ),
    );

    await _tapFirstCharacter(tester, mainWebAppUrl);
    await tester.pumpAndSettle();

    expect(
      requests.where((request) => request['@type'] == 'getAttachmentMenuBot'),
      hasLength(1),
    );
    expect(
      requests.where((request) => request['@type'] == 'getMainWebApp'),
      isEmpty,
    );
    expect(find.byKey(const ValueKey('app-confirm-cancel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(
      requests.where((request) => request['@type'] == 'getMainWebApp'),
      isEmpty,
    );
  });
}

Future<void> _tapFirstCharacter(WidgetTester tester, String text) async {
  final richText = find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  );
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  final firstCharacter = paragraph
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1))
      .single;
  await tester.tapAt(paragraph.localToGlobal(firstCharacter.toRect().center));
}
