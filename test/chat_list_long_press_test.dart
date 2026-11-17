import 'dart:async';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderFractionalTranslation;
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
        query: (request) async {
          sent.add(request);
          return switch (request['@type']) {
            'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
            'getConnectionState' => {'@type': 'connectionStateReady'},
            _ => {'@type': 'ok'},
          };
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

  testWidgets(
    'edit header rows keep the default header height',
    (tester) async {
      await pumpChatList(tester, updates);
      final normal = tester
          .getSize(find.byKey(const ValueKey('chat-list-header-avatar-hit')))
          .height;
      final bodyCenter = rowBodyCenter(tester, 'Chat 1');
      await tester.startGesture(bodyCenter);
      await tester.pump(kLongPressTimeout);
      await tester.pumpAndSettle();
      final editRow = tester
          .getSize(find.byKey(const ValueKey('chat-list-selection-pin')))
          .height;
      expect(editRow, moreOrLessEquals(normal, epsilon: 0.1));
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'overflow menu opens as a compact anchored popup and select-all works',
    (tester) async {
      await pumpChatList(tester, updates);
      final bodyCenter = rowBodyCenter(tester, 'Chat 1');
      await tester.startGesture(bodyCenter);
      await tester.pump(kLongPressTimeout);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('chat-list-selection-overflow')),
      );
      await tester.pumpAndSettle();
      final menu = tester.getSize(
        find.byKey(const ValueKey('chat-list-selection-overflow-menu')),
      );
      expect(menu.width, lessThan(280), reason: 'popup hugs its labels');
      await tester.tap(
        find.byKey(const ValueKey('chat-list-selection-overflow-select-all')),
      );
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'dragging a pinned row in edit mode reorders it and commits once on drop',
    (tester) async {
      await pumpChatList(tester, updates);
      updates.add(pinnedChatFixture(201, 'Pinned A', 300));
      updates.add(pinnedChatFixture(202, 'Pinned B', 200));
      updates.add(pinnedChatFixture(203, 'Pinned C', 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      sent.clear();

      // Enter edit mode via body long press on Pinned A.
      final start = rowBodyCenter(tester, 'Pinned A');
      final gesture = await tester.startGesture(start);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-list-selection-header')),
        findsOneWidget,
      );
      // Drag down past Pinned B: the lifted row swaps slots once, and only a
      // single setPinnedChats goes out — on drop, never per crossed slot.
      final rowHeight = tester.getSize(find.text('Pinned A')).height + 28;
      await gesture.moveBy(Offset(0, rowHeight * 1.2));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(Offset(0, rowHeight * 0.4));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sent.where((r) => r['@type'] == 'setPinnedChats'), isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      final commits = sent
          .where((r) => r['@type'] == 'setPinnedChats')
          .toList();
      expect(commits, hasLength(1));
      expect(commits.single['chat_ids'], [202, 201, 203]);

      // Order visibly changed: Pinned B now leads the band.
      expect(
        tester.getTopLeft(find.text('Pinned B')).dy <
            tester.getTopLeft(find.text('Pinned A')).dy,
        isTrue,
      );
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'the drag proxy follows the finger above the list while the row hides',
    (tester) async {
      await pumpChatList(tester, updates);
      updates.add(pinnedChatFixture(231, 'Proxy A', 300));
      updates.add(pinnedChatFixture(232, 'Proxy B', 200));
      updates.add(pinnedChatFixture(233, 'Proxy C', 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();

      final start = rowBodyCenter(tester, 'Proxy A');
      final gesture = await tester.startGesture(start);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      final rowHeight = tester.getSize(find.text('Proxy A')).height + 28;

      // The row's slot position before the drag — the proxy must lift from
      // exactly here.
      // The row's top edge = the text's top minus the row's leading padding
      // (the title sits 13.5pt below the row's top edge in this row style).
      final rowTopBeforeLift =
          tester.getTopLeft(find.text('Proxy A').first).dy - 13.5;

      // Past the lift threshold the proxy exists, lifted from the row's slot
      // and already carrying the 20px the finger moved — glued from frame one.
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      final proxyFinder = find.byKey(const ValueKey('chat-list-drag-proxy'));
      expect(proxyFinder, findsOneWidget, reason: 'drag lifts a proxy');
      final proxyTopAfterLift = tester.getTopLeft(proxyFinder).dy;
      expect(
        proxyTopAfterLift,
        moreOrLessEquals(rowTopBeforeLift + 20, epsilon: 2),
        reason: 'proxy lifts from the row position and tracks the finger',
      );

      // Move further: the proxy moves by the same delta — glued to finger.
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      final proxyTopAfterMove = tester.getTopLeft(proxyFinder).dy;
      expect(
        proxyTopAfterMove - proxyTopAfterLift,
        moreOrLessEquals(30, epsilon: 1),
        reason: 'proxy must track the finger 1:1',
      );

      // Cross Pinned B's midpoint: the NEIGHBOUR begins an animated slide,
      // its on-screen position is BETWEEN old and new slot mid-drag (no
      // teleport flash), and it never leaves the screen (no blank band).
      await gesture.moveBy(Offset(0, rowHeight * 0.5 + 6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // The neighbour slides — mid-animation its pixel rise is strictly
      // between 0 and the full row extent: 0 means the animation never ran
      // (dead), the full extent means it teleported (zero duration). Both
      // flash; neither may happen.
      final neighbourText = find.text('Proxy B');
      expect(neighbourText, findsOneWidget);
      final slide = find
          .ancestor(of: neighbourText, matching: find.byType(AnimatedSlide))
          .first;
      final renderSlide =
          tester.renderObject(slide) as RenderFractionalTranslation;
      final rise = -renderSlide.translation.dy;
      expect(rise, greaterThan(1), reason: 'neighbour must leave its slot');
      expect(
        rise,
        lessThan(rowHeight - 1),
        reason: 'neighbour must still be animating, not landed',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(proxyFinder, findsNothing, reason: 'drop removes the proxy');
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'lifting the finger after entering edit mode keeps the mode',
    (tester) async {
      await pumpChatList(tester, updates);
      updates.add(pinnedChatFixture(221, 'Keep A', 300));
      updates.add(pinnedChatFixture(222, 'Keep B', 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();

      // Long press enters edit mode; lifting the SAME finger must keep it —
      // exteraless's allowMoving: the opening gesture never toggles or drags.
      final gesture = await tester.startGesture(
        rowBodyCenter(tester, 'Keep A'),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-list-selection-header')),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-list-selection-header')),
        findsOneWidget,
        reason: 'releasing the opening long press must stay in edit mode',
      );
      expect(find.text('1'), findsWidgets);
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a selected pinned row can also be dragged',
    (tester) async {
      await pumpChatList(tester, updates);
      updates.add(pinnedChatFixture(211, 'Sel A', 300));
      updates.add(pinnedChatFixture(212, 'Sel B', 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      sent.clear();

      // Enter edit mode on Sel A (now selected), then long press it again and
      // drag: membership must not block the drag.
      final start = rowBodyCenter(tester, 'Sel A');
      final gesture = await tester.startGesture(start);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsWidgets);

      final rowHeight = tester.getSize(find.text('Sel A')).height + 28;
      await gesture.moveBy(Offset(0, rowHeight * 1.2));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final commits = sent
          .where((r) => r['@type'] == 'setPinnedChats')
          .toList();
      expect(commits, hasLength(1));
      expect(commits.single['chat_ids'], [212, 211]);
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

/// Chat payloads with pinned positions, for the drag-reorder tests.
Map<String, dynamic> pinnedChatFixture(int id, String title, int order) => {
  '@type': 'updateNewChat',
  'chat': {
    '@type': 'chat',
    'id': id,
    'title': title,
    'type': {'@type': 'chatTypePrivate', 'user_id': id},
    'last_message': {
      '@type': 'message',
      'id': order,
      'chat_id': id,
      'date': order,
      'is_outgoing': false,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'm$id', 'entities': []},
      },
    },
    'positions': [
      {
        '@type': 'chatPosition',
        'list': {'@type': 'chatListMain'},
        'order': order,
        'is_pinned': true,
      },
    ],
  },
};
