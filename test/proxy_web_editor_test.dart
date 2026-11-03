import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/settings_selection_row.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/proxy_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10nFixtures.load().install();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: const ProxyEditView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'web editor fixes 443 and validates domain, path and secret',
    (tester) async {
      await pumpEditor(tester);
      final selector = tester.widget<SettingsSelectionRow<String>>(
        find.byKey(const ValueKey('proxy-type-selector')),
      );
      expect(selector.options.map((o) => o.value), contains('web'));
      await selector.onSelected('web');
      await tester.pumpAndSettle();
      expect(find.text('443'), findsOneWidget);
      expect(find.text('Path'), findsOneWidget);
      expect(find.byType(EditableText), findsNWidgets(3));

      Color? saveColor() => tester.widget<Text>(find.text('Save')).style?.color;
      expect(saveColor(), isNot(AppTheme.brand));
      await tester.enterText(find.byType(EditableText).at(0), 'relay.example');
      await tester.enterText(find.byType(EditableText).at(1), 'relay/v2');
      await tester.enterText(
        find.byType(EditableText).at(2),
        '00112233445566778899aabbccddeeff',
      );
      await tester.pump();
      expect(saveColor(), AppTheme.brand);
      await tester.enterText(find.byType(EditableText).at(1), '../escape');
      await tester.pump();
      expect(saveColor(), isNot(AppTheme.brand));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'platforms without a relay host omit the web option',
    (tester) async {
      await pumpEditor(tester);
      final selector = tester.widget<SettingsSelectionRow<String>>(
        find.byKey(const ValueKey('proxy-type-selector')),
      );
      expect(selector.options.map((o) => o.value), isNot(contains('web')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );
}
