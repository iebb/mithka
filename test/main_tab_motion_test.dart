import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/app/main_tab_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/contacts/contacts_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_view.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('rapid main-tab switching preserves the nested tab state', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(800, 1200));
    await _pumpMainShell(tester);

    // The test shell has two main tabs, Messages and Contacts.
    await tester.tapAt(const Offset(600, 1168));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ContactsView), findsOneWidget);

    await tester.tap(find.text('Group chat'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<Text>(find.text('Group chat')).style?.fontWeight,
      FontWeight.w600,
    );

    // Interrupt each transition with another selection. The already-built
    // Contacts navigator must stay mounted throughout the rapid changes.
    await tester.tapAt(const Offset(200, 1168));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(600, 1168));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(200, 1168));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(600, 1168));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ContactsView), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Group chat')).style?.fontWeight,
      FontWeight.w600,
    );
    await _disposeShell(tester);
  });

  testWidgets('reduced motion opens and closes the profile drawer instantly', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(390, 844));
    final harness = await _pumpMainShell(tester, reducedMotion: true);

    var drawerPosition = _closestAncestor<Positioned>(
      tester,
      find.byType(ProfileView),
    );
    expect(drawerPosition.left, closeTo(-343.2, 0.001));

    harness.drawer.open();
    await tester.pump();
    drawerPosition = _closestAncestor<Positioned>(
      tester,
      find.byType(ProfileView),
    );
    expect(drawerPosition.left, 0);

    harness.drawer.close();
    await tester.pump();
    drawerPosition = _closestAncestor<Positioned>(
      tester,
      find.byType(ProfileView),
    );
    expect(drawerPosition.left, closeTo(-343.2, 0.001));
    await _disposeShell(tester);
  });

  testWidgets('reduced motion reveals a tablet detail without an entrance', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(1024, 800));
    await _pumpMainShell(tester, reducedMotion: true, showChannelsTab: true);

    // Move from Messages to Channels. On a tablet this replaces the detail
    // pane as well as the sidebar root.
    await tester.tapAt(const Offset(164, 770));
    await tester.pump();

    final detail = find.byKey(const ValueKey('tablet-channel-empty'));
    expect(detail, findsOneWidget);

    final opacity = _closestAncestor<Opacity>(tester, detail);
    final transform = _closestAncestor<Transform>(tester, detail);
    expect(opacity.opacity, 1);
    expect(transform.transform.getTranslation().x, 0);
    await _disposeShell(tester);
  });
}

class _MainShellHarness {
  const _MainShellHarness({required this.drawer});

  final dc.DrawerController drawer;
}

Future<_MainShellHarness> _pumpMainShell(
  WidgetTester tester, {
  bool reducedMotion = false,
  bool showChannelsTab = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'showChannelsTab': showChannelsTab,
    'showMomentsTab': false,
    'communitiesEnabled': false,
  });
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final accounts = AccountStore(prefs);
  final auth = AuthManager();
  final translation = TranslationController(prefs);
  final drawer = dc.DrawerController();
  final deepLinks = ChatDeepLinkController.shared;
  deepLinks.consumePending();

  addTearDown(theme.dispose);
  addTearDown(accounts.dispose);
  addTearDown(auth.dispose);
  addTearDown(translation.dispose);
  addTearDown(drawer.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: auth),
        ChangeNotifierProvider<TranslationController>.value(value: translation),
        ChangeNotifierProvider<ChatDeepLinkController>.value(value: deepLinks),
        ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
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
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        ),
        home: const MainSplitRootView(),
      ),
    ),
  );
  await tester.pump();
  return _MainShellHarness(drawer: drawer);
}

Future<void> _disposeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Chat-list cache warming uses delayed no-op guards after disposal.
  await tester.pump(const Duration(seconds: 6));
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

T _closestAncestor<T extends Widget>(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  T? result;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is! T) return true;
    result = widget;
    return false;
  });
  return result!;
}
