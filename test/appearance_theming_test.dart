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
      HeroAppIcons.tableCells,
      HeroAppIcons.font,
    ]) {
      expect(find.byIcon(icon.data), findsOneWidget, reason: '$icon is reused');
    }
  });

  testWidgets('Interface settings does not reuse row icons', (tester) async {
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
      HeroAppIcons.users,
      HeroAppIcons.play,
      HeroAppIcons.eyeSlash,
      HeroAppIcons.listCheck,
      HeroAppIcons.idBadge,
      HeroAppIcons.solidFaceSmile,
      HeroAppIcons.wandMagicSparkles,
    ]) {
      expect(find.byIcon(icon.data), findsOneWidget, reason: '$icon is reused');
    }
    expect(find.text('Interface'), findsOneWidget);
    expect(find.text('Interface Size'), findsNothing);
    expect(find.text('Play Animated Status Emoji'), findsNothing);
    expect(find.text('Name colors'), findsNWidgets(2));
  });

  testWidgets('chat and chat-list name color pages use separate defaults', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);

    Future<void> pumpSurface(NameColorSettingsSurface surface) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: _testApp(NameColorSettingsView(surface: surface)),
        ),
      );
      await tester.pump();
    }

    await pumpSurface(NameColorSettingsSurface.chat);
    expect(find.text('Chat name colors'), findsOneWidget);
    expect(find.text('Display color for'), findsOneWidget);
    expect(find.text('Display status'), findsOneWidget);
    expect(controller.chatNameColorAudience, NameColorAudience.allUsers);
    expect(controller.chatStatusEmojiMode, StatusEmojiDisplayMode.static);

    await tester.tap(find.text('Premium users'));
    await tester.pump();
    await tester.tap(find.text('Animated'));
    await tester.pump();
    expect(controller.chatNameColorAudience, NameColorAudience.premium);
    expect(controller.chatStatusEmojiMode, StatusEmojiDisplayMode.animated);

    await pumpSurface(NameColorSettingsSurface.chatList);
    expect(find.text('Chat-list name colors'), findsOneWidget);
    expect(controller.chatListNameColorAudience, NameColorAudience.premium);
    expect(controller.chatListStatusEmojiMode, StatusEmojiDisplayMode.static);
  });

  testWidgets('font and interface sizes have separate live previews', (
    tester,
  ) async {
    await _pumpAppearance(tester, themingEnabled: true);

    final fontSizeRow = find.text('Font Size');
    await tester.ensureVisible(fontSizeRow.first);
    await tester.tap(fontSizeRow.first);
    await tester.pumpAndSettle();

    expect(find.text('Interface Size'), findsNothing);
    expect(find.text('Mithka'), findsOneWidget);
    expect(find.text('Saved Messages'), findsOneWidget);
    expect(find.text('10:42'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    final interfaceSizeRow = find.text('Interface Size');
    await tester.ensureVisible(interfaceSizeRow.first);
    await tester.tap(interfaceSizeRow.first);
    await tester.pumpAndSettle();

    expect(find.text('Font Size'), findsNothing);
    expect(find.text('Saved Messages'), findsOneWidget);
    expect(find.text('10:42'), findsOneWidget);
    expect(find.text('Play Animated Status Emoji'), findsNothing);
  });

  test('Simplified Chinese names the interface size controls explicitly', () {
    expect(AppStrings.tForLocale('zhHans', AppStringKeys.appearanceSize), '界面');
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.appearanceFontSize),
      '字体大小',
    );
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.appearanceInterfaceSize),
      '界面大小',
    );
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
