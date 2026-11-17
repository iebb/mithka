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
    const chain = [
      AuthInitializing(),
      AuthReloading(),
      AuthWaitPhoneNumber(),
      AuthClosed(),
    ];
    final identities = chain.map(LoginView.debugStepIdentityForTesting).toSet();
    expect(identities, {'phone'});
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
