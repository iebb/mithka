import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// The emoji-font entry must live directly on the Appearance page — the user
/// could not find it behind 外观 → 字体 → 表情字体.
void main() {
  setUpAll(() => L10nFixtures.load().install());

  testWidgets('appearance page shows the emoji font row directly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final appIcons = AppIconController(prefs);
    addTearDown(theme.dispose);
    addTearDown(appIcons.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: appIcons),
        ],
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
          home: const AppearanceView(),
        ),
      ),
    );
    // The page keeps running animations (previews, spinner), so settle by
    // fixed frames instead of pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 400));
    // Failing-first: the row did not exist on the appearance page; the picker
    // was only reachable three levels deep through FontSettingsView.
    final row = find.byKey(const ValueKey('appearance-emoji-font-row'));
    final fontRow = find.byKey(const ValueKey('appearance-font-settings-row'));
    await tester.scrollUntilVisible(row, 200);
    expect(row, findsOneWidget);
    // Both rows are adjacent in the same card, so both are live here.
    final fontRect = tester.getCenter(fontRow);
    final emojiRect = tester.getCenter(row);
    expect(emojiRect.dy, greaterThan(fontRect.dy));

    // Tapping it opens the emoji picker surface. The tappable surface is the
    // row's title text (the row widget itself spans a KeyedSubtree whose
    // parent surface eats the tap position finder).
    final emojiTitle = find.descendant(
      of: row,
      matching: find.text('Emoji Font'),
    );
    expect(emojiTitle, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(emojiTitle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(EmojiFontPickerView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
