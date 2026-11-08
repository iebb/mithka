import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/auth/login_view.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// The flow at its phone-number step, where every login entrance is offered.
class _PhoneStepAuth extends AuthManager {
  int qrRequests = 0;
  AuthStep currentStep = const AuthWaitPhoneNumber();
  bool working = false;

  @override
  AuthStep get step => currentStep;

  @override
  bool get isWorking => working;

  @override
  void requestQrLogin() {
    qrRequests++;
    currentStep = const AuthWaitQrCode('tg://login?token=design-preview');
    notifyListeners();
  }

  @override
  Future<bool> switchToPhoneLogin() async {
    currentStep = const AuthWaitPhoneNumber();
    notifyListeners();
    return true;
  }

  void showStep(AuthStep step) {
    currentStep = step;
    notifyListeners();
  }
}

/// The compact form stays touch-sized on phones and adopts a method sidebar
/// on roomy windows without stretching its controls.
void main() {
  setUpAll(() {
    L10nFixtures.load().install();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => request['@type'] == 'getProxies'
            ? {'@type': 'proxies', 'proxies': <Map<String, dynamic>>[]}
            : {'@type': 'ok'},
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  testWidgets(
    'folding preserves the entered phone number',
    (tester) async {
      await _pumpLogin(tester, const Size(390, 844), 1);
      await tester.enterText(find.byType(TextField), '+819012345678');
      await tester.pump();
      final phone = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      final entered = phone.text;
      for (final size in [const Size(780, 720), const Size(390, 844)]) {
        await tester.binding.setSurfaceSize(size);
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller,
          same(phone),
        );
        expect(phone.text, entered);
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'login method cannot switch during authentication',
    (tester) async {
      final auth = _PhoneStepAuth()..working = true;
      addTearDown(auth.dispose);
      await _pumpLogin(tester, const Size(320, 568), 1, auth: auth);
      await tester.tap(_method('qrCode'));
      await tester.pump();
      expect(auth.qrRequests, 0);
      expect(_surface(tester, 'phoneNumber').selected, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

Finder _method(String name) => find.byKey(ValueKey('login-method-$name'));

AppInteractiveSurface _surface(WidgetTester tester, String name) =>
    tester.widget<AppInteractiveSurface>(_method(name));

Future<Finder> _pumpLogin(
  WidgetTester tester,
  Size logical,
  double dpr, {
  _PhoneStepAuth? auth,
}) async {
  await tester.binding.setSurfaceSize(logical);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = Size(logical.width * dpr, logical.height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final accounts = AccountStore(prefs);
  final localeController = AppLocaleController(prefs);
  final themeController = ThemeController(prefs);
  addTearDown(localeController.dispose);
  addTearDown(themeController.dispose);
  final loginAuth = auth ?? _PhoneStepAuth();
  addTearDown(accounts.dispose);
  if (auth == null) addTearDown(loginAuth.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountStore>.value(value: accounts),
        ChangeNotifierProvider<AuthManager>.value(value: loginAuth),
        ChangeNotifierProvider<AppLocaleController>.value(
          value: localeController,
        ),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: Consumer<AppLocaleController>(
        builder: (context, controller, _) => MaterialApp(
          locale: controller.locale ?? const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: const LoginView(),
        ),
      ),
    ),
  );
  await tester.pump();
  return find.bySemanticsLabel(
    AppStrings.t(AppStringKeys.loginGetVerificationCode),
  );
}
