import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/auth/premium_auth_purchase_service.dart';
import 'package:mithka/settings/account_security_service.dart';

void main() {
  test('email authorization requests use the dedicated TDLib types', () {
    expect(authenticationEmailAddressRequest(' user@example.com '), {
      '@type': 'setAuthenticationEmailAddress',
      'email_address': 'user@example.com',
    });
    expect(authenticationEmailCodeRequest(' 12345 '), {
      '@type': 'checkAuthenticationEmailCode',
      'code': {'@type': 'emailAddressAuthenticationCode', 'code': '12345'},
    });
  });

  test('Premium authorization requests preserve App Store receipt bytes', () {
    expect(
      PremiumAuthPurchaseService.checkRequest(
        premiumDayCount: 90,
        currency: 'JPY',
        amount: 1000,
      ),
      {
        '@type': 'checkAuthenticationPremiumPurchase',
        'premium_day_count': 90,
        'currency': 'JPY',
        'amount': 1000,
      },
    );
    expect(
      PremiumAuthPurchaseService.transactionRequest(
        receipt: Uint8List.fromList([1, 2, 3]),
        restore: true,
        premiumDayCount: 90,
        currency: 'JPY',
        amount: 1000,
      ),
      {
        '@type': 'setAuthenticationPremiumPurchaseTransaction',
        'transaction': {'@type': 'storeTransactionAppStore', 'receipt': 'AQID'},
        'is_restore': true,
        'premium_day_count': 90,
        'currency': 'JPY',
        'amount': 1000,
      },
    );
  });

  test('two-step password requests match the pinned TDLib schema', () {
    expect(
      AccountSecurityService.setPasswordRequest(
        oldPassword: 'old',
        newPassword: 'new',
        hint: 'hint',
        recoveryEmail: 'user@example.com',
      ),
      {
        '@type': 'setPassword',
        'old_password': 'old',
        'new_password': 'new',
        'new_hint': 'hint',
        'set_recovery_email_address': true,
        'new_recovery_email_address': 'user@example.com',
      },
    );
    expect(
      AccountSecurityService.recoverPasswordRequest(
        code: '12345',
        newPassword: 'new',
        hint: 'hint',
      ),
      {
        '@type': 'recoverPassword',
        'recovery_code': '12345',
        'new_password': 'new',
        'new_hint': 'hint',
      },
    );
  });

  test('change-phone requests use the generic phone verification flow', () {
    expect(AccountSecurityService.changePhoneRequest('+819012345678'), {
      '@type': 'sendPhoneNumberCode',
      'phone_number': '+819012345678',
      'settings': null,
      'type': {'@type': 'phoneNumberCodeTypeChange'},
    });
    expect(AccountSecurityService.checkPhoneCodeRequest('12345'), {
      '@type': 'checkPhoneNumberCode',
      'code': '12345',
    });
    expect(AccountSecurityService.resendPhoneCodeRequest(), {
      '@type': 'resendPhoneNumberCode',
      'reason': null,
    });
  });

  test('inactivity and native account deletion requests are exact', () {
    expect(AccountSecurityService.setAccountTtlRequest(180), {
      '@type': 'setAccountTtl',
      'ttl': {'@type': 'accountTtl', 'days': 180},
    });
    expect(
      AccountSecurityService.deleteAccountRequest(
        reason: 'Leaving',
        password: 'password',
      ),
      {'@type': 'deleteAccount', 'reason': 'Leaving', 'password': 'password'},
    );
  });
}
