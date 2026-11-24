import 'dart:async';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/archived_chats_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The archived list carries the same long-press edit mode the reference client gives its
// archive folder: body long press selects, the header becomes a command bar
// with the archive's own actions, and the system back button exits it first.

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final unarchived = <int>[];
  final muted = <int>[];
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

  ChatSummary chat(int id) => ChatSummary(
    id: id,
    title: 'Archived $id',
    lastMessage: '',
    lastMessageId: 1,
    date: 1,
    unreadCount: 0,
    order: 1,
    isMuted: false,
  );

  testWidgets(
    'long press enters edit mode; commands drive the archive callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppColors.light]),
            home: ArchivedChatsView(
              chats: [chat(1), chat(2)],
              onClearUnread: (_) {},
              onUnarchive: (c) => unarchived.add(c.id),
              onToggleMute: (c) => muted.add(c.id),
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Body long press enters edit mode.
      final first = tester.getTopLeft(find.text('Archived 1'));
      await tester.startGesture(Offset(first.dx + 220, first.dy + 6));
      await tester.pump(kLongPressTimeout);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-list-selection-header')),
        findsOneWidget,
      );

      // Tap the second row: count becomes 2.
      final second = tester.getTopLeft(find.text('Archived 2'));
      await tester.tapAt(Offset(second.dx + 220, second.dy + 6));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);

      // Unarchive drives both callbacks and exits the mode.
      await tester.tap(
        find.byKey(const ValueKey('chat-list-selection-unarchive')),
      );
      await tester.pumpAndSettle();
      expect(unarchived, [1, 2]);
      expect(
        find.byKey(const ValueKey('chat-list-selection-header')),
        findsNothing,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
