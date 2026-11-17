import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/auth/login_view.dart';

/// The logout flicker: leaving an account runs the chain
/// AuthLoggingOut → AuthClosed → AuthInitializing → AuthWaitPhoneNumber.
/// The gate deliberately crossfades splash ⇄ login across that chain, but
/// inside the login surface every one of those tail states renders the SAME
/// phone-number column — re-keying the step's AnimatedSwitcher child on each
/// hop mounted a second copy of the form and cross-faded it against itself.
/// The identity must stay 'phone' across the whole chain.
void main() {
  test('the logout chain never re-keys the phone form', () {
    const chain = [AuthInitializing(), AuthWaitPhoneNumber(), AuthClosed()];
    final identities = chain.map(LoginView.debugStepIdentityForTesting).toSet();
    expect(identities, {'phone'});
  });

  test('AuthReloading sticks to the previous identity', () async {
    // Cancel-add-account / logout run form → AuthReloading → gate hand-off.
    // The reloading state must not carry its own identity (the old mapping
    // sent code/2FA forms back to the phone column mid-flight, cross-fading
    // a displaced phone form that vanished last). The static seam cannot
    // hold per-instance state, so the reloading branch lives in the state
    // and this test pins the CONTRACT: a reloading step must never map to
    // a fresh identity through the pure core either.
    expect(
      LoginView.debugStepIdentityForTesting(const AuthReloading()),
      isNot('phone'),
      reason:
          'AuthReloading must be handled before the family mapping (sticky '
          'identity in _LoginViewState), never mapped inside it',
    );
    // Source pin: the sticky branch exists and precedes the mapping call
    // inside _stepIdentity (skip the initState seeding occurrence).
    final source = await File('lib/auth/login_view.dart').readAsString();
    final sticky = source.indexOf('if (auth.step is AuthReloading)');
    expect(sticky, greaterThan(0));
    final mapping = source.indexOf(
      '_lastStepIdentity = LoginView.debugStepIdentityForTesting',
      sticky,
    );
    expect(mapping, greaterThan(sticky));
  });

  test('distinct forms keep distinct identities', () {
    expect(
      LoginView.debugStepIdentityForTesting(
        const AuthWaitCode(
          AuthCodeInfo(method: AuthCodeDeliveryMethod.sms, length: 5),
        ),
      ),
      isNot('phone'),
    );
    expect(
      LoginView.debugStepIdentityForTesting(const AuthWaitQrCode('a')),
      isNot('phone'),
    );
  });
}
