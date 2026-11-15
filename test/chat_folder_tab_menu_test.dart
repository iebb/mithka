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

Future<void> _pumpHome(WidgetTester tester, {bool reduceMotion = false}) async {
  const Widget home = Scaffold(body: SizedBox.shrink());
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
      builder: (context, child) => reduceMotion
          ? MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            )
          : child!,
      home: home,
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

  double scrimOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.ancestor(
          of: find.byKey(const ValueKey('chat-folder-action-scrim')),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  testWidgets(
    'scrim dims the main surface while the menu grows from the tab corner',
    (tester) async {
      await _pumpHome(tester);
      final ctx = tester.element(find.byType(Scaffold));
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
              onSelected: () {},
            ),
          ],
        ).then((_) {}),
      );

      // First frame after the entrance starts: the dim and fade tracks are
      // still near zero, the menu barely visible over the scrim.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(scrimOpacity(tester), lessThan(0.25));
      var fade = tester.widget<FadeTransition>(
        find.ancestor(
          of: find.byKey(const ValueKey('chat-folder-action-menu')),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, lessThan(0.4));

      // Fully entered: the scrim settles at exteraless's 0x60 dim and the
      // menu is opaque; dismissing runs the reverse before the entry goes.
      await tester.pumpAndSettle();
      expect(scrimOpacity(tester), 1.0);
      fade = tester.widget<FadeTransition>(
        find.ancestor(
          of: find.byKey(const ValueKey('chat-folder-action-menu')),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, 1);

      // Dismiss runs the reverse before the overlay entry goes away.
      await tester.tapAt(const Offset(400, 500));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('chat-folder-action-menu')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-folder-action-menu')),
        findsNothing,
      );
    },
  );

  testWidgets('reduced motion shows the menu and scrim instantly', (
    tester,
  ) async {
    await _pumpHome(tester, reduceMotion: true);
    final ctx = tester.element(find.byType(Scaffold));
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
            onSelected: () {},
          ),
        ],
      ).then((_) {}),
    );
    await tester.pump();
    await tester.pump();

    expect(scrimOpacity(tester), 1.0);
    final fade = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.byKey(const ValueKey('chat-folder-action-menu')),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    expect(
      find.byKey(const ValueKey('chat-folder-action-scrim')).evaluate(),
      isNotEmpty,
    );
  });
}
