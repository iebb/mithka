import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/unread_badge_model.dart';
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

  test('chat font size is not pre-scaled before root text scaling', () async {
    SharedPreferences.setMockInitialValues({'fontScale': 1.5});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);

    expect(controller.fontScale, 1.5);
    expect(controller.chatTextSize(16), 16);
  });

  test(
    'interface option is squared while rendering keeps its prior scale',
    () async {
      SharedPreferences.setMockInitialValues({'interfaceScale': 1.5});
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);

      expect(controller.interfaceScale, 2.25);
      expect(controller.renderedInterfaceScale, 1.5);

      controller.interfaceScale = 2.25;
      expect(controller.renderedInterfaceScale, 1.5);
      expect(prefs.getDouble('interfaceScale'), 1.5);
    },
  );

  testWidgets('Appearance is a hub and Theme owns conditional controls', (
    tester,
  ) async {
    final controller = await _pumpAppearance(tester, themingEnabled: false);

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Interface'), findsOneWidget);
    expect(find.text('Interface Size'), findsOneWidget);
    expect(find.text('Font'), findsOneWidget);
    expect(find.text('Message Bubbles'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appearance-message-bubbles-row')),
      findsOneWidget,
    );
    expect(find.text('Enable Theming'), findsNothing);
    expect(find.text('Wallpaper'), findsNothing);
    expect(find.text('Use chat theme for UI'), findsNothing);
    expect(find.text('Use themes per account'), findsNothing);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    expect(find.byType(ThemeSettingsView), findsOneWidget);
    expect(find.text('Enable Theming'), findsOneWidget);
    expect(find.text('Use themes per account'), findsOneWidget);
    expect(find.text('Wallpaper'), findsNothing);
    expect(find.text('Use chat theme for UI'), findsNothing);

    controller.themingEnabled = true;
    await tester.pump();
    expect(find.text('Wallpaper'), findsOneWidget);
    expect(find.text('Message Bubbles'), findsNothing);
    expect(find.text('Use chat theme for UI'), findsNothing);
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
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

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

  testWidgets('Appearance hub uses a distinct icon for every navigation row', (
    tester,
  ) async {
    await _pumpAppearance(tester, themingEnabled: true);

    for (final icon in const [
      HeroAppIcons.palette,
      HeroAppIcons.tableCells,
      HeroAppIcons.expand,
      HeroAppIcons.font,
      HeroAppIcons.message,
    ]) {
      expect(find.byIcon(icon.data), findsOneWidget, reason: '$icon is reused');
    }
  });

  testWidgets('Interface child routes expose live previews without fixtures', (
    tester,
  ) async {
    final controller = await _pumpAppearance(tester, themingEnabled: true);

    await tester.tap(find.text('Interface'));
    await tester.pumpAndSettle();

    expect(find.byType(DisplaySettingsView), findsOneWidget);
    for (final key in const [
      'avatars-sidebar-settings-row',
      'chat-view-settings-row',
      'chat-list-settings-row',
      'unread-badge-settings-row',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    for (final icon in const [
      HeroAppIcons.users,
      HeroAppIcons.message,
      HeroAppIcons.listCheck,
      HeroAppIcons.solidBell,
    ]) {
      expect(find.byIcon(icon.data), findsOneWidget, reason: '$icon is reused');
    }

    Future<void> openChild(String rowKey, String previewKey) async {
      final row = find.byKey(ValueKey(rowKey));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(previewKey)), findsOneWidget);
    }

    Future<void> returnToInterface() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.byType(DisplaySettingsView), findsOneWidget);
    }

    await openChild('avatars-sidebar-settings-row', 'avatars-sidebar-preview');
    expect(find.text('Hide Phone Number in Sidebar'), findsNothing);
    expect(
      find.byKey(const ValueKey('appearance-live-preview-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Mithka Group'), findsNothing);
    expect(find.text('+81 90 1234 5678'), findsNothing);
    controller.hideSidebarPhone = true;
    await tester.pump();
    expect(
      find.byKey(const ValueKey('avatars-sidebar-preview-phone')),
      findsNothing,
    );
    await returnToInterface();

    await openChild('chat-view-settings-row', 'chat-view-preview');
    expect(
      find.byKey(const ValueKey('appearance-live-preview-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Bob Harris'), findsNothing);
    expect(find.text('Jessica'), findsNothing);
    controller.alwaysShowMessageTime = true;
    await tester.pump();
    await returnToInterface();

    await openChild('chat-list-settings-row', 'chat-list-preview');
    expect(
      find.byKey(const ValueKey('chat-list-representative-row')),
      findsOneWidget,
    );
    expect(find.text('Mithka Users'), findsOneWidget);
    expect(find.text('Jennie: See you in the chat'), findsOneWidget);
    final swipeSettings = find.byKey(
      const ValueKey('chat-list-swipe-settings-row'),
    );
    expect(swipeSettings, findsOneWidget);
    await tester.ensureVisible(swipeSettings);
    await tester.tap(swipeSettings);
    await tester.pumpAndSettle();
    expect(find.byType(ChatListGestureSettingsView), findsOneWidget);
    expect(
      find.text(
        '1 finger: chat actions · 2 fingers: folders · 3 fingers: accounts',
      ),
      findsOneWidget,
    );
    expect(
      find.text('1 finger: folders · 3 fingers: accounts'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('chat-list-swipe-mode-switchFolders')),
    );
    await tester.pump();
    expect(controller.chatListSwipeMode, ChatListSwipeMode.switchFolders);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ChatListAppearanceSettingsView), findsOneWidget);
    expect(find.text('Switch folders'), findsOneWidget);
    controller.showChatListSearch = false;
    await tester.pump();
    await returnToInterface();

    await openChild('unread-badge-settings-row', 'unread-badge-preview');
    expect(
      find.byKey(const ValueKey('appearance-live-preview-unavailable')),
      findsOneWidget,
    );
    expect(find.text('99+'), findsNothing);
    controller.capUnreadBadgeAt99 = false;
    await tester.pump();
    expect(find.text('99+'), findsNothing);
    expect(find.text('128'), findsNothing);
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

  testWidgets('unread preview uses the active unread model count', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    final updates = StreamController<Map<String, dynamic>>.broadcast();
    final unread = UnreadBadgeModel(updates: updates.stream)..start();
    addTearDown(() async {
      unread.dispose();
      await updates.close();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider.value(value: unread),
        ],
        child: _testApp(const UnreadBadgeSettingsView()),
      ),
    );
    updates.add({
      '@type': 'updateUnreadMessageCount',
      'chat_list': {'@type': 'chatListMain'},
      'unread_unmuted_count': 128,
    });
    await tester.pump();

    expect(find.text('99+'), findsOneWidget);
    controller.capUnreadBadgeAt99 = false;
    await tester.pump();
    expect(find.text('128'), findsOneWidget);
  });

  testWidgets('font size and scaling have separate top-level pages', (
    tester,
  ) async {
    await _pumpAppearance(tester, themingEnabled: true);

    expect(find.text('Font Size'), findsNothing);
    expect(find.text('Interface Size'), findsOneWidget);

    await tester.tap(find.text('Font'));
    await tester.pumpAndSettle();
    expect(find.byType(FontSettingsView), findsOneWidget);

    final fontSizeRow = find.text('Font Size');
    await tester.ensureVisible(fontSizeRow.first);
    await tester.tap(fontSizeRow.first);
    await tester.pumpAndSettle();

    expect(find.text('Interface Size'), findsNothing);
    expect(
      find.byKey(const ValueKey('font-size-chat-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('font-size-chat-list-preview')),
      findsOneWidget,
    );
    expect(find.text('This is how chat text will look.'), findsOneWidget);
    expect(find.text('Mithka Users'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    final interfaceSizeRow = find.byKey(
      const ValueKey('appearance-scaling-settings-row'),
    );
    await tester.ensureVisible(interfaceSizeRow);
    await tester.tap(interfaceSizeRow);
    await tester.pumpAndSettle();

    expect(find.byType(InterfaceSizeSettingsView), findsOneWidget);
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
