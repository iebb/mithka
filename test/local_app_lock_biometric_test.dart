import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/security/local_app_lock_controller.dart';
import 'package:mithka/security/local_app_lock_views.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('biometrics unlock without showing or accepting a PIN', (
    tester,
  ) async {
    final harness = await _pumpLock(tester);

    expect(harness.attempts, hasLength(1));
    expect(find.text('2'), findsNothing);
    expect(find.text('Enter your 4-digit PIN'), findsNothing);
    for (final key in const [
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit8,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();
    expect(harness.controller.locked, isTrue);
    expect(harness.controller.failedAttemptCount, 0);

    // Native authentication can temporarily make the app inactive. Resuming
    // must keep the existing prompt, rather than open another one.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(harness.attempts, hasLength(1));
    expect(find.text('2'), findsNothing);

    harness.attempts.single.complete(true);
    await tester.pumpAndSettle();
    expect(harness.controller.locked, isFalse);
    expect(find.text('2'), findsNothing);
  });

  for (final (name, error) in [
    ('failure', null),
    (
      'cancellation',
      const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
    ),
    (
      'passcode fallback request',
      const LocalAuthException(
        code: LocalAuthExceptionCode.userRequestedFallback,
      ),
    ),
    (
      'lockout',
      const LocalAuthException(code: LocalAuthExceptionCode.temporaryLockout),
    ),
    (
      'unavailable hardware',
      const LocalAuthException(
        code: LocalAuthExceptionCode.noBiometricHardware,
      ),
    ),
  ]) {
    testWidgets('biometric $name reveals the PIN without retrying', (
      tester,
    ) async {
      final harness = await _pumpLock(tester);
      expect(find.text('2'), findsNothing);

      if (error == null) {
        harness.attempts.single.complete(false);
      } else {
        harness.attempts.single.completeError(error);
      }
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(harness.controller.locked, isTrue);

      await harness.controller.refreshBiometricAvailability();
      await tester.pumpAndSettle();
      expect(harness.attempts, hasLength(1));
      expect(find.text('2'), findsOneWidget);

      await _enterPin(tester, harness.controller);
      expect(harness.controller.locked, isFalse);
    });
  }

  testWidgets('manual biometric retry hides the PIN again', (tester) async {
    final harness = await _pumpLock(tester);
    harness.attempts.single.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    final context = tester.element(find.byType(LocalAppLockGate));
    await tester.tap(find.text(AppStringKeys.appLockFaceUnlock.l10n(context)));
    await tester.pumpAndSettle();
    expect(harness.attempts, hasLength(2));
    expect(find.text('2'), findsNothing);

    harness.attempts.last.complete(true);
    await tester.pumpAndSettle();
    expect(harness.controller.locked, isFalse);
  });

  testWidgets('each new lock starts with biometrics again', (tester) async {
    final harness = await _pumpLock(tester);
    harness.attempts.single.complete(false);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => harness.controller.unlockWithCredential('2468'),
    );
    await tester.pumpAndSettle();

    harness.controller.lock();
    await tester.pumpAndSettle();
    expect(harness.attempts, hasLength(2));
    expect(find.text('2'), findsNothing);
    harness.attempts.last.complete(true);
    await tester.pumpAndSettle();
    expect(harness.controller.locked, isFalse);
  });

  testWidgets('background lock waits for resume before prompting', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final harness = await _pumpLock(tester);
    expect(harness.attempts, isEmpty);
    expect(find.text('2'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(harness.attempts, hasLength(1));
    expect(find.text('2'), findsNothing);
    harness.attempts.single.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  for (final enabled in [false, true]) {
    testWidgets(
      enabled
          ? 'unavailable biometrics show the PIN immediately'
          : 'disabled biometrics show the PIN immediately',
      (tester) async {
        final harness = await _pumpLock(
          tester,
          biometricEnabled: enabled,
          biometricAvailable: !enabled,
        );
        expect(harness.attempts, isEmpty);
        expect(find.text('2'), findsOneWidget);
      },
    );
  }

  testWidgets('gesture lock also waits for biometrics before fallback', (
    tester,
  ) async {
    final harness = await _pumpLock(
      tester,
      credentialType: AppLockCredentialType.gesture,
    );
    expect(find.byType(GesturePatternPad), findsNothing);
    harness.attempts.single.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(GesturePatternPad), findsOneWidget);
    expect(harness.controller.locked, isTrue);
  });
}

class _LockHarness {
  final attempts = <Completer<bool>>[];
  late final LocalAppLockController controller;
}

Future<void> _enterPin(
  WidgetTester tester,
  LocalAppLockController controller,
) async {
  for (final digit in [2, 4, 6, 8]) {
    await tester.tap(find.text('$digit'));
    await tester.pump();
  }
  // Credential hashing uses a real isolate; drain its result back into the
  // widget test's fake async zone before checking the unlocked UI.
  for (var attempt = 0; attempt < 100 && controller.locked; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<_LockHarness> _pumpLock(
  WidgetTester tester, {
  bool biometricEnabled = true,
  bool biometricAvailable = true,
  AppLockCredentialType credentialType = AppLockCredentialType.pin,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);

  final harness = _LockHarness();
  final storage = <String, String>{};
  var configuring = true;
  final controller = LocalAppLockController(
    secureRead: (key) async => storage[key],
    secureWrite: (key, value) async {
      if (value == null) {
        storage.remove(key);
      } else {
        storage[key] = value;
      }
    },
    biometricProbe: () async => configuring || biometricAvailable
        ? const [BiometricType.face]
        : const [],
    biometricAuthenticate: (_) async {
      if (configuring) return true;
      final attempt = Completer<bool>();
      harness.attempts.add(attempt);
      return attempt.future;
    },
    privacyShieldApply: (_) async {},
    platformSupportsBiometrics: true,
    hashRounds: 4,
  );
  harness.controller = controller;
  addTearDown(controller.dispose);
  await tester.runAsync(() async {
    await controller.initialize();
    await controller.setCredential(
      credentialType,
      credentialType == AppLockCredentialType.pin ? '2468' : '0,1,2,5',
    );
    if (biometricEnabled) {
      await controller.setBiometricEnabled(
        true,
        localizedReason: 'Enable biometric unlock',
      );
    }
    configuring = false;
    await controller.refreshBiometricAvailability();
    controller.lock();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<LocalAppLockController>.value(value: controller),
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
        home: LocalAppLockGate(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}
