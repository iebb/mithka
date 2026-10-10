import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_proxy_button.dart';
import 'package:mithka/profile/profile_view.dart';
import 'package:mithka/settings/proxy_status.dart';
import 'package:mithka/settings/proxy_view.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_motion.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _savedProxy({required bool enabled}) => {
  '@type': 'addedProxy',
  'id': 7,
  'last_used_date': 0,
  'is_enabled': enabled,
  'comment': '',
  'proxy': {
    '@type': 'proxy',
    'server': '10.0.0.1',
    'port': 1080,
    'type': {'@type': 'proxyTypeSocks5'},
  },
};

Map<String, dynamic> _connectionUpdate(String state) => {
  '@type': 'updateConnectionState',
  'state': {'@type': state},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controller = ProxyStatusController.shared;
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  var proxies = <Map<String, dynamic>>[];
  var connectionState = 'connectionStateReady';

  setUpAll(() {
    // Keep the sidebar proxy entry entirely off a real Telegram account.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getProxies' => {'@type': 'proxies', 'proxies': proxies},
          'getConnectionState' => {'@type': connectionState},
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Test'},
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  setUp(() {
    controller.debugReset();
    proxies = const [];
    connectionState = 'connectionStateReady';
  });

  /// Lets the button's own queries land without a frame of animation.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// Pumps the button on its own and reads the state it was handed.
  ///
  /// The shared controller keeps tracking after the first test in this file
  /// builds it, so the reading is refreshed explicitly instead of relying on
  /// whichever mount happened to start the tracking.
  Future<void> pumpButton(WidgetTester tester, {VoidCallback? onTap}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: Center(child: ProfileProxyButton(onTap: onTap ?? () {})),
        ),
      ),
    );
    await controller.refresh();
    await settle(tester);
  }

  testWidgets('no saved proxy leaves the globe bare', (tester) async {
    await pumpButton(tester);
    expect(find.byKey(const ValueKey('profile-proxy-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-proxy-icon')), findsOneWidget);
    for (final badge in const [
      'profile-proxy-badge-connected',
      'profile-proxy-badge-connecting',
      'profile-proxy-badge-off',
      'profile-proxy-badge-unreachable',
    ]) {
      expect(find.byKey(ValueKey(badge)), findsNothing, reason: badge);
    }
    expect(
      find.byTooltip(AppStrings.t(AppStringKeys.proxyTitle)),
      findsOneWidget,
    );
  });

  testWidgets('each proxy state paints its own badge and label', (
    tester,
  ) async {
    final cases = <({String badge, String state, bool enabled, String label})>[
      (
        badge: 'profile-proxy-badge-off',
        state: 'connectionStateReady',
        enabled: false,
        label: AppStringKeys.proxyStatusOff,
      ),
      (
        badge: 'profile-proxy-badge-connecting',
        state: 'connectionStateConnectingToProxy',
        enabled: true,
        label: AppStringKeys.proxyStatusConnecting,
      ),
      (
        badge: 'profile-proxy-badge-connected',
        state: 'connectionStateReady',
        enabled: true,
        label: AppStringKeys.proxyStatusConnected,
      ),
      (
        badge: 'profile-proxy-badge-unreachable',
        state: 'connectionStateWaitingForNetwork',
        enabled: true,
        label: AppStringKeys.proxyStatusUnreachable,
      ),
    ];
    for (final entry in cases) {
      proxies = [_savedProxy(enabled: entry.enabled)];
      connectionState = entry.state;
      await pumpButton(tester);
      expect(
        find.byKey(ValueKey(entry.badge)),
        findsOneWidget,
        reason: '${entry.state} enabled=${entry.enabled}',
      );
      final title = AppStrings.t(AppStringKeys.proxyTitle);
      expect(
        find.byTooltip('$title · ${AppStrings.t(entry.label)}'),
        findsOneWidget,
        reason: entry.label,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a pushed connection state repaints the badge in place', (
    tester,
  ) async {
    proxies = [_savedProxy(enabled: true)];
    await pumpButton(tester);
    expect(
      find.byKey(const ValueKey('profile-proxy-badge-connected')),
      findsOneWidget,
    );

    // No rebuild of anything above the button: TDLib pushed, the badge moved.
    connectionState = 'connectionStateConnectingToProxy';
    updates.add(_connectionUpdate('connectionStateConnectingToProxy'));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('profile-proxy-badge-connecting')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-proxy-badge-connected')),
      findsNothing,
    );

    connectionState = 'connectionStateWaitingForNetwork';
    updates.add(_connectionUpdate('connectionStateWaitingForNetwork'));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('profile-proxy-badge-unreachable')),
      findsOneWidget,
    );
  });

  testWidgets('tapping reports to the owner', (tester) async {
    var tapped = 0;
    await pumpButton(tester, onTap: () => tapped++);
    await tester.tap(find.byKey(const ValueKey('profile-proxy-button')));
    expect(tapped, 1);
  });

  testWidgets('the connecting badge spins with the owned indicator', (
    tester,
  ) async {
    proxies = [_savedProxy(enabled: true)];
    connectionState = 'connectionStateConnectingToProxy';
    await pumpButton(tester);

    final badge = find.byKey(const ValueKey('profile-proxy-badge-connecting'));
    expect(badge, findsOneWidget);
    expect(tester.widget(badge), isA<AppActivityIndicator>());
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the sidebar puts 代理 between 设置 and the day/night switch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'showMomentsTab': false,
      'communitiesEnabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final translation = TranslationController(prefs);
    final locale = AppLocaleController(prefs);
    final drawer = dc.DrawerController();
    for (final owned in [theme, accounts, auth, translation, locale, drawer]) {
      addTearDown(owned.dispose);
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
          ChangeNotifierProvider<AuthManager>.value(value: auth),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
          ChangeNotifierProvider<AppLocaleController>.value(value: locale),
          ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.8)),
            child: child!,
          ),
          home: const Scaffold(body: ProfileView()),
        ),
      ),
    );
    await settle(tester);

    final settings = find.byTooltip(
      AppStrings.t(AppStringKeys.profileSettings),
    );
    final proxy = find.byKey(const ValueKey('profile-proxy-button'));
    final night = find.byTooltip(AppStrings.t(AppStringKeys.profileNightMode));
    expect(settings, findsOneWidget);
    expect(proxy, findsOneWidget);
    expect(night, findsOneWidget);
    final settingsCenter = tester.getCenter(settings);
    final proxyCenter = tester.getCenter(proxy);
    final nightCenter = tester.getCenter(night);
    expect(settingsCenter.dx, lessThan(proxyCenter.dx));
    expect(proxyCenter.dx, lessThan(nightCenter.dx));
    // One bar, one row.
    expect(proxyCenter.dy, settingsCenter.dy);
    expect(proxyCenter.dy, nightCenter.dy);

    // The same bar shows the live status once a proxy is switched on.
    proxies = [_savedProxy(enabled: true)];
    await controller.refresh();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('profile-proxy-badge-connected')),
      findsOneWidget,
    );

    await tester.tap(proxy);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProxyView), findsOneWidget);
    // The owned route helper, so 代理 enters with Mithka's transition and keeps
    // the native back gesture, exactly like the settings entry for it.
    expect(
      ModalRoute.of(tester.element(find.byType(ProxyView))),
      isA<AppPageRoute<void>>(),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    // Let the drawer's deferred account refresh finish against the mock
    // transport after disposing the app.
    await tester.pump(const Duration(seconds: 6));
  });
}
