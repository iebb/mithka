import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/security/local_app_lock_controller.dart';
import 'package:mithka/security/local_app_lock_views.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'PIN setup accepts top-row and numpad digits plus Backspace and Delete',
    (tester) async {
      final harness = await _pumpSetupHarness(tester);

      await tester.tap(find.byKey(_SetupHarness.openButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('Create a 4-digit PIN'), findsOneWidget);

      await _sendKey(tester, LogicalKeyboardKey.digit9);
      await _sendKey(tester, LogicalKeyboardKey.backspace);
      await _sendKey(tester, LogicalKeyboardKey.digit8);
      await _sendKey(tester, LogicalKeyboardKey.delete);
      await _sendKeys(tester, const [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Enter the PIN again to confirm'), findsOneWidget);

      await _sendKeys(tester, const [
        LogicalKeyboardKey.numpad1,
        LogicalKeyboardKey.numpad2,
        LogicalKeyboardKey.numpad3,
        LogicalKeyboardKey.numpad4,
      ]);
      await tester.pumpAndSettle();

      expect(harness.setupResult.value, isTrue);
      expect(harness.controller.enabled, isTrue);
      expect(harness.controller.credential, '1234');
      expect(await harness.controller.verifyCredential('1234'), isTrue);
    },
  );

  testWidgets('PIN setup retains on-screen keypad input', (tester) async {
    final harness = await _pumpSetupHarness(tester);

    await tester.tap(find.byKey(_SetupHarness.openButtonKey));
    await tester.pumpAndSettle();

    await _tapDigits(tester, [2, 4, 6, 8]);
    await tester.pumpAndSettle();
    expect(find.text('Enter the PIN again to confirm'), findsOneWidget);

    await _tapDigits(tester, [2, 4, 6, 8]);
    await tester.pumpAndSettle();

    expect(harness.setupResult.value, isTrue);
    expect(harness.controller.credential, '2468');
    expect(await harness.controller.verifyCredential('2468'), isTrue);
  });
}

Future<_SetupHarness> _pumpSetupHarness(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);

  final controller = _RecordingLocalAppLockController();
  addTearDown(controller.dispose);

  final harness = _SetupHarness(controller: controller, theme: theme);
  addTearDown(harness.setupResult.dispose);
  await tester.pumpWidget(harness);
  return harness;
}

Future<void> _sendKeys(
  WidgetTester tester,
  Iterable<LogicalKeyboardKey> keys,
) async {
  for (final key in keys) {
    await _sendKey(tester, key);
  }
}

Future<void> _sendKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> _tapDigits(WidgetTester tester, Iterable<int> digits) async {
  for (final digit in digits) {
    await tester.tap(find.text('$digit'));
    await tester.pump();
  }
}

class _SetupHarness extends StatelessWidget {
  _SetupHarness({required this.controller, required this.theme});

  static const openButtonKey = ValueKey('open-pin-setup');

  final _RecordingLocalAppLockController controller;
  final ThemeController theme;
  final setupResult = ValueNotifier<bool?>(null);

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<LocalAppLockController>.value(value: controller),
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: openButtonKey,
              onPressed: () async {
                setupResult.value = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const AppLockCredentialSetupView(
                      type: AppLockCredentialType.pin,
                    ),
                  ),
                );
              },
              child: const Text('Open PIN setup'),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RecordingLocalAppLockController extends LocalAppLockController {
  _RecordingLocalAppLockController()
    : super(
        secureRead: (_) async => null,
        secureWrite: (_, _) async {},
        hashRounds: 4,
        platformSupportsBiometrics: false,
      );

  String? credential;
  AppLockCredentialType? recordedType;

  @override
  bool get enabled => credential != null;

  @override
  AppLockCredentialType? get credentialType => recordedType;

  @override
  Future<void> setCredential(AppLockCredentialType type, String value) async {
    recordedType = type;
    credential = value;
    notifyListeners();
  }

  @override
  Future<bool> verifyCredential(String value) async => credential == value;
}
