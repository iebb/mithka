import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/auth/login_view.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// The flow at its phone-number step, where every login entrance is offered.
class _PhoneStepAuth extends AuthManager {
  int qrRequests = 0;

  @override
  AuthStep get step => const AuthWaitPhoneNumber();

  @override
  void requestQrLogin() => qrRequests++;
}

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
    'desktop lays the step out as a left-aligned page beside the sidebar',
    (tester) async {
      final button = await _pumpLogin(tester, const Size(1280, 800), 2);
      final rect = tester.getRect(button);
      final sidebar = tester.getRect(_method('phoneNumber'));
      // The page starts after the sidebar instead of floating mid-window.
      expect(rect.left, greaterThan(sidebar.right));
      expect(rect.left, lessThan(1280 / 3));
      expect(rect.width, 380);
      // Pointer-sized control, not the 52 pt touch bar.
      expect(rect.height, 36);
      final title = find.text(
        AppStrings.t(AppStringKeys.loginTelegramAccountTitle),
      );
      expect(title, findsOneWidget);
      expect(tester.getRect(title).left, rect.left);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'desktop phone number is one large underlined field',
    (tester) async {
      final button = await _pumpLogin(tester, const Size(1280, 800), 2);
      final field = find.byType(TextField).first;
      expect(
        tester.widget<TextField>(field).style?.fontSize,
        AppTextSize.display,
      );
      final shell = find.ancestor(
        of: field,
        matching: find.byType(AnimatedContainer),
      );
      final container = tester.widget<AnimatedContainer>(shell.first);
      // No box: no fill, no radius, only a rule under the text.
      expect(container.decoration, isNull);
      final rule =
          (container.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(rule.top, BorderSide.none);
      expect(rule.left, BorderSide.none);
      expect(rule.bottom.width, greaterThan(0));
      // Larger than the 36 pt controls around it, and flush with the page.
      final rect = tester.getRect(shell.first);
      expect(rect.height, greaterThan(tester.getSize(button).height));
      expect(rect.left, tester.getRect(button).left);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'desktop sidebar holds every way in and marks the current one',
    (tester) async {
      await _pumpLogin(tester, const Size(1280, 800), 2);
      for (final method in ['phoneNumber', 'qrCode', 'botToken']) {
        expect(_method(method), findsOneWidget, reason: method);
      }
      expect(_surface(tester, 'phoneNumber').selected, isTrue);
      expect(_surface(tester, 'qrCode').selected, isFalse);
      // The sidebar replaces the alternate entrances inside the step.
      expect(
        find.bySemanticsLabel(AppStrings.t(AppStringKeys.loginWithQrCode)),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(AppStrings.t(AppStringKeys.loginWithBotToken)),
        findsNothing,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'desktop sidebar switches between the ways in',
    (tester) async {
      await _pumpLogin(tester, const Size(1280, 800), 2);
      final auth =
          Provider.of<AuthManager>(
                tester.element(find.byType(LoginView)),
                listen: false,
              )
              as _PhoneStepAuth;

      await tester.tap(_method('qrCode'));
      await tester.pump();
      expect(auth.qrRequests, 1);

      await tester.tap(_method('botToken'));
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.t(AppStringKeys.loginBotAccountTitle)),
        findsOneWidget,
      );
      expect(_surface(tester, 'botToken').selected, isTrue);

      await tester.tap(_method('phoneNumber'));
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.t(AppStringKeys.loginTelegramAccountTitle)),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'desktop login draws flat fills only',
    (tester) async {
      await _pumpLogin(tester, const Size(1280, 800), 2);
      final decorations = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(LoginView),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>();
      expect(decorations, isNotEmpty);
      for (final decoration in decorations) {
        expect(decoration.gradient, isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'the penguin sits on a neutral surface, never a brand tile',
    (tester) async {
      final phone = defaultTargetPlatform == TargetPlatform.iOS;
      await _pumpLogin(
        tester,
        phone ? const Size(390, 844) : const Size(1280, 800),
        2,
      );
      final penguin = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/penguin.png',
      );
      expect(penguin, findsOneWidget);
      final backdrops = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: penguin,
              matching: find.descendant(
                of: find.byType(LoginView),
                matching: find.byType(DecoratedBox),
              ),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>();
      // Whatever surface the mark sits on is neutral: no gradient and no
      // tinted (brand) fill, only a grey at most.
      for (final decoration in backdrops) {
        expect(decoration.gradient, isNull);
        final color = decoration.color;
        if (color != null) {
          expect(color.r, color.g);
          expect(color.g, color.b);
        }
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'phones keep QR login as the compact corner action',
    (tester) async {
      await _pumpLogin(tester, const Size(390, 844), 3);
      final qr = find.byTooltip(AppStrings.t(AppStringKeys.loginWithQrCode));
      expect(qr, findsOneWidget);
      expect(tester.getSize(qr).width, lessThan(56));
      expect(tester.getCenter(qr).dy, lessThan(120));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
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

Finder _method(String name) => find.byKey(ValueKey('login-method-$name'));

AppInteractiveSurface _surface(WidgetTester tester, String name) =>
    tester.widget<AppInteractiveSurface>(_method(name));

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
  final auth = _PhoneStepAuth();
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
