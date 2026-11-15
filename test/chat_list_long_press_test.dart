import 'dart:async';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/chats/chat_list_preview.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Long-press behavior on the chat list, mirroring exteraless's split:
// a press inside the avatar column peeks the conversation; a press anywhere
// else enters the multi-select edit mode with that chat selected.

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
          'getConnectionState' => {'@type': 'connectionStateReady'},
          _ => {'@type': 'ok'},
        },
        send: (request) async {
          sent.add(request);
        },
        updates: updates.stream,
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets(
    'long press on the avatar column opens the peek preview',
    (tester) async {
      await pumpChatList(tester, updates);
      final avatarCenter = rowAvatarCenter(tester, 'Chat 1');
      await tester.startGesture(avatarCenter);
      await tester.pump(kLongPressTimeout);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-list-preview-card')),
        findsOneWidget,
        reason: 'a long press inside the avatar column must peek',
      );
      expect(
        find.byKey(const ValueKey('chat-list-selection-header')),
        findsNothing,
      );
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'long press on the row body enters multi-select edit mode',
    (tester) async {
      await pumpChatList(tester, updates);
      final bodyCenter = rowBodyCenter(tester, 'Chat 1');
      await tester.startGesture(bodyCenter);
      await tester.pump(kLongPressTimeout);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-list-selection-header')),
        findsOneWidget,
        reason: 'a long press on the row body must enter edit mode',
      );
      expect(find.text('1'), findsWidgets);
      expect(
        find.byKey(const ValueKey('chat-list-selection-pin')),
        findsOneWidget,
      );
      // Tap a second row: membership toggles, count becomes 2.
      final second = rowBodyCenter(tester, 'Chat 2');
      await tester.tapAt(second);
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);
      // Close exits edit mode.
      await tester.tap(
        find.byKey(const ValueKey('chat-list-close-selection')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-list-selection-header')),
        findsNothing,
      );
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'preview action menu hugs its content, not the full card width',
    (tester) async {
      await pumpChatList(tester, updates);
      final avatarCenter = rowAvatarCenter(tester, 'Chat 1');
      await tester.startGesture(avatarCenter);
      await tester.pump(kLongPressTimeout);
      await tester.pumpAndSettle();
      final menu = tester.getSize(
        find.byKey(const ValueKey('chat-list-preview-actions')),
      );
      expect(
        menu.width,
        lessThanOrEqualTo(chatListPreviewMenuMaxWidth),
        reason: 'the popup must stay compact',
      );
      expect(menu.width, greaterThanOrEqualTo(chatListPreviewMenuMinWidth));
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

Offset rowAvatarCenter(WidgetTester tester, String title) {
  final text = tester.getTopLeft(find.text(title));
  // The title starts after inset(16) + avatar(49) + gap(12) = 77pt; the
  // avatar's center sits 16 + 24.5 = 40.5pt from the row's left edge.
  return Offset(text.dx - 77 + 40.5, text.dy + 12);
}

Offset rowBodyCenter(WidgetTester tester, String title) {
  final topLeft = tester.getTopLeft(find.text(title));
  return Offset(topLeft.dx + 220, topLeft.dy + 6);
}

Future<void> pumpChatList(
  WidgetTester tester,
  StreamController<Map<String, dynamic>> updates,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final accounts = AccountStore(prefs);
  addTearDown(theme.dispose);
  addTearDown(accounts.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
      ],
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
  updates.add({
    '@type': 'updateNewChat',
    'chat': {
      '@type': 'chat',
      'id': 102,
      'title': 'Chat 2',
      'type': {'@type': 'chatTypePrivate', 'user_id': 8},
      'last_message': {
        '@type': 'message',
        'id': 11,
        'chat_id': 102,
        'date': 11,
        'is_outgoing': false,
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'yo', 'entities': []},
        },
      },
      'positions': [
        {
          '@type': 'chatPosition',
          'list': {'@type': 'chatListMain'},
          'order': 90,
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
