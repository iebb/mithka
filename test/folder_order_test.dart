import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_folder_tab_menu.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/chats/local_folder_order_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/chat_folder_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/chat_folder_management_view.dart';
import 'package:mithka/settings/chat_folder_service.dart';
import 'package:mithka/settings/local_premium.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The folder order surfaces must stay usable with many folders, must only
// offer the main-list move when the account is entitled to it, and must show
// what Telegram actually stores: the main list's own position, the
// local-premium copy on this device, and each folder's icon.

ChatFolderRecord folderRecord(int id, String title, {String icon = 'Custom'}) =>
    ChatFolderRecord(
      id: id,
      title: title,
      raw: {
        '@type': 'chatFolder',
        'name': {
          '@type': 'chatFolderName',
          'text': {'@type': 'formattedText', 'text': title},
        },
        'icon': {'@type': 'chatFolderIcon', 'name': icon},
      },
      hasInviteLinks: false,
    );

ChatFolderService recordingService(List<Map<String, dynamic>> sent) =>
    ChatFolderService(
      query: (request) async {
        sent.add(request);
        return {'@type': 'ok'};
      },
    );

Widget appShell(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: [AppColors.light]),
  home: Scaffold(body: home),
);

Future<void> pumpSheet(
  WidgetTester tester,
  List<ChatFolderRecord> folders, {
  int mainListPosition = 0,
  bool canMoveMainList = true,
  ValueChanged<int>? onMainListPositionSaved,
  ChatFolderService? service,
}) => tester.pumpWidget(
  appShell(
    ChatFolderReorderSheet(
      folders: folders,
      mainListPosition: mainListPosition,
      service: service ?? recordingService(<Map<String, dynamic>>[]),
      canMoveMainList: canMoveMainList,
      onMainListPositionSaved: onMainListPositionSaved,
    ),
  ),
);

ChatFolderService settingsService() => ChatFolderService(
  query: (request) async {
    if (request['@type'] == 'getChatFolder') {
      final id = request['chat_folder_id'] as int;
      return {
        '@type': 'chatFolder',
        'id': id,
        'name': {
          '@type': 'chatFolderName',
          'text': {'@type': 'formattedText', 'text': 'Folder $id'},
        },
        'icon': {'@type': 'chatFolderIcon', 'name': id == 7 ? 'Cat' : 'Home'},
      };
    }
    if (request['@type'] == 'getRecommendedChatFolders') {
      return {'@type': 'chatFolders', 'chat_folders': <Object>[]};
    }
    return {'@type': 'ok'};
  },
);

Future<StreamController<Map<String, dynamic>>> pumpSettings(
  WidgetTester tester, {
  required ThemeController theme,
}) async {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: ChatFolderManagementView(
          service: settingsService(),
          updates: updates.stream,
        ),
      ),
    ),
  );
  await tester.pump();
  updates.add({
    '@type': 'updateChatFolders',
    'chat_folders': [
      {'id': 7, 'title': 'Folder 7'},
      {'id': 8, 'title': 'Folder 8'},
    ],
    'main_chat_list_position': 0,
  });
  await tester.pumpAndSettle();
  return updates;
}

