import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/app/desktop_navigation_rail.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'desktop rail keeps a fixed width and exposes every destination',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController(await SharedPreferences.getInstance());
      addTearDown(theme.dispose);
      var selection = -1;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: 500,
                child: DesktopNavigationRail(
                  destinations: const [
                    DesktopNavigationDestination(
                      label: 'Messages',
                      icon: HeroAppIcons.solidMessage,
                    ),
                    DesktopNavigationDestination(
                      label: 'Contacts',
                      icon: HeroAppIcons.users,
                    ),
                  ],
                  selection: 0,
                  unread: 4,
                  onClearUnread: () {},
                  onSelect: (value) => selection = value,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester
            .getSize(find.byKey(const ValueKey('desktop-navigation-rail')))
            .width,
        desktopNavigationRailWidth,
      );
      expect(find.bySemanticsLabel('Messages'), findsOneWidget);
      expect(find.bySemanticsLabel('Contacts'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Contacts'));
      expect(selection, 1);
    },
  );

  testWidgets(
    'desktop rail switches accounts and opens utilities from anchored menu',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController(await SharedPreferences.getInstance());
      addTearDown(theme.dispose);
      int? selectedAccount;
      var callsOpened = false;
      var settingsOpened = false;
      var themeSelectorOpened = false;
      var themeToggled = false;
      String? selectedLanguage;

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: 500,
                child: DesktopNavigationRail(
                  destinations: const [
                    DesktopNavigationDestination(
                      label: 'Messages',
                      icon: HeroAppIcons.solidMessage,
                    ),
                  ],
                  selection: 0,
                  unread: 0,
                  onClearUnread: () {},
                  onSelect: (_) {},
                  accounts: [
                    AccountSummary(
                      slot: 1,
                      userId: 11,
                      name: 'Alpha',
                      phone: '+1',
                    ),
                    AccountSummary(
                      slot: 2,
                      userId: 22,
                      name: 'Beta',
                      phone: '+2',
                    ),
                  ],
                  activeAccountSlot: 1,
                  onSelectAccount: (slot) => selectedAccount = slot,
                  onAddAccount: () {},
                  themeToggleLabel: 'Toggle appearance',
                  darkMode: true,
                  onToggleThemeMode: () => themeToggled = true,
                  actions: [
                    DesktopNavigationAction(
                      id: 'calls',
                      label: 'Calls',
                      icon: HeroAppIcons.phone,
                      onTap: () => callsOpened = true,
                    ),
                  ],
                  applicationMenuQuickActions: [
                    DesktopNavigationAction(
                      id: 'saved-messages',
                      label: 'Saved Messages',
                      icon: HeroAppIcons.thumbtack,
                      onTap: () {},
                    ),
                    DesktopNavigationAction(
                      id: 'files',
                      label: 'Files',
                      icon: HeroAppIcons.folder,
                      onTap: () {},
                    ),
                    DesktopNavigationAction(
                      id: 'appearance',
                      label: 'Theme',
                      icon: HeroAppIcons.palette,
                      onTap: () => themeSelectorOpened = true,
                    ),
                  ],
                  languageOptions: [
                    for (final entry in const <String, String>{
                      'zh-Hans': '简体中文',
                      'zh-Hant': '繁體中文',
                      'ja': '日本語',
                      'ko': '한국어',
                      'en': 'English',
                      'fr': 'Français',
                      'es': 'Español',
                      'de': 'Deutsch',
                    }.entries)
                      DesktopLanguageMenuOption(
                        id: entry.key,
                        label: entry.value,
                        selected: entry.key == 'en',
                        onTap: () => selectedLanguage = entry.key,
                      ),
                  ],
                  applicationMenuActions: [
                    DesktopNavigationAction(
                      id: 'settings',
                      label: 'Settings',
                      icon: HeroAppIcons.gear,
                      onTap: () => settingsOpened = true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('desktop-account-rail-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('desktop-account-rail-2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('desktop-account-switch-icon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-theme-toggle-button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('desktop-theme-toggle-button')),
      );
      expect(themeToggled, isTrue);

      await tester.tap(find.byKey(const ValueKey('desktop-account-switcher')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-account-switcher-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('desktop-account-2')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('desktop-account-2')));
      await tester.pump();
      expect(selectedAccount, 2);
      expect(
        find.byKey(const ValueKey('desktop-account-switcher-panel')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('desktop-navigation-action-calls')),
      );
      expect(callsOpened, isTrue);
      expect(
        find.byKey(const ValueKey('desktop-navigation-action-settings')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop-application-menu-button')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-application-menu-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-application-quick-saved-messages')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-application-quick-files')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-application-language')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop-application-language')),
      );
      await tester.pump();
      for (final languageId in const [
        'zh-Hans',
        'zh-Hant',
        'ja',
        'ko',
        'en',
        'fr',
        'es',
        'de',
      ]) {
        expect(
          find.byKey(ValueKey('desktop-application-language-$languageId')),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.byKey(const ValueKey('desktop-application-language-ja')),
      );
      await tester.pump();
      expect(selectedLanguage, 'ja');
      expect(
        find.byKey(const ValueKey('desktop-application-menu-panel')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop-application-menu-button')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-application-quick-appearance')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop-application-quick-appearance')),
      );
      await tester.pump();
      expect(themeSelectorOpened, isTrue);
      expect(
        find.byKey(const ValueKey('desktop-application-menu-panel')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop-application-menu-button')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('desktop-application-action-settings')),
      );
      await tester.pump();
      expect(settingsOpened, isTrue);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('desktop-account-switcher')))
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('desktop-theme-toggle-button')),
              )
              .dy,
        ),
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('desktop-theme-toggle-button')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('desktop-application-menu-button')),
              )
              .dy,
        ),
      );
      expect(
        tester
            .getBottomRight(
              find.byKey(const ValueKey('desktop-application-menu-button')),
            )
            .dy,
        greaterThan(470),
      );
    },
  );
}
