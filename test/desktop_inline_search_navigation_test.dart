import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/chat/telegram_mini_app_recents.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';

/// The inline search panel ships mounted by `MaterialApp.builder`, i.e. above
/// the app Navigator. Every test here builds that exact shape — a panel under
/// the Navigator can route by accident and hides the bug these cover.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) => handler(request),
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() => handler = _searchResponse);

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('a chat hit above the app Navigator still opens its chat', (
    tester,
  ) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    final deepLinks = _DeepLinkHost();
    addTearDown(deepLinks.dispose);

    await tester.pumpWidget(_frameHarness(controller));
    await _search(tester, 'needle');

    await tester.tap(find.text('Needle chat'));
    await tester.pumpAndSettle();

    final request = ChatDeepLinkController.shared.consumePending();
    expect(request?.chatId, 100);
    expect(request?.title, 'Needle chat');
    expect(tester.takeException(), isNull);
    expect(controller.panelVisible, isFalse);
  });

  testWidgets('a message hit above the app Navigator carries its message id', (
    tester,
  ) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    final deepLinks = _DeepLinkHost();
    addTearDown(deepLinks.dispose);

    await tester.pumpWidget(_frameHarness(controller));
    await _search(tester, 'needle');

    await tester.tap(find.textContaining('needle:post').first);
    await tester.pumpAndSettle();

    final request = ChatDeepLinkController.shared.consumePending();
    expect(request?.chatId, 200);
    expect(request?.messageId, 1000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Mini App hit above the app Navigator still launches', (
    tester,
  ) async {
    const app = TelegramMiniAppRecent(
      title: 'Sticker Captcha',
      url: 'https://example.com/captcha',
      botUserId: 701,
      chatId: 801,
      updatedAt: 5,
    );
    TelegramMiniAppRecent? opened;
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => [app],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _frameHarness(controller, onOpenMiniApp: (value) => opened = value),
    );
    await _search(tester, 'captcha');

    await tester.tap(
      find.byKey(const ValueKey('desktop-inline-search-mini-app-701-801')),
    );
    await tester.pumpAndSettle();

    expect(identical(opened, app), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Telegram link is the first candidate and opens directly', (
    tester,
  ) async {
    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    String? openedLink;

    await tester.pumpWidget(
      _frameHarness(
        controller,
        onOpenTelegramLink: (_, link) => openedLink = link,
      ),
    );
    await _search(tester, 'telegram.me/example_chat');

    final firstCandidate = find.byKey(
      const ValueKey('desktop-inline-search-deeplink'),
    );
    expect(firstCandidate, findsOneWidget);
    expect(
      tester.getTopLeft(firstCandidate).dy,
      lessThan(tester.getTopLeft(find.text('Needle chat')).dy),
    );

    await tester.tap(firstCandidate);
    await tester.pumpAndSettle();

    expect(openedLink, 'https://telegram.me/example_chat');
    expect(controller.panelVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a discovered chat with no message history still opens', (
    tester,
  ) async {
    handler = (request) async {
      if (request['@type'] == 'searchPublicChats') {
        return {
          '@type': 'chats',
          'chat_ids': [300],
        };
      }
      if (request['@type'] == 'getChat' && request['chat_id'] == 300) {
        return {
          '@type': 'chat',
          'id': 300,
          'title': 'Fresh chat',
          'type': {'@type': 'chatTypeSupergroup', 'is_channel': false},
          'positions': <Map<String, dynamic>>[],
          'unread_count': 0,
          // Deliberately no last_message: this chat has no history yet.
        };
      }
      return _searchResponse(request);
    };

    final controller = DesktopInlineSearchController(
      miniAppSearch: (_) async => const [],
    );
    addTearDown(controller.dispose);
    final deepLinks = _DeepLinkHost();
    addTearDown(deepLinks.dispose);

    await tester.pumpWidget(_frameHarness(controller));
    await _search(tester, 'fresh');
    await tester.tap(find.text('Fresh chat'));
    await tester.pumpAndSettle();

    final request = ChatDeepLinkController.shared.consumePending();
    expect(request?.chatId, 300);
    expect(request?.title, 'Fresh chat');
    expect(controller.panelVisible, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.byKey(const ValueKey('desktop-title-bar-search-input')),
    query,
  );
  await tester.pump(const Duration(milliseconds: 241));
  await tester.pumpAndSettle();
}

/// Registering a listener makes [ChatDeepLinkController.hasHost] true, which is
/// how the split-pane path reports a conversation without building a ChatView.
class _DeepLinkHost {
  _DeepLinkHost() {
    ChatDeepLinkController.shared.addListener(_noop);
  }

  void _noop() {}

  void dispose() {
    ChatDeepLinkController.shared
      ..removeListener(_noop)
      ..consumePending();
  }
}

Widget _frameHarness(
  DesktopInlineSearchController controller, {
  FutureOr<void> Function(TelegramMiniAppRecent app)? onOpenMiniApp,
  DesktopTelegramLinkOpener? onOpenTelegramLink,
}) => MaterialApp(
  navigatorKey: appNavigatorKey,
  theme: ThemeData(extensions: [AppColors.light]),
  // The shipped tree: the search field and panel are siblings of the app
  // Navigator, not descendants of it.
  builder: (context, child) => Stack(
    children: [
      Positioned.fill(child: child ?? const SizedBox.shrink()),
      Positioned(
        top: 0,
        right: 0,
        child: SizedBox(
          width: 460,
          height: 600,
          child: Column(
            children: [
              SizedBox(
                width: DesktopInlineSearchField.width,
                height: DesktopInlineSearchField.height,
                child: Overlay(
                  clipBehavior: Clip.none,
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => DesktopInlineSearchField(
                        controller: controller,
                        onSearchAll: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: DesktopInlineSearchPanel(
                    controller: controller,
                    onSearchAll: (_) {},
                    onOpenMiniApp: onOpenMiniApp,
                    onOpenTelegramLink: onOpenTelegramLink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
  home: const Scaffold(body: SizedBox.expand()),
);

Future<Map<String, dynamic>> _searchResponse(
  Map<String, dynamic> request,
) async {
  switch (request['@type']) {
    case 'searchChats':
      return {
        '@type': 'chats',
        'chat_ids': [100],
      };
    case 'searchContacts':
      return {'@type': 'users', 'user_ids': <int>[]};
    case 'searchPublicChats':
      return {'@type': 'chats', 'chat_ids': <int>[]};
    case 'searchPublicChat':
      return {'@type': 'error', 'code': 404, 'message': 'not found'};
    case 'searchMessages':
      final list = request['chat_list'] as Map<String, dynamic>?;
      final filter =
          (request['filter'] as Map<String, dynamic>)['@type'] as String;
      if (list?['@type'] == 'chatListArchive' ||
          filter != 'searchMessagesFilterEmpty') {
        return {'@type': 'foundMessages', 'messages': <Map<String, dynamic>>[]};
      }
      return {
        '@type': 'foundMessages',
        'messages': [_message(1000, text: 'needle:post')],
      };
    case 'getChat':
      final chatId = request['chat_id'] as int;
      return {
        '@type': 'chat',
        'id': chatId,
        'title': chatId == 100 ? 'Needle chat' : 'Message source',
        'type': {'@type': 'chatTypePrivate', 'user_id': 50},
        'positions': <Map<String, dynamic>>[],
        'unread_count': 0,
      };
  }
  return {'@type': 'ok'};
}

Map<String, dynamic> _message(int id, {required String text}) => {
  '@type': 'message',
  'id': id,
  'chat_id': 200,
  'date': id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': 50},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': text,
      'entities': <Map<String, dynamic>>[],
    },
  },
};