void main() {
  tearDown(() {
    LocalPremium.shared.setEnabled(false);
    LocalFolderOrderStore.shared.clearForTesting();
  });

  test('a locked main list cannot be moved by a folder drop', () {
    final entries = [null, folderRecord(7, 'A'), folderRecord(8, 'B')];

    final locked = reorderFolderEntries(entries, 2, 0, moveMainList: false);
    expect(locked.folders.map((folder) => folder.id), [8, 7]);
    expect(locked.mainChatListPosition, 0);

    final free = reorderFolderEntries(entries, 2, 0);
    expect(free.folders.map((folder) => folder.id), [8, 7]);
    expect(free.mainChatListPosition, 1);
  });

  testWidgets('a long folder order sheet scrolls from the row body', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final folders = [
      for (var id = 1; id <= 24; id++) folderRecord(id, 'Folder $id'),
    ];
    await pumpSheet(tester, folders);

    expect(find.text('Folder 24'), findsNothing);
    // The row body must belong to the scroll view, not to a drag listener;
    // dragging it used to start a reorder instead of scrolling.
    expect(
      find.descendant(
        of: find.byType(ReorderableDragStartListener),
        matching: find.text('Folder 1'),
      ),
      findsNothing,
      reason: 'only the grip may start a reorder',
    );

    await tester.drag(
      find.byKey(const ValueKey('chat-folder-order-main')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();

    expect(find.text('Folder 24'), findsOneWidget);
  });

  testWidgets('without Premium the All row is locked and cannot start a drag', (
    tester,
  ) async {
    await pumpSheet(tester, [
      folderRecord(7, 'Business'),
    ], canMoveMainList: false);

    final mainRow = find.byKey(const ValueKey('chat-folder-order-main'));
    expect(
      find.descendant(
        of: mainRow,
        matching: find.byType(ReorderableDragStartListener),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: mainRow,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.icon == HeroAppIcons.lock,
        ),
      ),
      findsOneWidget,
    );
    // Real folders keep their grip.
    expect(find.byType(ReorderableDragStartListener), findsOneWidget);
  });

  testWidgets('a locked main list is saved at position 0 even when a folder '
      'is dropped above it', (tester) async {
    tester.view.physicalSize = const Size(1170, 1600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final sent = <Map<String, dynamic>>[];
    await pumpSheet(
      tester,
      [folderRecord(7, 'Alpha'), folderRecord(8, 'Beta')],
      canMoveMainList: false,
      service: recordingService(sent),
    );

    final grip = find.byKey(const ValueKey('chat-folder-order-grip-8'));
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await tester.pump();
    for (var step = 0; step < 12; step++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final reorder = sent.lastWhere(
      (request) => request['@type'] == 'reorderChatFolders',
    );
    expect(reorder['chat_folder_ids'], [8, 7]);
    expect(reorder['main_chat_list_position'], 0);
    expect(find.text('All chats'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('an unlocked All row reports the position it was dropped at', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 1600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final positions = <int>[];
    await pumpSheet(tester, [
      folderRecord(7, 'Alpha'),
      folderRecord(8, 'Beta'),
    ], onMainListPositionSaved: positions.add);

    final grip = find.byKey(const ValueKey('chat-folder-order-grip-main'));
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await tester.pump();
    for (var step = 0; step < 12; step++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(positions, isNotEmpty);
    expect(positions.last, greaterThan(0));
  });

  testWidgets('the order sheet draws each folder\'s own icon', (tester) async {
    await pumpSheet(tester, [
      folderRecord(7, 'Business', icon: 'Cat'),
      folderRecord(8, 'Home', icon: 'Home'),
    ]);

    final names = tester
        .widgetList<ChatFolderIcon>(find.byType(ChatFolderIcon))
        .map((icon) => icon.name)
        .toList();
    expect(names, ['All', 'Cat', 'Home']);
  });

  test('local premium keeps the moved All position on this device', () async {
    if (!LocalPremium.isAvailable) return;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    LocalPremium.shared.initialize(prefs);
    LocalPremium.shared.setEnabled(true);
    LocalFolderOrderStore.shared.initialize(prefs);
    LocalFolderOrderStore.shared.clearForTesting();

    final model = ChatListViewModel();
    addTearDown(model.dispose);
    model.meId = 42;
    final update = {
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 7, 'title': 'A'},
        {'id': 8, 'title': 'B'},
      ],
      'main_chat_list_position': 0,
    };
    model.applyUpdateForTesting(update);
    expect(model.filters.map((filter) => filter.folderId), [null, 7, 8]);

    await LocalFolderOrderStore.shared.setPosition(42, 2);
    model.applyUpdateForTesting(update);
    expect(model.filters.map((filter) => filter.folderId), [7, 8, null]);

    // The store stops answering as soon as the switch is off, so the server
    // position is back.
    LocalPremium.shared.setEnabled(false);
    model.applyUpdateForTesting(update);
    expect(model.filters.map((filter) => filter.folderId), [null, 7, 8]);
  });

  testWidgets('settings rows draw each folder\'s own icon', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final updates = await pumpSettings(tester, theme: theme);
    addTearDown(updates.close);

    final names = tester
        .widgetList<ChatFolderIcon>(find.byType(ChatFolderIcon))
        .map((icon) => icon.name)
        .toList();
    expect(names, ['Cat', 'Home']);

    // Without Premium the main-list row is locked.
    final mainRow = find.byKey(const ValueKey('folder-main-list'));
    expect(
      find.descendant(
        of: mainRow,
        matching: find.byType(ReorderableDragStartListener),
      ),
      findsNothing,
    );
  });

  testWidgets('local premium unlocks the All row in settings', (tester) async {
    if (!LocalPremium.isAvailable) return;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    LocalPremium.shared.initialize(prefs);
    LocalPremium.shared.setEnabled(true);
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final updates = await pumpSettings(tester, theme: theme);
    addTearDown(updates.close);

    final mainRow = find.byKey(const ValueKey('folder-main-list'));
    expect(
      find.descendant(
        of: mainRow,
        matching: find.byType(ReorderableDragStartListener),
      ),
      findsOneWidget,
    );
  });
}
