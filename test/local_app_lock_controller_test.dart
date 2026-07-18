import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mithka/security/local_app_lock_controller.dart';

void main() {
  test('four-digit PIN is hashed, verified, and restored as locked', () async {
    final storage = <String, String>{};
    final controller = _controller(storage);
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
    expect(await controller.unlockWithCredential('1234'), isTrue);
    expect(controller.locked, isFalse);

    final restored = _controller(storage);
    await restored.initialize();
    expect(restored.enabled, isTrue);
    expect(restored.locked, isTrue);
    expect(await restored.verifyCredential('1234'), isTrue);
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
    expect(
      await controller.authenticateBiometric(localizedReason: 'Unlock app'),
      AppLockBiometricResult.success,
    );
    expect(controller.locked, isFalse);
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
}

LocalAppLockController _controller(Map<String, String> storage) =>
    LocalAppLockController(
      secureRead: (key) async => storage[key],
      secureWrite: (key, value) async {
        if (value == null) {
          storage.remove(key);
        } else {
          storage[key] = value;
        }
      },
      hashRounds: 4,
      platformSupportsBiometrics: false,
    );
