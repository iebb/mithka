import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// The emoji-font picker lives BEHIND 外观 → 字体 only: the appearance page
/// itself must not carry a direct emoji row (the user removed the duplicate
/// entry; the font-settings second-level row is the single entry).
void main() {
  setUpAll(() => L10nFixtures.load().install());

  testWidgets('appearance page has no direct emoji font row', (tester) async {
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
    await tester.pump(const Duration(milliseconds: 400));
    // The removed row must stay gone no matter how far the list scrolls.
    await tester.scrollUntilVisible(
      find.byType(ColoredBox).first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('appearance-emoji-font-row')),
      findsNothing,
    );

    // The second-level entry survives: 外观 → 字体 → 表情字体.
    final fontRow = find.byKey(const ValueKey('appearance-font-settings-row'));
    await tester.scrollUntilVisible(fontRow, -200);
    await tester.pump(const Duration(milliseconds: 200));
    final fontTitle = find.descendant(of: fontRow, matching: find.text('Font'));
    expect(fontTitle, findsOneWidget);
    await tester.tap(fontTitle, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FontSettingsView), findsOneWidget);

    // And the picker still carries its own emoji row there.
    final emojiTitle = find.text('Emoji Font');
    await tester.scrollUntilVisible(emojiTitle, 200);
    await tester.pump(const Duration(milliseconds: 200));
    expect(emojiTitle, findsOneWidget);
    await tester.tap(emojiTitle, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(EmojiFontPickerView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
