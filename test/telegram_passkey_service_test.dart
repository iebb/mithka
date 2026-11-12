import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/telegram_passkey_service.dart';

void main() {
  test('iOS does not claim Telegram-owned passkey domains', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();

    expect(
      entitlements,
      isNot(contains('com.apple.developer.associated-domains')),
    );
    expect(entitlements, isNot(contains('webcredentials:telegram.org')));
  });

  test('reads the Telegram user id from a passkey user handle', () {
    final handle = base64Url
        .encode(utf8.encode('2:1234567890123'))
        .replaceAll('=', '');

    expect(telegramUserIdFromPasskeyUserHandle(handle), 1234567890123);
    expect(telegramUserIdFromPasskeyUserHandle(''), isNull);
    expect(telegramUserIdFromPasskeyUserHandle('not-base64!'), isNull);
    expect(
      telegramUserIdFromPasskeyResponse(
        jsonEncode({
          'response': {'userHandle': handle},
        }),
      ),
      1234567890123,
    );
  });

  test('builds the exact TDLib assertion fields', () {
    const clientData =
        '{"type":"webauthn.get","challenge":"x","origin":"https://telegram.org"}';
    final assertion = telegramPasskeyAssertion(
      jsonEncode({
        'id': 'credential-id',
        'response': {
          'authenticatorData': 'AQID-vs',
          'signature': 'BAUG',
          'userHandle': 'MjoyMw',
        },
      }),
      clientData,
    );

    expect(assertion, {
      'credential_id': 'credential-id',
      'client_data': clientData,
      'authenticator_data': 'AQID+vs=',
      'signature': 'BAUG',
      'user_handle': 'MjoyMw==',
    });
  });
}
