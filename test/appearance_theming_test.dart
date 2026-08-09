import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_wallpaper_view.dart';
import 'package:mithka/chat/link_handler.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/ui_components.dart';
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

  testWidgets('Appearance is a flat hub and Theme owns conditional controls', (
    tester,
  ) async {
    final controller = await _pumpAppearance(tester, themingEnabled: false);

    // Theme is its own settings entry now, not a row in this hub — it owns
    // the combined theme-and-background preview.
    expect(find.text('Theme'), findsNothing);
    // The old catch-all "Interface" heading is gone: rows now sit under the
    // thing they change — Text, Chat, and Chat List.
    expect(find.text('Interface'), findsNothing);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Interface Size'), findsOneWidget);
    expect(find.text('Font'), findsOneWidget);
    expect(find.text('Message Bubbles'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appearance-message-bubbles-row')),
      findsOneWidget,
    );
    for (final key in const [
      'chat-view-settings-row',
      'chat-list-settings-row',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('unread-badge-settings-row')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('avatars-sidebar-settings-row')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('avatars-sidebar-controls')),
      findsOneWidget,
    );
    expect(find.text('Enable Theming'), findsNothing);
    expect(find.text('Wallpaper'), findsNothing);
    expect(find.text('Use chat theme for UI'), findsNothing);
    expect(find.text('Use themes per account'), findsNothing);

    // Theme is reached from the settings list now rather than from this hub,
    // so push it directly instead of tapping a row that no longer exists.
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(builder: (_) => const ThemeSettingsView()),
          ),
    );
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
            home: const ThemeSettingsView(),
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

  testWidgets('Appearance hub uses owned icons for its navigation rows', (
    tester,
  ) async {
    await _pumpAppearance(tester, themingEnabled: true);

    for (final entry in const {
      'appearance-scaling-settings-row': HeroAppIcons.expand,
      'appearance-font-settings-row': HeroAppIcons.font,
      'chat-view-settings-row': HeroAppIcons.message,
      'chat-list-settings-row': HeroAppIcons.listCheck,
      'appearance-message-bubbles-row': HeroAppIcons.message,
    }.entries) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(entry.key)),
          matching: find.byType(SettingsLeadingIcon),
        ),
        findsOneWidget,
        reason: '${entry.key} does not use the shared line-icon treatment',
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey(entry.key)),
          matching: find.byIcon(entry.value.data),
        ),
        findsOneWidget,
        reason: '${entry.key} does not use its owned icon',
      );
    }
    expect(find.byType(SettingsIconTile), findsNothing);
  });

  testWidgets('Appearance summarizes hidden message bubbles as off', (
    tester,
  ) async {
    final controller = await _pumpAppearance(tester, themingEnabled: true);

    controller.messageBubblesEnabled = false;
    await tester.pump();

    final row = find.byKey(const ValueKey('appearance-message-bubbles-row'));
    expect(
      find.descendant(of: row, matching: find.text('Off')),
      findsOneWidget,
    );
  });

  testWidgets('folder appearance keeps Telegram management out of Mithka', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: _testApp(const ChatFolderSettingsView()),
      ),
    );
    await tester.pump();

    expect(find.text('Chat Folders'), findsOneWidget);
    expect(find.text('Manage folders'), findsNothing);
  });

  testWidgets(
    'Appearance separates sidebar controls from the merged Chat List page',
    (tester) async {
      final controller = await _pumpAppearance(tester, themingEnabled: true);

      expect(find.byType(DisplaySettingsView), findsNothing);
      expect(
        find.byKey(const ValueKey('chat-view-settings-row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat-list-settings-row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('unread-badge-settings-row')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('avatars-sidebar-settings-row')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('avatars-sidebar-controls')),
        findsOneWidget,
      );

      Future<void> returnToAppearance() async {
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        expect(find.byType(AppearanceView), findsOneWidget);
        expect(find.byType(DisplaySettingsView), findsNothing);
      }

      controller.showMemberTags = true;
      controller.showPlainMemberRoleTags = true;
      final chatViewRow = find.byKey(const ValueKey('chat-view-settings-row'));
      await tester.ensureVisible(chatViewRow);
      await tester.tap(chatViewRow);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat-view-preview')), findsOneWidget);
      expect(find.text('Chat View'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('chat-view-preview')),
          matching: find.byType(SettingsPanel),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chat-view-preview-album')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('messageImageAlbumTile--9101')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('messageImageAlbumTile--9102')),
        findsOneWidget,
      );
      expect(find.text('Mira Chen'), findsOneWidget);
      expect(find.text('Album Curator'), findsOneWidget);
      controller.alwaysShowMessageTime = true;
      await tester.pump();
      expect(
        find.byKey(const ValueKey('messageTappedTimestamp')),
        findsOneWidget,
      );
      await tester.longPress(
        find.byKey(const ValueKey('messageImageAlbumTile--9101')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-reaction-bar')), findsOneWidget);
      expect(find.text('👍'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('chat-view-preview-reaction-dismiss')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-reaction-bar')), findsNothing);
      await returnToAppearance();

      final chatListRow = find.byKey(const ValueKey('chat-list-settings-row'));
      await tester.ensureVisible(chatListRow);
      await tester.tap(chatListRow);
      await tester.pumpAndSettle();

      expect(find.byType(ChatListAppearanceSettingsView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-list-merged-controls')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('unread-badge-controls')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('avatars-sidebar-controls')),
        findsNothing,
      );
      for (final previewKey in const [
        'chat-list-preview',
        'unread-badge-preview',
        'avatars-sidebar-preview',
        'appearance-live-preview-unavailable',
      ]) {
        expect(find.byKey(ValueKey(previewKey)), findsNothing);
      }

      expect(find.text('Hide Phone Number in Sidebar'), findsNothing);

      controller.capUnreadBadgeAt99 = false;
      controller.showChatListSearch = false;
      await tester.pump();

      final swipeSettings = find.byKey(
        const ValueKey('chat-list-swipe-settings-row'),
      );
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
      expect(tester.takeException(), isNull);
      await returnToAppearance();

      expect(
        find.byKey(const ValueKey('avatars-sidebar-controls')),
        findsOneWidget,
      );
      expect(find.text('Hide Phone Number in Sidebar'), findsNothing);

      final roundAvatarRow = find
          .descendant(
            of: find.byKey(const ValueKey('avatars-sidebar-controls')),
            matching: find.byType(SettingsSwitchRow),
          )
          .first;
      final initiallyCircular = controller.circularGroupAvatars;
      await tester.tap(roundAvatarRow);
      await tester.pump();
      expect(controller.circularGroupAvatars, isNot(initiallyCircular));
    },
  );

  testWidgets('merged Chat List settings stay usable at phone size', (
    tester,
  ) async {
    await _pumpAppearance(
      tester,
      themingEnabled: true,
      surfaceSize: const Size(402, 874),
    );

    expect(find.text('Chat List'), findsWidgets);
    expect(
      find.byKey(const ValueKey('unread-badge-settings-row')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('avatars-sidebar-settings-row')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('avatars-sidebar-controls')),
      findsOneWidget,
    );
    final chatListRow = find.byKey(const ValueKey('chat-list-settings-row'));
    await tester.ensureVisible(chatListRow);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(chatListRow);
    await tester.pumpAndSettle();
    expect(find.byType(ChatListAppearanceSettingsView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-list-merged-controls')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-list-preview')), findsNothing);
    expect(
      find.byKey(const ValueKey('avatars-sidebar-controls')),
      findsNothing,
    );
    expect(find.text('Hide Phone Number in Sidebar'), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('avatars-sidebar-controls')),
      findsOneWidget,
    );
    expect(find.text('Hide Phone Number in Sidebar'), findsNothing);
    expect(tester.takeException(), isNull);
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
  Size surfaceSize = const Size(900, 1800),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
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
