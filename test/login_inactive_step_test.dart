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

class _PresentationAuth extends AuthManager {
  AuthStep currentStep = const AuthWaitQrCode('');
  int refreshRequests = 0;

  @override
  AuthStep get step => currentStep;

  @override
  void requestQrLogin() => refreshRequests++;

  void showPhone() {
    currentStep = const AuthWaitPhoneNumber();
    notifyListeners();
  }
}

void main() {
  setUpAll(() => L10nFixtures.load().install());

  testWidgets(
    'an outgoing QR step cannot restart QR login',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues({});
      final accounts = AccountStore(await SharedPreferences.getInstance());
      final auth = _PresentationAuth();
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
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppColors.light]),
            home: const LoginView(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      final refresh = find.bySemanticsLabel(
        AppStrings.t(AppStringKeys.loginRefreshQrCode),
      );
      final oldCenter = tester.getCenter(refresh);
      auth.showPhone();
      await tester.pump();
      // The faded-out QR screen remains painted during the switch, but must no
      // longer accept a tap in the space below the shorter incoming phone form.
      await tester.tapAt(oldCenter);
      await tester.pump();
      expect(auth.refreshRequests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
