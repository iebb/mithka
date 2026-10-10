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

/// Counts the frames in which the chat list built its folder rail.
///
/// The rail is published from [ChatListView.build], so one publication is one
/// build of the whole list.
class _BuildCount {
  int builds = 0;
}

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();

  setUpAll(() {
    // Exercise the real list without accessing a Telegram account.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
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
    'a chat list returning from under a conversation rebuilds once',
    (tester) async {
      SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
      final theme = ThemeController(await SharedPreferences.getInstance());
      final controller = ChatListController();
      final count = _BuildCount();
      controller.sideFolders.addListener(() => count.builds++);
      addTearDown(theme.dispose);
      addTearDown(controller.dispose);

      Future<void> pumpList({required bool tickerEnabled}) async {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: theme,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: const [AppLocalizations.delegate],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(extensions: [AppColors.light]),
              home: Scaffold(
                body: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      height: 210,
                      child: ValueListenableBuilder<Widget?>(
                        valueListenable: controller.sideFolders,
                        builder: (_, child, _) =>
                            child ?? const SizedBox.shrink(),
                      ),
                    ),
                    Expanded(
                      // A conversation route above the shell mutes the list's
                      // tickers for as long as it covers it.
                      child: TickerMode(
                        enabled: tickerEnabled,
                        child: ChatListView(
                          controller: controller,
                          desktopSidebar: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      await pumpList(tickerEnabled: true);
      updates.add({
        '@type': 'updateChatFolders',
        'chat_folders': [
          {'id': 1, 'title': 'Folder 1'},
        ],
      });
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('side-folder-1')), findsOneWidget);

      // The conversation covers the list.
      await pumpList(tickerEnabled: false);
      await tester.pumpAndSettle();
      count.builds = 0;

      // A folder arrives while the list is covered, and stays deferred.
      updates.add({
        '@type': 'updateChatFolders',
        'chat_folders': [
          {'id': 1, 'title': 'Folder 1'},
          {'id': 2, 'title': 'Folder 2'},
        ],
      });
      await tester.pump();
      await tester.pumpAndSettle();
      expect(count.builds, 0);
      expect(find.byKey(const ValueKey('side-folder-2')), findsNothing);

      // The conversation closes: the frame that unmutes the list is the frame
      // that rebuilds it, with everything the model applied while covered.
      await pumpList(tickerEnabled: true);
      expect(count.builds, 1);

      // The next frame belongs to the transition. Rebuilding the list again
      // here is what made closing a conversation stutter.
      await tester.pump(const Duration(milliseconds: 16));
      expect(count.builds, 1);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('side-folder-2')), findsOneWidget);
      expect(count.builds, 1);

      // Let the model's warm-cache timers run out with the list unmounted.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
