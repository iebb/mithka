import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/privacy_security/ghost_mode_controller.dart';
import 'package:mithka/settings/privacy_security/ghost_mode_settings_view.dart';
import 'package:mithka/settings/privacy_security/privacy_security_view.dart';
import 'package:mithka/settings/privacy_security/sensitive_content_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enabled-build variant: run with
/// `flutter test --dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true
/// test/ghost_mode_settings_enabled_test.dart`. Every test self-skips when
/// the define is absent so the default CI run stays green.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final requests = <Map<String, dynamic>>[];

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (_) async => <String, dynamic>{'@type': 'error'},
        send: (request) async => requests.add(request),
        updates: updates.stream,
      ),
    );
  });

  setUp(() async {
    requests.clear();
    SharedPreferences.setMockInitialValues({});
    GhostModeController.shared.initialize(
      await SharedPreferences.getInstance(),
    );
  });

  tearDownAll(() async {
    await GhostModeController.shared.setGlobalEnabled(false);
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  if (!allowTelegramTosViolations) {
    test('skipped: this file requires I_DONT_FUCKING_CARE_ABOUT_TOS', () {
      expect(allowTelegramTosViolations, isFalse);
    });
    return;
  }

  Future<void> pumpPrivacy(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<SensitiveContentController>.value(
            value: SensitiveContentController.shared,
          ),
        ],
        child: const MaterialApp(
          locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: PrivacySecurityView(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('privacy screen shows the ghost mode row', (tester) async {
    await pumpPrivacy(tester);

    expect(find.text('隐身模式'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ghost settings screen renders the switches', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
        ],
        child: const MaterialApp(
          locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: GhostModeSettingsView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('ghost-mode-master')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ghost-mode-add-exception')),
      findsOneWidget,
    );
    expect(find.text('已读回执'), findsOneWidget);
    expect(find.text('快拍浏览'), findsOneWidget);
    expect(find.text('输入状态'), findsOneWidget);
    expect(find.text('在线状态'), findsOneWidget);
    expect(find.text('所有聊天均遵循上方开关。'), findsOneWidget);

    // Toggling the master switch flips the controller (and not, while the
    // proxy answers generically, anything else).
    await tester.tap(find.byKey(const ValueKey('ghost-mode-master')));
    await tester.pump();
    expect(GhostModeController.shared.globalEnabled, isTrue);
    await tester.tap(find.byKey(const ValueKey('ghost-mode-master')));
    await tester.pump();
    expect(GhostModeController.shared.globalEnabled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
