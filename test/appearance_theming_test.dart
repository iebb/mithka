import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper_view.dart';
import 'package:mithka/chat/link_handler.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theming defaults on and persists its disabled state', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);

    expect(controller.themingEnabled, isTrue);
    controller.themingEnabled = false;
    expect(ThemeController(prefs).themingEnabled, isFalse);
  });

  testWidgets('Appearance keeps theme scope available when theming is off', (
    tester,
  ) async {
    final controller = await _pumpAppearance(tester, themingEnabled: false);

    expect(find.text('Enable Theming'), findsOneWidget);
    expect(find.text('Theme'), findsNothing);
    expect(find.text('Wallpaper'), findsNothing);
    expect(find.text('Use chat theme for UI'), findsNothing);
    expect(find.text('Use themes per account'), findsOneWidget);

    controller.themingEnabled = true;
    await tester.pump();
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Wallpaper'), findsOneWidget);
    expect(find.text('Use chat theme for UI'), findsOneWidget);
    expect(find.text('Use themes per account'), findsOneWidget);
  });

  testWidgets(
    'global wallpaper follows active manual dark theme instead of system light',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'appearanceThemingEnabled': true,
        'appearanceMode': AppearanceMode.dark.name,
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: controller),
            ChangeNotifierProvider(create: (_) => AppIconController(prefs)),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [AppLocalizations.delegate],
            theme: ThemeData(
              brightness: Brightness.light,
              extensions: [AppColors.light],
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              extensions: [AppColors.dark],
            ),
            themeMode: ThemeMode.dark,
            home: const AppearanceView(),
          ),
        ),
      );
      await tester.pump();

      // The test platform remains light. The wallpaper slot must nevertheless
      // follow the manually selected app theme, matching Telegram iOS.
      expect(tester.platformDispatcher.platformBrightness, Brightness.light);
      final wallpaperRow = find.text('Wallpaper');
      await tester.ensureVisible(wallpaperRow);
      await tester.tap(wallpaperRow);
      await tester.pumpAndSettle();

      final picker = tester.widget<ChatWallpaperView>(
        find.byType(ChatWallpaperView),
      );
      expect(picker.forDarkTheme, isTrue);
      expect(
        find.byKey(const ValueKey('global-wallpaper-brightness-picker')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Appearance uses a distinct icon for every navigation row', (
    tester,
  ) async {
    await _pumpAppearance(tester, themingEnabled: true);

    for (final icon in const [
      HeroAppIcons.wandMagicSparkles,
      HeroAppIcons.palette,
      HeroAppIcons.image,
      HeroAppIcons.mobileScreenButton,
      HeroAppIcons.users,
      HeroAppIcons.expand,
      HeroAppIcons.eye,
      HeroAppIcons.font,
    ]) {
      expect(find.byIcon(icon.data), findsOneWidget, reason: '$icon is reused');
    }
  });

  testWidgets('Display settings does not reuse row icons', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: _testApp(const DisplaySettingsView()),
      ),
    );
    await tester.pump();

    for (final icon in const [
      HeroAppIcons.flash,
      HeroAppIcons.eyeSlash,
      HeroAppIcons.listCheck,
      HeroAppIcons.idBadge,
      HeroAppIcons.palette,
      HeroAppIcons.solidFaceSmile,
      HeroAppIcons.wandMagicSparkles,
      HeroAppIcons.star,
    ]) {
      expect(find.byIcon(icon.data), findsOneWidget, reason: '$icon is reused');
    }
    expect(find.text('Play Animated Status Emoji'), findsOneWidget);
  });

  testWidgets('theme-link prompt only enables theming after confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'appearanceThemingEnabled': false});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    var result = false;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: _testApp(
          Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('open-theme-link'),
              onTap: () async {
                result = await ensureThemingEnabledForThemeLink(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-theme-link')));
    await tester.pumpAndSettle();
    expect(find.text('Enable Theming?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(controller.themingEnabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('open-theme-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(controller.themingEnabled, isTrue);
  });
}

Future<ThemeController> _pumpAppearance(
  WidgetTester tester, {
  required bool themingEnabled,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    'appearanceThemingEnabled': themingEnabled,
  });
  final prefs = await SharedPreferences.getInstance();
  final controller = ThemeController(prefs);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider(create: (_) => AppIconController(prefs)),
      ],
      child: _testApp(const AppearanceView()),
    ),
  );
  await tester.pump();
  return controller;
}

Widget _testApp(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [AppLocalizations.delegate],
  theme: ThemeData(brightness: Brightness.light, extensions: [AppColors.light]),
  home: child,
);
