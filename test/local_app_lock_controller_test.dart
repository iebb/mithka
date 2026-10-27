import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mithka/security/local_app_lock_controller.dart';

void main() {
  test('Android registers the app-lock platform plugins', () {
    final activity = File(
      'android/app/src/main/kotlin/ad/neko/mithka/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('registerPlugins(flutterEngine)'));
    expect(
      activity,
      contains(
        'add("com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin")',
      ),
    );
    expect(
      activity,
      contains('add("io.flutter.plugins.localauth.LocalAuthPlugin")'),
    );
    expect(activity, contains('"mithka/app_lock_privacy"'));
    expect(activity, contains('WindowManager.LayoutParams.FLAG_SECURE'));
  });

  test('four-digit PIN is hashed, verified, and restored as locked', () async {
    final storage = <String, String>{};
    var now = DateTime.utc(2026, 8, 31, 12);
    final controller = _controller(storage, now: () => now);
    await controller.initialize();

    expect(LocalAppLockController.pinLength, 4);
    await controller.setCredential(AppLockCredentialType.pin, '1234');

    expect(controller.enabled, isTrue);
    expect(controller.credentialType, AppLockCredentialType.pin);
    expect(controller.locked, isFalse);
    expect(storage.values.single, isNot(contains('1234')));
    expect(await controller.verifyCredential('1234'), isTrue);
    expect(await controller.verifyCredential('4321'), isFalse);
    expect(await controller.verifyCredential('12345'), isFalse);

    controller.lock();
    expect(controller.locked, isTrue);
    expect(await controller.unlockWithCredential('4321'), isFalse);
    expect(controller.locked, isTrue);
    expect(controller.failedAttemptCount, 1);
    expect(controller.canAttemptCredential, isFalse);
    expect(await controller.unlockWithCredential('1234'), isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(await controller.unlockWithCredential('1234'), isTrue);
    expect(controller.locked, isFalse);
    expect(controller.failedAttemptCount, 0);

    final restored = _controller(storage);
    await restored.initialize();
    expect(restored.enabled, isTrue);
    expect(restored.locked, isTrue);
    expect(await restored.verifyCredential('1234'), isTrue);
  });

  test(
    'failed unlock throttling is progressive and survives restart',
    () async {
      final storage = <String, String>{};
      var now = DateTime.utc(2026, 8, 31, 12);
      final controller = _controller(storage, now: () => now);
      await controller.initialize();
      await controller.setCredential(AppLockCredentialType.pin, '1234');
      controller.lock();

      expect(await controller.unlockWithCredential('0000'), isFalse);
      expect(controller.failedAttemptCount, 1);
      expect(controller.credentialRetryAfter, const Duration(seconds: 1));
      now = now.add(const Duration(seconds: 1));
      expect(await controller.unlockWithCredential('0000'), isFalse);
      expect(controller.failedAttemptCount, 2);
      expect(controller.credentialRetryAfter, const Duration(seconds: 2));

      final restored = _controller(storage, now: () => now);
      await restored.initialize();
      expect(restored.locked, isTrue);
      expect(restored.failedAttemptCount, 2);
      expect(restored.canAttemptCredential, isFalse);
      expect(await restored.unlockWithCredential('1234'), isFalse);

      now = now.add(const Duration(seconds: 2));
      expect(await restored.unlockWithCredential('1234'), isTrue);
      expect(restored.failedAttemptCount, 0);
    },
  );

  test('secure-storage read failures keep the entire app locked', () async {
    final storage = <String, String>{};
    var available = false;
    final controller = LocalAppLockController(
      secureRead: (key) async {
        if (!available) throw StateError('secure storage unavailable');
        return storage[key];
      },
      secureWrite: (key, value) async {
        if (value == null) {
          storage.remove(key);
        } else {
          storage[key] = value;
        }
      },
      privacyShieldApply: (_) async {},
      hashRounds: 4,
      platformSupportsBiometrics: false,
    );

    await controller.initialize();
    expect(controller.initialized, isTrue);
    expect(controller.storageUnavailable, isTrue);
    expect(controller.locked, isTrue);
    expect(await controller.unlockWithCredential('1234'), isFalse);
    controller.unlock();
    expect(controller.locked, isTrue);

    available = true;
    await controller.reloadFromStorage();
    expect(controller.storageUnavailable, isFalse);
    expect(controller.locked, isFalse);
  });

  test(
    'gesture credential preserves node order and rejects short input',
    () async {
      final storage = <String, String>{};
      final controller = _controller(storage);
      await controller.initialize();

      await controller.setCredential(AppLockCredentialType.gesture, '0,1,4,8');

      expect(await controller.verifyCredential('0,1,4,8'), isTrue);
      expect(await controller.verifyCredential('8,4,1,0'), isFalse);
      expect(await controller.verifyCredential('0,1,4'), isFalse);
      expect(
        () => controller.setCredential(AppLockCredentialType.gesture, '0,1,2'),
        throwsArgumentError,
      );
    },
  );

  test('biometric unlock is opt-in and unlocks after native success', () async {
    final storage = <String, String>{};
    var authenticationCount = 0;
    final controller = LocalAppLockController(
      secureRead: (key) async => storage[key],
      secureWrite: (key, value) async {
        if (value == null) {
          storage.remove(key);
        } else {
          storage[key] = value;
        }
      },
      biometricProbe: () async => const [BiometricType.face],
      biometricAuthenticate: (_) async {
        authenticationCount += 1;
        return true;
      },
      privacyShieldApply: (_) async {},
      hashRounds: 4,
      platformSupportsBiometrics: true,
    );
    await controller.initialize();
    await controller.setCredential(AppLockCredentialType.pin, '2468');

    expect(controller.biometricAvailable, isTrue);
    expect(controller.biometricKind, AppLockBiometricKind.face);
    expect(controller.biometricEnabled, isFalse);

    expect(
      await controller.setBiometricEnabled(
        true,
        localizedReason: 'Enable app unlock',
      ),
      AppLockBiometricResult.success,
    );
    expect(controller.biometricEnabled, isTrue);
    expect(authenticationCount, 1);

    controller.lock();
    expect(await controller.unlockWithCredential('0000'), isFalse);
    expect(controller.failedAttemptCount, 1);
    expect(
      await controller.authenticateBiometric(localizedReason: 'Unlock app'),
      AppLockBiometricResult.success,
    );
    expect(controller.locked, isFalse);
    expect(controller.failedAttemptCount, 0);
    expect(authenticationCount, 2);
  });

  test('disabling app lock removes the secure record', () async {
    final storage = <String, String>{};
    final controller = _controller(storage);
    await controller.initialize();
    await controller.setCredential(AppLockCredentialType.pin, '0000');

    await controller.disable();

    expect(controller.enabled, isFalse);
    expect(controller.locked, isFalse);
    expect(storage, isEmpty);
  });

  test(
    'auto-lock options persist, migrate, and shield iOS snapshots',
    () async {
      final storage = <String, String>{};
      final shieldStates = <bool>[];
      final controller = _controller(storage, shieldStates: shieldStates);
      await controller.initialize();
      await controller.setCredential(AppLockCredentialType.pin, '1357');
      await controller.setAutoLockOption(AppLockAutoLockOption.fiveMinutes);

      expect(controller.autoLockOption, AppLockAutoLockOption.fiveMinutes);
      expect(jsonDecode(storage.values.single)['version'], 2);

      controller.handleLifecycleState(AppLifecycleState.paused);
      expect(controller.locked, isFalse);
      expect(shieldStates.last, isTrue);
      controller.handleLifecycleState(AppLifecycleState.resumed);
      expect(shieldStates.last, isFalse);

      final legacy = jsonDecode(storage.values.single) as Map<String, dynamic>;
      legacy
        ..['version'] = 1
        ..remove('autoLockSeconds');
      storage[storage.keys.single] = jsonEncode(legacy);

      final restored = _controller(storage);
      await restored.initialize();
      expect(restored.autoLockOption, AppLockAutoLockOption.disabled);
      expect(jsonDecode(storage.values.single)['version'], 2);
    },
  );

  test(
    'a mobile host without secure storage stays unlocked instead of failing closed',
    () async {
      // flutter_secure_storage has no HarmonyOS port: the platform-interface
      // default throws MissingPluginException on the first read. Nothing was
      // ever persisted, so there is no lock to enforce and no gate a
      // credential could open — the controller must read "not configured",
      // not brick the app behind the storage-unavailable screen.
      final controller = LocalAppLockController(
        secureRead: (key) => throw MissingPluginException(),
        secureWrite: (key, value) => throw MissingPluginException(),
        privacyShieldApply: (visible) async {},
        hashRounds: 4,
        platformSupportsBiometrics: true,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.initialized, isTrue);
      expect(controller.enabled, isFalse);
      expect(controller.locked, isFalse);
      expect(controller.storageUnavailable, isFalse);

      // A later reload (desktop engine sync) must reach the same answer.
      await controller.reloadFromStorage();
      expect(controller.enabled, isFalse);
      expect(controller.locked, isFalse);
      expect(controller.storageUnavailable, isFalse);
    },
  );

  test(
    'a known lock that loses secure storage mid-read fails closed',
    () async {
      // The credential record reads back fine; the failed-attempts record
      // hits a vanished implementation. A lock is known: resetting to "no
      // lock configured" would silently disable existing protection.
      final stored = <String, String>{};
      final enroller = LocalAppLockController(
        secureRead: (key) => Future.value(stored[key]),
        secureWrite: (key, value) async {
          if (value == null) {
            stored.remove(key);
          } else {
            stored[key] = value;
          }
        },
        privacyShieldApply: (visible) async {},
        hashRounds: 4,
        platformSupportsBiometrics: false,
      );
      addTearDown(enroller.dispose);
      await enroller.initialize();
      await enroller.setCredential(AppLockCredentialType.pin, '1234');
      // Keep only the credential record: the attempts read now throws.
      const credentialKey = 'mithka.local_app_lock.v1';
      final credentialRecord = stored[credentialKey]!;
      final reloaded = LocalAppLockController(
        secureRead: (key) => key == credentialKey
            ? Future.value(credentialRecord)
            : throw MissingPluginException(),
        secureWrite: (key, value) async {},
        privacyShieldApply: (visible) async {},
        hashRounds: 4,
        platformSupportsBiometrics: false,
      );
      addTearDown(reloaded.dispose);
      await reloaded.initialize();

      expect(reloaded.enabled, isTrue);
      expect(reloaded.locked, isTrue);
      expect(reloaded.storageUnavailable, isTrue);
    },
  );

  test(
    'reloading a known lock against a vanished implementation fails closed',
    () async {
      // initialize read the lock on a working store; by the time a desktop
      // engine sync triggers reloadFromStorage, the plugin is gone. The old
      // reset path answered "no lock configured" and left the app unlocked —
      // the exact fail-open this regression pins.
      final stored = <String, String>{};
      var storageGone = false;
      Future<String?> read(String key) async {
        if (storageGone) throw MissingPluginException();
        return stored[key];
      }

      final controller = LocalAppLockController(
        secureRead: read,
        secureWrite: (key, value) async {
          if (value == null) {
            stored.remove(key);
          } else {
            stored[key] = value;
          }
        },
        privacyShieldApply: (visible) async {},
        hashRounds: 4,
        platformSupportsBiometrics: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.setCredential(AppLockCredentialType.pin, '1234');
      controller.lock();
      expect(controller.locked, isTrue);

      storageGone = true;
      await controller.reloadFromStorage();

      expect(controller.enabled, isTrue);
      expect(controller.locked, isTrue);
      expect(controller.storageUnavailable, isTrue);
    },
  );

  test('a real secure-storage failure still fails closed', () async {
    // A present implementation that errors is a different situation: a lock
    // may exist behind the error, so the fail-closed behaviour is kept.
    final controller = LocalAppLockController(
      secureRead: (key) => throw PlatformException(code: 'keychain_gone'),
      secureWrite: (key, value) =>
          throw PlatformException(code: 'keychain_gone'),
      privacyShieldApply: (visible) async {},
      hashRounds: 4,
      platformSupportsBiometrics: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.storageUnavailable, isTrue);
    expect(controller.locked, isTrue);
  });

  test(
    'biometrics on a host without the local_auth port report unavailable',
    () async {
      // local_auth without a native implementation throws
      // MissingPluginException from the enrolled-biometrics probe; the
      // availability refresh already degrades to "no biometrics" instead of
      // surfacing the error.
      final controller = LocalAppLockController(
        secureRead: (key) async => null,
        secureWrite: (key, value) async {},
        biometricProbe: () => throw MissingPluginException(),
        biometricAuthenticate: (_) async => true,
        privacyShieldApply: (visible) async {},
        hashRounds: 4,
        platformSupportsBiometrics: true,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.biometricAvailable, isFalse);
      expect(controller.locked, isFalse);
    },
  );
}

LocalAppLockController _controller(
  Map<String, String> storage, {
  List<bool>? shieldStates,
  AppLockNow? now,
}) => LocalAppLockController(
  secureRead: (key) async => storage[key],
  secureWrite: (key, value) async {
    if (value == null) {
      storage.remove(key);
    } else {
      storage[key] = value;
    }
  },
  privacyShieldApply: (visible) async => shieldStates?.add(visible),
  hashRounds: 4,
  platformSupportsBiometrics: false,
  now: now,
);
