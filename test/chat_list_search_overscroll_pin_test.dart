import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
          'getConnectionState' => {'@type': 'connectionStateReady'},
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets(
    'overscrolling a folder tab pins the inline search row',
    (tester) async {
      await _pumpFolderChatList(tester, updates);
      final searchTop = tester
          .getTopLeft(find.byKey(const ValueKey('chat-list-inline-search')))
          .dy;
      final firstRowTop = tester.getTopLeft(find.text('Chat 1')).dy;

      final gesture = await tester.startGesture(Offset(200, firstRowTop + 40));
      for (final delta in const [20.0, 24.0, 28.0]) {
        await gesture.moveBy(Offset(0, delta));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('chat-list-inline-search')))
              .dy,
          moreOrLessEquals(searchTop, epsilon: 0.1),
          reason:
              'the search row stays with the folder strip while the '
              'viewport rubber-bands below it',
        );
      }
      final stretchedRowTop = tester.getTopLeft(find.text('Chat 1')).dy;
      expect(stretchedRowTop, greaterThan(firstRowTop));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('chat-list-inline-search')))
            .dy,
        moreOrLessEquals(searchTop, epsilon: 0.1),
      );
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

Future<void> _pumpFolderChatList(
  WidgetTester tester,
  StreamController<Map<String, dynamic>> updates,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'communitiesEnabled': false,
    'showChatListSearch': true,
  });
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: const Scaffold(body: ChatListView()),
      ),
    ),
  );

  updates.add({
    '@type': 'updateConnectionState',
    'state': {'@type': 'connectionStateReady'},
  });
  updates.add({
    '@type': 'updateChatFolders',
    'chat_folders': [
      {'id': 1, 'title': 'Work'},
    ],
  });
  updates.add({
    '@type': 'updateNewChat',
    'chat': {
      '@type': 'chat',
      'id': 101,
      'title': 'Chat 1',
      'type': {'@type': 'chatTypePrivate', 'user_id': 7},
      'last_message': {
        '@type': 'message',
        'id': 10,
        'chat_id': 101,
        'date': 10,
        'is_outgoing': false,
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'hi', 'entities': []},
        },
      },
      'positions': [
        {
          '@type': 'chatPosition',
          'list': {'@type': 'chatListMain'},
          'order': 100,
          'is_pinned': false,
        },
      ],
    },
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}
