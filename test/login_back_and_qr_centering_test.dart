import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/login_view.dart';

void main() {
  test(
    'the standalone back button only appears where it adds a destination',
    () {
      // First run, QR step: no other account, the method switch already covers
      // returning to the phone form — no back button.
      expect(
        loginHasDistinctBackDestination(
          showBotLogin: false,
          backToPhoneOnly: true,
          configuredAccountCount: 1,
        ),
        isFalse,
      );
      // First run, bot-token step: same — the switch returns to the phone.
      expect(
        loginHasDistinctBackDestination(
          showBotLogin: true,
          backToPhoneOnly: true,
          configuredAccountCount: 1,
        ),
        isFalse,
      );
      // Adding an account while others exist: back offers the previous account.
      expect(
        loginHasDistinctBackDestination(
          showBotLogin: false,
          backToPhoneOnly: true,
          configuredAccountCount: 2,
        ),
        isTrue,
      );
      expect(
        loginHasDistinctBackDestination(
          showBotLogin: true,
          backToPhoneOnly: true,
          configuredAccountCount: 2,
        ),
        isTrue,
      );
      // Steps past the phone form (code, 2FA, registration) always offer
      // re-entry plus account switching.
      expect(
        loginHasDistinctBackDestination(
          showBotLogin: false,
          backToPhoneOnly: false,
          configuredAccountCount: 1,
        ),
        isTrue,
      );
    },
  );

  test(
    'switching away from QR login keeps the login surface mounted',
    () async {
      // AuthInitializing is what routes the auth gate to the cold-start splash;
      // leaving the QR step for the phone form must not produce it.
      final source = await File('lib/auth/auth_manager.dart').readAsString();
      final start = source.indexOf('Future<bool> switchToPhoneLogin()');
      final end = source.indexOf('void requestQrLogin()');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      expect(body, contains('AuthReloading'));
      expect(body, isNot(contains('AuthInitializing')));
    },
  );

  test('the touch QR step centers the code and its refresh action', () async {
    final source = await File('lib/auth/login_view.dart').readAsString();
    final start = source.indexOf('Widget _qrCodeStep(');
    final end = source.indexOf('Widget _freshSessionWaitingStep(');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body, contains('Center('));
    expect(body, isNot(contains('Alignment.centerLeft')));
  });
} //
