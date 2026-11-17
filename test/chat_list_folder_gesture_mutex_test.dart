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

/// Scroll offset of the chat list's vertical scrollable.
double _chatListPixels(WidgetTester tester) {
  for (final element in find.byType(Scrollable).evaluate()) {
    if (element.widget is! Scrollable) continue;
    final state = (element as StatefulElement).state;
    if (state is ScrollableState && state.position.axis == Axis.vertical) {
      return state.position.pixels;
    }
  }
  return double.nan;
}

Map<String, dynamic> _chat(
  int id, {
  String list = 'chatListMain',
  int order = 100,
}) => {
  '@type': 'chat',
  'id': id,
  'title': 'Chat $id',
  'type': {'@type': 'chatTypePrivate', 'user_id': 1000 + id},
  'last_message': {
    '@type': 'message',
    'id': id * 10,
    'chat_id': id,
    'date': order,
    'is_outgoing': false,
    'content': {
      '@type': 'messageText',
      'text': {'@type': 'formattedText', 'text': 'hi', 'entities': <Object>[]},
    },
  },
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': list},
      'order': order,
      'is_pinned': false,
    },
  ],
};

/// Pumps the chat list with two folders plus one chat inside a folder, so the
/// folder pager has somewhere to swipe to.
Future<ThemeController> _pumpFolderPager(
  WidgetTester tester,
  StreamController<Map<String, dynamic>> updates, {
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'communitiesEnabled': false,
    'showChatListSearch': true,
    ...prefs,
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
      {
        'id': 1,
        'title': 'Work',
        'pinned_chat_ids': [201],
        'included_chat_ids': [201],
      },
    ],
  });
  for (var i = 1; i <= 30; i++) {
    updates.add({
      '@type': 'updateNewChat',
      'chat': _chat(1000 - i, order: 1000 - i),
    });
  }
  updates.add({
    '@type': 'updateNewChat',
    'chat': {..._chat(201), 'title': 'Work chat'},
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pumpAndSettle();
  return theme;
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

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
    'a folder drag cancels the vertical scroll it started as',
    (tester) async {
      await _pumpFolderPager(
        tester,
        updates,
        prefs: {'chatListSwipeMode.v1': 'switchFolders'},
      );
      final firstRow = tester.getTopLeft(find.text('Chat 991')).dy;
      final gesture = await tester.startGesture(Offset(200, firstRow + 60));
      await tester.pump(const Duration(milliseconds: 40));
      // Scroll the list upward first — the drag is owned by the vertical
      // scrollable at this point.
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final scrolled = _chatListPixels(tester);
      expect(scrolled, greaterThan(0), reason: 'the list scrolls first');
      // Now bend the same contact sideways into a folder swipe.
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final duringFolderDrag = _chatListPixels(tester);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      final afterUp = _chatListPixels(tester);
      expect(
        duringFolderDrag,
        moreOrLessEquals(scrolled, epsilon: 1),
        reason:
            'once the folder drag owns the contact the list must stop '
            'scrolling instead of stacking both axes',
      );
      expect(
        afterUp,
        moreOrLessEquals(scrolled, epsilon: 1),
        reason: 'the list does not inherit leftover drag travel',
      );
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'scrolling up collapses the archive row and the search row in one animation',
    (tester) async {
      await _pumpFolderPager(
        tester,
        updates,
        prefs: {'archivedChatsDisplayMode': 'pullDown'},
      );
      updates.add({
        '@type': 'updateNewChat',
        'chat': _chat(101, list: 'chatListArchive', order: 50),
      });
      await tester.pump();
      await tester.pumpAndSettle();

      // Reveal the pull-down archive row.
      final firstRow = tester.getTopLeft(find.text('Chat 991')).dy;
      var gesture = await tester.startGesture(Offset(200, firstRow + 60));
      await tester.pump(const Duration(milliseconds: 40));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.byType(ChatListPullDownArchiveSlot),
        findsOneWidget,
        reason: 'fixture must mount the pull-down archive slot',
      );
      // The pill is a list row; once the archive reveal collapsed the layout
      // the search row may already sit offscreen — jump back to the top where
      // the pin assertions below measure it.
      {
        final scrollables = find.byType(Scrollable).evaluate();
        for (final element in scrollables) {
          final state = (element as StatefulElement).state;
          if (state is ScrollableState &&
              state.position.axis == Axis.vertical &&
              state.position.pixels != 0) {
            state.position.jumpTo(0);
          }
        }
        await tester.pump();
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('chat-list-inline-search')),
        findsOneWidget,
        reason: 'fixture must show the search row at the top',
      );

      final searchFinder = find.byKey(
        const ValueKey('chat-list-inline-search'),
      );
      final searchTop = tester.getTopLeft(searchFinder).dy;

      // Scroll up a little: the archive row slides out from under the search
      // row while the search row holds its place.
      gesture = await tester.startGesture(Offset(200, firstRow + 60));
      await tester.pump(const Duration(milliseconds: 40));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // The collapse fires at half a row of travel (~36px at this fixture's
      // row height), which this drag has passed. Both rows now leave in ONE
      // shared 180ms animation — no stall between them.
      final slotElement = find
          .byType(ChatListPullDownArchiveSlot)
          .evaluate()
          .single;
      final slot = (slotElement.widget as ChatListPullDownArchiveSlot);
      expect(
        slot.visible,
        isFalse,
        reason:
            'by now the revealed archive row has started collapsing '
            '(travel is past half a row)',
      );
      // Mid-animation on the shared clock: the search row is already leaving
      // with the archive row instead of being held in place.
      await tester.pump(const Duration(milliseconds: 60));
      final midTop = searchFinder.evaluate().isEmpty
          ? double.negativeInfinity
          : tester.getTopLeft(searchFinder).dy;
      expect(
        midTop,
        lessThan(searchTop - 0.5),
        reason:
            'the search row departs in the same animation as the archive '
            'row — no stall between them',
      );
      // By the end of the shared clock the compensation has returned the
      // offset to the top and the first chat row sits fully visible at the
      // top of the viewport — not half-clipped by leftover offset.
      await tester.pump(const Duration(milliseconds: 200));
      expect(_chatListPixels(tester), moreOrLessEquals(0, epsilon: 1));
      final firstChatTop = tester.getTopLeft(find.text('Chat 999')).dy;
      // The folder strip's bottom edge (~108) plus the list's top padding
      // (~13.5) is where a fully visible first row starts. Leftover
      // un-compensated offset clipped it mid-row before the fix; a premature
      // latch release pushed it down further.
      expect(
        firstChatTop,
        moreOrLessEquals(121.5, epsilon: 3),
        reason:
            'after the collapse the first chat row is fully at the top, not '
            'half-clipped',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
