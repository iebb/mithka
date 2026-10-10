import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/auth/login_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// The login flow is one centred composition. On tablets and desktop windows
/// it used to stretch edge to edge, turning every control into an unusable
/// full-width bar; the lane cap must hold on every target while phones keep
/// their full-bleed form.
void main() {
  setUpAll(() => L10nFixtures.load().install());

  testWidgets(
    'phone keeps the full-width form inside the screen padding',
    (tester) async {
      final button = await _pumpLogin(tester, const Size(390, 844), 3);
      expect(tester.getSize(button).width, 390 - 48);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'tablet caps the form at the login lane instead of the window edge',
    (tester) async {
      final button = await _pumpLogin(tester, const Size(834, 1112), 2);
      final size = tester.getSize(button);
      // Literal cap: this must fail against the pre-lane code, which let the
      // button stretch to the full tablet window.
      expect(size.width, lessThanOrEqualTo(420));
      expect(size.width, greaterThan(300));
      // The lane is centred, not left-hugged.
      final center = tester.getCenter(button).dx;
      expect((center - 834 / 2).abs(), lessThan(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'desktop caps the form at the login lane instead of the window edge',
    (tester) async {
      final button = await _pumpLogin(tester, const Size(1400, 860), 2);
      expect(tester.getSize(button).width, lessThanOrEqualTo(420));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'the alternate login entrances stay quiet text links',
    (tester) async {
      await _pumpLogin(tester, const Size(390, 844), 3);
      final link = find.bySemanticsLabel(
        AppStrings.t(AppStringKeys.loginWithBotToken),
      );
      expect(link, findsOneWidget);
      expect(tester.getSize(link).height, lessThanOrEqualTo(44));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

Future<Finder> _pumpLogin(WidgetTester tester, Size logical, double dpr) async {
  await tester.binding.setSurfaceSize(logical);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = Size(logical.width * dpr, logical.height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final accounts = AccountStore(prefs);
  final auth = AuthManager();
  addTearDown(accounts.dispose);
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: auth),
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
        home: const LoginView(),
      ),
    ),
  );
  await tester.pump();
  return find.bySemanticsLabel(
    AppStrings.t(AppStringKeys.loginGetVerificationCode),
  );
}
