//
//  message_action_dropdown_test.dart
//
//  The touch dropdown lays its options out at the reference client's popup scale: 44px
//  rows, 16pt labels, a 20pt glyph and a column that hugs its widest label
//  instead of a 36px pointer row squeezed into 220px. The desktop context menu
//  keeps its compact pointer rows.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_action_menu.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  setUpAll(() => L10nFixtures.load().install());

  ChatMessage message() => ChatMessage(
    id: 1,
    isOutgoing: false,
    text: 'hello',
    date: 1700000000,
    chatId: 100,
    contentType: 'messageText',
  );

  /// Pumps the dropdown with [platform] as the target, resetting the debug
  /// override before the test's invariants are checked.
  Future<List<MessageAction>> pumpMenu(
    WidgetTester tester, {
    required TargetPlatform platform,
    required MessageActionMenuLayout layout,
  }) async {
    final picked = <MessageAction>[];
    debugDefaultTargetPlatformOverride = platform;
    SharedPreferences.setMockInitialValues({});
    final translation = TranslationController(
      await SharedPreferences.getInstance(),
    );
    addTearDown(translation.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<TranslationController>.value(
        value: translation,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: Scaffold(
            body: Center(
              child: MessageActionMenu(
                message: message(),
                isPinned: false,
                layout: layout,
                allowCopyMessageLink: true,
                onSelect: picked.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
    return picked;
  }

  double rowHeight(WidgetTester tester, String action) =>
      tester.getSize(find.byKey(ValueKey('message-action-$action'))).height;

  double surfaceWidth(WidgetTester tester) => tester
      .getSize(find.byKey(const ValueKey('message-action-menu-surface')))
      .width;

  TextStyle labelStyle(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style!;

  testWidgets('touch dropdown gives every option a full-size row', (
    tester,
  ) async {
    await pumpMenu(
      tester,
      platform: TargetPlatform.android,
      layout: MessageActionMenuLayout.vertical,
    );

    expect(
      rowHeight(tester, 'copy'),
      MessageActionMenu.mobileDropdownRowHeight,
    );
    expect(
      labelStyle(tester, 'Copy').fontSize,
      MessageActionMenu.mobileDropdownTextSize,
    );
  });

  testWidgets('touch dropdown hugs its widest label inside the bounds', (
    tester,
  ) async {
    await pumpMenu(
      tester,
      platform: TargetPlatform.android,
      layout: MessageActionMenuLayout.vertical,
    );

    final width = surfaceWidth(tester);
    expect(
      width,
      greaterThanOrEqualTo(MessageActionMenu.mobileDropdownMinWidth),
    );
    expect(width, lessThanOrEqualTo(MessageActionMenu.mobileDropdownMaxWidth));
    expect(width, greaterThan(MessageActionMenu.desktopPreferredWidth));
  });

  testWidgets('desktop context menu keeps its compact pointer rows', (
    tester,
  ) async {
    await pumpMenu(
      tester,
      platform: TargetPlatform.linux,
      layout: MessageActionMenuLayout.vertical,
    );

    expect(rowHeight(tester, 'copy'), 36);
    expect(labelStyle(tester, 'Copy').fontSize, AppTextSize.callout);
    expect(surfaceWidth(tester), MessageActionMenu.desktopPreferredWidth);
  });

  testWidgets('tapping a dropdown row selects its action', (tester) async {
    final picked = await pumpMenu(
      tester,
      platform: TargetPlatform.android,
      layout: MessageActionMenuLayout.vertical,
    );

    await tester.tap(find.byKey(const ValueKey('message-action-forward')));
    await tester.pump();
    expect(picked, [MessageAction.forward]);
  });

  group('theme', () {
    Future<void> pumpIn(WidgetTester tester, ThemeData theme) async {
      SharedPreferences.setMockInitialValues({});
      final translation = TranslationController(
        await SharedPreferences.getInstance(),
      );
      addTearDown(translation.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<TranslationController>.value(
          value: translation,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: theme,
            home: Scaffold(
              body: Center(
                child: MessageActionMenu(
                  message: message(),
                  isPinned: false,
                  layout: MessageActionMenuLayout.vertical,
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    BoxDecoration surfaceOf(WidgetTester tester) =>
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('message-action-menu-surface')),
                )
                .decoration!
            as BoxDecoration;

    testWidgets('day theme floats a light card with dark ink', (tester) async {
      await pumpIn(tester, ThemeData(extensions: [AppColors.light]));
      final decoration = surfaceOf(tester);
      expect(decoration.color, AppColors.light.card);
      expect(
        tester.widget<Text>(find.text('Copy')).style!.color,
        AppColors.light.textPrimary,
      );
    });

    testWidgets('night theme keeps the raised dark surface', (tester) async {
      await pumpIn(
        tester,
        ThemeData(brightness: Brightness.dark, extensions: [AppColors.dark]),
      );
      final decoration = surfaceOf(tester);
      expect(decoration.color, AppColors.dark.navBar);
      expect(
        tester.widget<Text>(find.text('Copy')).style!.color,
        AppColors.dark.textPrimary,
      );
    });
  });

  group('placement', () {
    const bottomSafe = 800.0;
    const topSafe = 0.0;
    const stripHeight = 48.0;
    const gap = 8.0;

    MessageActionOverlayPlacement place({
      Rect? anchor = const Rect.fromLTWH(10, 700, 200, 60),
      double menuHeight = 544,
      bool dropdown = true,
      double strip = stripHeight,
    }) => MessageActionMenu.placeMobileOverlay(
      anchor: anchor,
      preferredMenuHeight: menuHeight,
      stripHeight: strip,
      topSafe: topSafe,
      bottomSafe: bottomSafe,
      viewportHeight: 800,
      menuStartsAtAnchorTop: dropdown,
    );

    test('the strip rides above the menu on every anchor and height', () {
      for (final anchorTop in [0.0, 80.0, 300.0, 500.0, 640.0, 700.0, 760.0]) {
        for (final menuHeight in [40.0, 152.0, 300.0, 544.0, 700.0, 900.0]) {
          for (final dropdown in [true, false]) {
            final placement = place(
              anchor: Rect.fromLTWH(10, anchorTop, 200, 60),
              menuHeight: menuHeight,
              dropdown: dropdown,
            );
            final stripBottom = placement.stripTop + stripHeight;
            expect(
              placement.menuTop,
              greaterThanOrEqualTo(stripBottom),
              reason:
                  'anchor $anchorTop, menu $menuHeight, dropdown $dropdown: '
                  'strip ${placement.stripTop}..$stripBottom, '
                  'menu ${placement.menuTop}',
            );
            expect(placement.stripTop, greaterThanOrEqualTo(topSafe));
            expect(
              placement.menuTop + placement.menuHeight,
              lessThanOrEqualTo(bottomSafe),
              reason: 'anchor $anchorTop, menu $menuHeight, dropdown $dropdown',
            );
          }
        }
      }
    });

    test(
      'a message at the bottom lifts the pair, menu end at the safe area',
      () {
        final placement = place();
        expect(placement.menuHeight, 544);
        expect(placement.menuTop + placement.menuHeight, bottomSafe);
        // The strip sits directly on top of the menu, not over it.
        expect(placement.menuTop, placement.stripTop + stripHeight + gap);
      },
    );

    test('a message with room keeps the strip above the bubble', () {
      final placement = place(
        anchor: const Rect.fromLTWH(10, 300, 200, 60),
        menuHeight: 300,
      );
      expect(placement.stripTop, 300 - stripHeight - gap);
      expect(placement.menuTop, 300);
    });

    test('the grid opens below the bubble and never above the strip', () {
      final placement = place(
        anchor: const Rect.fromLTWH(10, 300, 200, 60),
        menuHeight: 152,
        dropdown: false,
      );
      expect(placement.menuTop, 368);
      expect(placement.menuTop, greaterThan(placement.stripTop + stripHeight));
    });

    test('the grid near the bottom lifts without crossing the strip', () {
      final placement = place(menuHeight: 152, dropdown: false);
      expect(placement.menuTop + placement.menuHeight, bottomSafe);
      expect(
        placement.menuTop,
        greaterThanOrEqualTo(placement.stripTop + stripHeight),
      );
    });

    test('without a strip the menu opens at the bubble', () {
      final placement = place(
        anchor: const Rect.fromLTWH(10, 300, 200, 60),
        strip: 0,
        menuHeight: 200,
      );
      expect(placement.menuTop, 300);
      expect(placement.stripTop, 300);
    });

    test('no anchor centres the pair', () {
      final placement = place(anchor: null, menuHeight: 300, strip: 0);
      expect(placement.menuTop, 250);
      expect(placement.menuHeight, 300);
    });
  });
}
