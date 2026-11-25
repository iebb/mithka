import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/auth_manager.dart';

/// The add-account flicker: entering 添加账号 lands the login surface through
/// AuthReloading → AuthWaitPhoneNumber — both render the SAME phone form, but
/// each notifyListeners re-keyed the form's AnimatedSwitcher child and the
/// whole column cross-faded against itself. The state machine must swallow
/// the redundant notification, and still fire on every real change.
void main() {
  test('re-setting the same phone step does not notify', () {
    final auth = AuthManager();
    addTearDown(auth.dispose);
    expect(
      auth.debugSetStepForTesting(const AuthWaitPhoneNumber()),
      isTrue,
      reason: 'the first real change must notify',
    );
    expect(
      auth.debugSetStepForTesting(const AuthWaitPhoneNumber()),
      isFalse,
      reason: 'an identical re-set must not re-key the phone form',
    );
  });

  test('re-setting AuthReloading repeatedly notifies once', () {
    final auth = AuthManager();
    addTearDown(auth.dispose);
    expect(auth.debugSetStepForTesting(const AuthReloading()), isTrue);
    expect(auth.debugSetStepForTesting(const AuthReloading()), isFalse);
  });

  test('a genuine step change always notifies', () {
    final auth = AuthManager();
    addTearDown(auth.dispose);
    expect(auth.debugSetStepForTesting(const AuthReloading()), isTrue);
    expect(
      auth.debugSetStepForTesting(const AuthWaitPhoneNumber()),
      isTrue,
      reason: 'the reload landing on phone is a real change the first time',
    );
    expect(auth.debugSetStepForTesting(const AuthReady()), isTrue);
    expect(auth.debugSetStepForTesting(const AuthInitializing()), isTrue);
  });

  test('QR steps compare by link', () {
    final auth = AuthManager();
    addTearDown(auth.dispose);
    expect(auth.debugSetStepForTesting(const AuthWaitQrCode('a')), isTrue);
    expect(auth.debugSetStepForTesting(const AuthWaitQrCode('a')), isFalse);
    expect(
      auth.debugSetStepForTesting(const AuthWaitQrCode('b')),
      isTrue,
      reason: 'a regenerated QR link is a real change',
    );
  });

  test('code steps compare by info', () {
    const info = AuthCodeInfo(method: AuthCodeDeliveryMethod.sms, length: 5);
    final auth = AuthManager();
    addTearDown(auth.dispose);
    expect(auth.debugSetStepForTesting(const AuthWaitCode(info)), isTrue);
    expect(auth.debugSetStepForTesting(const AuthWaitCode(info)), isFalse);
    const other = AuthCodeInfo(
      method: AuthCodeDeliveryMethod.unknown,
      length: 5,
    );
    expect(auth.debugSetStepForTesting(const AuthWaitCode(other)), isTrue);
  });

  test('password steps compare by hint', () {
    final auth = AuthManager();
    addTearDown(auth.dispose);
    expect(auth.debugSetStepForTesting(const AuthWaitPassword('hint')), isTrue);
    expect(
      auth.debugSetStepForTesting(const AuthWaitPassword('hint')),
      isFalse,
    );
    expect(
      auth.debugSetStepForTesting(const AuthWaitPassword('other')),
      isTrue,
    );
  });
}
