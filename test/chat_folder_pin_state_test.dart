import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Folder pin state must be local to each folder projection: the row shows the
// folder's own pin (icon + pinnedRow tint), and a toggle targets the folder's
// chat list without touching the Main list's pin.
void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final requests = <Map<String, dynamic>>[];
  setUpAll(() {
    // Exercise the real folder UI without accessing a Telegram account.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(request);
          return switch (request['@type']) {
            'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
            _ => {'@type': 'ok'},
          };
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
    'folder rows render folder-local pin state',
    (tester) async {
      await _pumpFolders(tester, updates, reducedMotion: true);
      for (final chat in [
        _folderChat(1, 'Main pinned', mainPinned: true, folderPinned: false),
        _folderChat(2, 'Folder pinned', mainPinned: false, folderPinned: true),
      ]) {
        updates.add({'@type': 'updateNewChat', 'chat': chat});
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Main list first: existing behaviour must not regress.
      _expectRowPin(
        tester,
        'Main pinned',
        pinned: true,
        reason: 'main list keeps its own pin rendering',
      );
      _expectRowPin(tester, 'Folder pinned', pinned: false);

      await tester.tap(find.byKey(const ValueKey('side-folder-1')));
      await tester.pumpAndSettle();

      // Folder 1: A is Main-pinned but folder-unpinned, B the reverse.
      _expectRowPin(tester, 'Main pinned', pinned: false);
      _expectRowPin(tester, 'Folder pinned', pinned: true);
      await _disposeFolders(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'toggling a folder row pins only that folder list',
    (tester) async {
      await _pumpFolders(tester, updates, reducedMotion: true);
      updates.add({
        '@type': 'updateNewChat',
        'chat': _folderChat(
          1,
          'Chat one',
          mainPinned: false,
          folderPinned: false,
        ),
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('side-folder-1')));
      await tester.pumpAndSettle();

      // Long-press preview's pin action targets the folder the row lives in.
      await tester.longPress(find.text('Chat one'));
      await tester.pumpAndSettle();
      final pinAction = find.descendant(
        of: find.byKey(const ValueKey('chat-list-preview-actions')),
        matching: find.text(_t(AppStringKeys.chatInfoPin)),
      );
      expect(pinAction, findsOneWidget);
      requests.clear();
      await tester.tap(pinAction);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));

      final toggle = requests.where((r) => r['@type'] == 'toggleChatIsPinned');
      expect(toggle, hasLength(1));
      expect(toggle.single['chat_list'], {
        '@type': 'chatListFolder',
        'chat_folder_id': 1,
      });
      expect(toggle.single['is_pinned'], isTrue);

      // The Main list pin must stay untouched (no optimistic flip there).
      final row = find.ancestor(
        of: find.text('Chat one'),
        matching: find.byType(ChatRowView),
      );
      // Back on the main list, the row must not carry a pin.
      await tester.tap(find.byKey(const ValueKey('side-folder-all')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('chat-row-pinned')),
        ),
        findsNothing,
        reason: 'folder toggle must not flip the Main list pin',
      );
      await _disposeFolders(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

String _t(String key) => AppStrings.t(key);

void _expectRowPin(
  WidgetTester tester,
  String title, {
  required bool pinned,
  String? reason,
}) {
  final row = find.ancestor(
    of: find.text(title),
    matching: find.byType(ChatRowView),
  );
  final icon = find.descendant(
    of: row,
    matching: find.byKey(const ValueKey('chat-row-pinned')),
  );
  expect(icon.evaluate().length, pinned ? 1 : 0, reason: reason);
  Color rowColor() => tester
      .widget<Container>(
        find.descendant(of: row, matching: find.byType(Container)).first,
      )
      .color!;
  expect(
    rowColor(),
    pinned ? AppColors.light.pinnedRow : AppColors.light.background,
    reason: reason,
  );
}

Future<void> _pumpFolders(
  WidgetTester tester,
  StreamController<Map<String, dynamic>> updates, {
  bool reducedMotion = false,
}) async {
  SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
  final theme = ThemeController(await SharedPreferences.getInstance());
  theme.chatListSwipeMode = ChatListSwipeMode.switchFolders;
  final controller = ChatListController();
  final accounts = AccountStore(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  addTearDown(controller.dispose);
  addTearDown(accounts.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: theme,
      child: ChangeNotifierProvider<AccountStore>.value(
        value: accounts,
        child: ChangeNotifierProvider<AuthManager>.value(
          value: AuthManager(),
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppColors.light]),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: child!,
            ),
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
                    child: ChatListView(
                      controller: controller,
                      desktopSidebar: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  updates.add({
    '@type': 'updateChatFolders',
    'chat_folders': [
      for (var id = 1; id <= 8; id++) {'id': id, 'title': 'Folder $id'},
    ],
  });
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _disposeFolders(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

Map<String, dynamic> _folderChat(
  int id,
  String title, {
  required bool mainPinned,
  required bool folderPinned,
}) => {
  '@type': 'chat',
  'id': id,
  'title': title,
  'type': {'@type': 'chatTypePrivate', 'user_id': id + 1000},
  'unread_count': 0,
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': 100 - id,
      'is_pinned': mainPinned,
    },
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListFolder', 'chat_folder_id': 1},
      'order': 200 - id,
      'is_pinned': folderPinned,
    },
  ],
};
