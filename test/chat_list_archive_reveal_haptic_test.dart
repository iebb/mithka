import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _chat(
  int id, {
  String list = 'chatListMain',
  int order = 100,
}) => {
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

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final haptics = <MethodCall>[];
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          haptics.add(call);
          return null;
        });
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets(
    'revealing the pull-down archive fires a haptic exactly once',
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'communitiesEnabled': false,
        'showChatListSearch': true,
        'archivedChatsDisplayMode': 'pullDown',
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
        '@type': 'updateNewChat',
        'chat': _chat(101, list: 'chatListArchive', order: 50),
      });
      for (var i = 1; i <= 30; i++) {
        updates.add({
          '@type': 'updateNewChat',
          'chat': _chat(1000 - i, order: 1000 - i),
        });
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      haptics.clear();

      final firstRow = tester.getTopLeft(find.text('Chat 991')).dy;
      final gesture = await tester.startGesture(Offset(200, firstRow + 60));
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
      expect(haptics, isNotEmpty, reason: 'the reveal must fire a haptic');
      expect(
        haptics.where((c) => c.method == 'HapticFeedback.vibrate').length,
        1,
        reason: 'exactly one haptic when the archive reveal latches',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
