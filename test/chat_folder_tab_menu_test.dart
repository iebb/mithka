//
//  chat_folder_tab_menu_test.dart
//
//  The folder tab popup is an anchored menu, not a bottom sheet: it renders
//  every wired command (including the destructive delete row that only a real
//  folder offers), pops itself before invoking the command, closes on a
//  barrier tap, and its placement math keeps the menu inside the viewport
//  below the tab or above it when there is no room.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_folder_tab_menu.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(extensions: [AppColors.light]),
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('popup renders all rows anchored above the barrier', (
    tester,
  ) async {
    await _pumpHome(tester);
    final ctx = tester.element(find.byType(Scaffold));
    var selected = 0;
    unawaited(
      showChatFolderPopupMenu(
        context: ctx,
        anchor: const Rect.fromLTWH(40, 60, 120, 44),
        title: 'Work',
        actions: [
          ChatFolderMenuAction(
            key: 'edit',
            label: 'Edit folder',
            icon: const AppIconData(Icons.edit),
            onSelected: () => selected += 1,
          ),
          ChatFolderMenuAction(
            key: 'delete',
            label: 'Delete folder',
            icon: const AppIconData(Icons.delete),
            destructive: true,
            onSelected: () => selected += 10,
          ),
        ],
      ).then((_) {}),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-folder-action-menu')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-folder-action-edit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-folder-action-delete')),
      findsOneWidget,
    );
    expect(find.text('Work'), findsOneWidget);

    // Selecting a row dismisses the menu before invoking the command.
    await tester.tap(find.byKey(const ValueKey('chat-folder-action-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-folder-action-menu')), findsNothing);
    expect(selected, 10);
  });

  testWidgets('barrier tap dismisses without invoking any command', (
    tester,
  ) async {
    await _pumpHome(tester);
    final ctx = tester.element(find.byType(Scaffold));
    var selected = 0;
    unawaited(
      showChatFolderPopupMenu(
        context: ctx,
        anchor: const Rect.fromLTWH(40, 60, 120, 44),
        title: 'Work',
        actions: [
          ChatFolderMenuAction(
            key: 'edit',
            label: 'Edit folder',
            icon: const AppIconData(Icons.edit),
            onSelected: () => selected += 1,
          ),
        ],
      ).then((_) {}),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(400, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-folder-action-menu')), findsNothing);
    expect(selected, 0);
  });

  test(
    'origin prefers below the anchor and flips above when it cannot fit',
    () {
      const anchor = Rect.fromLTWH(40, 60, 120, 44);
      final menu = Size(200, chatFolderMenuHeightFor(2));
      // Room below on a tall viewport: the menu starts right under the tab.
      final below = chatFolderMenuOriginFor(
        anchor: anchor,
        viewport: const Size(800, 600),
        menuSize: menu,
      );
      expect(below.dy, anchor.bottom + 8);

      // No room below on a short viewport (but room above): the menu flips
      // above the tab.
      final above = chatFolderMenuOriginFor(
        anchor: const Rect.fromLTWH(40, 200, 120, 44),
        viewport: const Size(800, 300),
        menuSize: menu,
      );
      expect(above.dy + menu.height, lessThanOrEqualTo(200));
      expect(above.dy, greaterThanOrEqualTo(8));

      // A viewport too short for either placement still keeps the menu inside.
      final tiny = chatFolderMenuOriginFor(
        anchor: anchor,
        viewport: const Size(800, 120),
        menuSize: menu,
      );
      expect(tiny.dy + menu.height, lessThanOrEqualTo(120 - 8));

      // A tab near the right edge clamps the menu inside the viewport.
      final clamped = chatFolderMenuOriginFor(
        anchor: const Rect.fromLTWH(780, 60, 120, 44),
        viewport: const Size(800, 600),
        menuSize: menu,
      );
      expect(clamped.dx + menu.width, lessThanOrEqualTo(800 - 8));
    },
  );
}
