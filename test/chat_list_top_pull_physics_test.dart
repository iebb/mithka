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

/// Drags straight down from the first chat row while the list rests at the
/// top, and reports the scroll offset reached mid-drag.
Future<double> _pullDownFromTop(
  WidgetTester tester, {
  required double fingersDown,
}) async {
  final firstRow = tester.getTopLeft(find.text('Chat 1')).dy;
  final gesture = await tester.startGesture(Offset(200, firstRow + 40));
  await tester.pump(const Duration(milliseconds: 40));
  var remaining = fingersDown;
  while (remaining > 0) {
    final step = remaining > 40 ? 40.0 : remaining;
    await gesture.moveBy(Offset(0, step));
    await tester.pump(const Duration(milliseconds: 16));
    remaining -= step;
  }
  final pixels = _chatListPixels(tester);
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 16));
  return pixels;
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

Future<void> _pump(
  WidgetTester tester,
  StreamController<Map<String, dynamic>> updates, {
  required List<Map<String, dynamic>> chats,
}) async {
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
    'chat_folders': <Map<String, dynamic>>[],
  });
  for (final chat in chats) {
    updates.add({'@type': 'updateNewChat', 'chat': chat});
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pumpAndSettle();
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
    'no archive: top pull does not rubber-band the chat list',
    (tester) async {
      await _pump(
        tester,
        updates,
        chats: [
          _chat(1, order: 300),
          _chat(2, order: 200),
          _chat(3),
        ],
      );
      final pixels = await _pullDownFromTop(tester, fingersDown: 200);
      expect(
        pixels,
        0.0,
        reason:
            'without a pull-down archive the top edge follows the platform '
            'default — no long elastic drag with nothing to reveal',
      );
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'with archive: top pull keeps revealing the archive slot',
    (tester) async {
      await _pump(
        tester,
        updates,
        chats: [
          _chat(1, order: 300),
          _chat(2, order: 200),
          _chat(3),
          _chat(101, list: 'chatListArchive', order: 50),
        ],
      );
      expect(
        find.byType(ChatListPullDownArchiveSlot),
        findsOneWidget,
        reason: 'fixture must mount the pull-down archive slot',
      );
      final pixels = await _pullDownFromTop(tester, fingersDown: 200);
      expect(
        pixels,
        lessThan(0),
        reason: 'the archive reveal keeps its elastic negative offset',
      );
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
