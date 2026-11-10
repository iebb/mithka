//
//  r14: sidebar ghost-mode shortcut.
//
//  1) The drawer sidebar's bottom bar renders the ghost glyph between the
//     proxy button and the day/night toggle in opted-in builds, and never
//     in non-opted builds.
//  2) The desktop rail renders its ghost button right after the theme
//     toggle when (and only when) the callback is provided.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_navigation_rail.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/profile/profile_proxy_button.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/profile/profile_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    await theme.loadSelectedEmojiFontIfAvailable();
    addTearDown(theme.dispose);
  });

  testWidgets('drawer sidebar carries the ghost glyph after 代理', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final drawer = dc.DrawerController();
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);
    addTearDown(auth.dispose);
    addTearDown(drawer.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AppLocaleController>.value(
            value: AppLocaleController(prefs),
          ),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
          ChangeNotifierProvider<AuthManager>.value(value: auth),
          ChangeNotifierProvider<TranslationController>.value(
            value: TranslationController(prefs),
          ),
          ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProfileView(),
        ),
      ),
    );
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    final ghost = find.byKey(const ValueKey('sidebar-ghost-mode-button'));
    if (!_enabled) {
      expect(ghost, findsNothing);
      return;
    }
    expect(ghost, findsOneWidget);
    // Between 代理 and day/night: to the right of the proxy globe.
    final proxy = tester.getCenter(
      find.byKey(const ValueKey('profile-proxy-button')),
    );
    final ghostCenter = tester.getCenter(ghost);
    expect(ghostCenter.dx, greaterThan(proxy.dx));
  });

  testWidgets('desktop rail shows the ghost button only when wired', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: DesktopNavigationRail(
            destinations: const [],
            selection: 0,
            onSelect: (_) {},
            unread: 0,
            onClearUnread: () {},
            onToggleThemeMode: () {},
            onOpenGhostMode: _enabled ? () {} : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ghost = find.byKey(const ValueKey('desktop-ghost-mode-button'));
    if (!_enabled) {
      expect(ghost, findsNothing);
      return;
    }
    expect(ghost, findsOneWidget);
    // Below the theme toggle (higher dy).
    final themeButton = find.byKey(
      const ValueKey('desktop-theme-toggle-button'),
    );
    expect(
      tester.getCenter(ghost).dy,
      greaterThan(tester.getCenter(themeButton).dy),
    );
  });
}
