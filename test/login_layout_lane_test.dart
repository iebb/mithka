import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/auth/login_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/language_settings_view.dart';
import 'package:mithka/settings/proxy_view.dart';
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
  setUpAll(() => L10nFixtures.load().install());

  for (final size in [const Size(390, 844), const Size(780, 720)]) {
    testWidgets(
      'login language and proxy actions have distinct icons and destinations at $size',
      (tester) async {
        addTearDown(() => AppStrings.setLocale(const Locale('en')));
        await _pumpLogin(tester, size, 1);
        await tester.enterText(find.byType(TextField), '+35057123456');
        await tester.pump();
        final phone = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        final language = find.byKey(const ValueKey('login-language'));
        final proxy = find.byKey(const ValueKey('login-proxy'));
        AppIcon icon(Finder action) => tester.widget<AppIcon>(
          find.descendant(of: action, matching: find.byType(AppIcon)),
        );
        expect(icon(language).icon.data, HeroAppIcons.globe.data);
        expect(icon(proxy).icon.data, HeroAppIcons.networkWired.data);
        await tester.ensureVisible(language);
        await tester.tap(language);
        await tester.pumpAndSettle();
        expect(find.byType(AppLanguageSettingsView), findsOneWidget);
        await tester.tap(
          find.text(AppStrings.t(AppStringKeys.appLocaleJapanese)),
        );
        await tester.pumpAndSettle();
        final pickerContext = tester.element(
          find.byType(AppLanguageSettingsView),
        );
        expect(
          pickerContext.read<AppLocaleController>().locale,
          const Locale('ja'),
        );
        expect(
          (await SharedPreferences.getInstance()).getString('app.locale'),
          'ja',
        );
        Navigator.of(pickerContext).pop();
        await tester.pumpAndSettle();
        expect(phone.text, '+350 57123456');
        expect(
          find.text(
            L10nFixtures.load().messages('ja')['loginTelegramAccountTitle']!,
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(proxy);
        await tester.tap(proxy);
        await tester.pumpAndSettle();
        expect(find.byType(ProxyEditView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'phone keeps the full-width form inside the screen padding',
    (tester) async {
      final button = await _pumpLogin(tester, const Size(390, 844), 3);
      expect(tester.getSize(button).width, 390 - 48);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'tablet uses a touch-sized sidebar and caps the form width',
    (tester) async {
      final button = await _pumpLogin(tester, const Size(834, 1112), 2);
      final size = tester.getSize(button);
      // Literal cap: this must fail against the pre-lane code, which let the
      // button stretch to the full tablet window.
      expect(size.width, lessThanOrEqualTo(420));
      expect(size.width, greaterThan(300));
      expect(tester.getRect(button).left, greaterThan(184));
      expect(tester.getSize(_method('phoneNumber')).height, 44);
      expect(size.height, 44);
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
      expect(
        find.text(AppStrings.t(AppStringKeys.loginTelegramAccountTitle)),
        findsOneWidget,
      );
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
      expect(find.byType(TextField), findsOneWidget);
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
    'phone method switch has icons, one selected label and touch targets',
    (tester) async {
      await _pumpLogin(tester, const Size(390, 844), 3);
      for (final method in ['phoneNumber', 'qrCode', 'botToken']) {
        expect(_method(method), findsOneWidget);
        expect(
          tester.getSize(_method(method)).height,
          greaterThanOrEqualTo(44),
        );
        expect(tester.getSize(_method(method)).width, greaterThanOrEqualTo(44));
        expect(
          find.descendant(of: _method(method), matching: find.byType(AppIcon)),
          findsOneWidget,
        );
      }
      expect(_surface(tester, 'phoneNumber').selected, isTrue);
      expect(
        find.text(AppStrings.t(AppStringKeys.loginMethodPhoneNumber)),
        findsOneWidget,
      );
      expect(
        find.text(AppStrings.t(AppStringKeys.loginMethodQrCode)),
        findsNothing,
      );
      expect(
        find.text(AppStrings.t(AppStringKeys.loginBotToken)),
        findsNothing,
      );
      expect(
        find.text(AppStrings.t(AppStringKeys.loginTelegramAccountTitle)),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'phone method switch opens bot login and returns to the phone',
    (tester) async {
      await _pumpLogin(tester, const Size(390, 844), 3);
      await tester.tap(_method('botToken'));
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.t(AppStringKeys.loginBotAccountTitle)),
        findsOneWidget,
      );
      expect(_surface(tester, 'botToken').selected, isTrue);
      await tester.tap(_method('phoneNumber'));
      await tester.pumpAndSettle();
      expect(_surface(tester, 'phoneNumber').selected, isTrue);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'phone entry formats Gibraltar mobile numbers with a country separator',
    (tester) async {
      await _pumpLogin(tester, const Size(390, 844), 1);
      await tester.enterText(find.byType(TextField), '+35057123456');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '+350 57123456',
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'folding preserves the entered number and selects the matching layout',
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
        final method = tester.getRect(_method('phoneNumber'));
        final submit = tester.getRect(
          find.bySemanticsLabel(
            AppStrings.t(AppStringKeys.loginGetVerificationCode),
          ),
        );
        if (size.width >= 740) {
          expect(submit.left, greaterThan(method.right));
        } else {
          expect(submit.top, greaterThan(method.bottom));
        }
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'small phone keeps get code above the keyboard and terms scrollable',
    (tester) async {
      final button = await _pumpLogin(
        tester,
        const Size(320, 568),
        1,
        keyboardHeight: 216,
        safeTop: 20,
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.getRect(button).bottom, lessThan(568 - 216));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.ensureVisible(
        find.text(AppStrings.t(AppStringKeys.loginTermsButton)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'Duo sidebar stays scrollable when the keyboard leaves little height',
    (tester) async {
      await _pumpLogin(
        tester,
        const Size(740, 600),
        1,
        keyboardHeight: 320,
        safeTop: 24,
        textScale: 1.5,
      );
      final sidebar = find.byKey(const ValueKey('login-sidebar-scroll'));
      expect(sidebar, findsOneWidget);
      expect(
        tester.getSize(_method('phoneNumber')).height,
        greaterThanOrEqualTo(44),
      );
      await tester.ensureVisible(
        find.text(AppStrings.t(AppStringKeys.loginTermsButton)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'method icons retain labels and cannot switch during authentication',
    (tester) async {
      final auth = _PhoneStepAuth()..working = true;
      addTearDown(auth.dispose);
      await _pumpLogin(tester, const Size(320, 568), 1, auth: auth);
      for (final method in ['phoneNumber', 'qrCode', 'botToken']) {
        expect(_surface(tester, method).semanticLabel, isNotEmpty);
        expect(_surface(tester, method).enabled, isFalse);
      }
      await tester.tap(_method('qrCode'));
      await tester.pump();
      expect(auth.qrRequests, 0);
      expect(_surface(tester, 'phoneNumber').selected, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final size in [
    const Size(320, 568),
    const Size(780, 720),
    const Size(844, 390),
  ]) {
    testWidgets(
      'login steps fit $size with larger German text in both themes',
      (tester) async {
        final auth = _PhoneStepAuth();
        addTearDown(auth.dispose);
        for (final brightness in Brightness.values) {
          await _pumpLogin(
            tester,
            size,
            1,
            auth: auth,
            brightness: brightness,
            textScale: 1.5,
            locale: const Locale('de'),
          );
          for (final step in <AuthStep>[
            const AuthWaitPhoneNumber(),
            const AuthWaitQrCode('tg://login?token=design-preview'),
            const AuthWaitCode(AuthCodeInfo.fallback),
            const AuthWaitPassword('Example hint'),
            const AuthWaitEmailAddress(
              allowAppleId: false,
              allowGoogleId: false,
            ),
            const AuthWaitEmailCode(
              allowAppleId: false,
              allowGoogleId: false,
              emailPattern: 'e***@example.com',
              length: 6,
              canReset: true,
              resetWaitSeconds: 0,
              resetPending: false,
            ),
            const AuthWaitRegistration(),
            const AuthMissingCredentials(),
          ]) {
            auth.showStep(step);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              tester.takeException(),
              isNull,
              reason: '$brightness ${step.runtimeType}',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
}

Finder _method(String name) => find.byKey(ValueKey('login-method-$name'));

AppInteractiveSurface _surface(WidgetTester tester, String name) =>
    tester.widget<AppInteractiveSurface>(_method(name));

Future<Finder> _pumpLogin(
  WidgetTester tester,
  Size logical,
  double dpr, {
  _PhoneStepAuth? auth,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Locale locale = const Locale('en'),
  double keyboardHeight = 0,
  double safeTop = 0,
}) async {
  await tester.binding.setSurfaceSize(logical);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = Size(logical.width * dpr, logical.height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight * dpr);
  tester.view.padding = FakeViewPadding(top: safeTop * dpr);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetPadding);
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
          locale: controller.locale ?? locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: brightness,
            extensions: [
              brightness == Brightness.light ? AppColors.light : AppColors.dark,
            ],
          ),
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
