import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/telegram_passkey_service.dart';

void main() {
  test('passkeys are exposed only on Android', () {
    expect(
      telegramPasskeyPlatformSupported(isAndroid: true, isIOS: false),
      isTrue,
    );
    expect(
      telegramPasskeyPlatformSupported(isAndroid: false, isIOS: true),
      isFalse,
    );
    expect(
      telegramPasskeyPlatformSupported(isAndroid: false, isIOS: false),
      isFalse,
    );
  });

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

  test('extracts the WebAuthn publicKey object from TDLib text', () {
    final result = telegramPublicKeyJson(
      jsonEncode({
        'publicKey': {
          'challenge': 'challenge',
          'rpId': 'telegram.org',
          'timeout': 60000,
        },
      }),
    );

    expect(jsonDecode(result), {
      'challenge': 'challenge',
      'rpId': 'telegram.org',
      'timeout': 60000,
    });
  });

  test('converts WebAuthn base64url data to TDLib standard Base64', () {
    expect(tdlibBase64FromBase64Url('AQID-vs'), 'AQID+vs=');
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

  test('parses passkey timestamps returned by TDLib', () {
    final passkey = TelegramLoginPasskey.fromJson({
      '@type': 'passkey',
      'id': 'id',
      'name': 'Pixel',
      'addition_date': 100,
      'last_usage_date': 200,
      'software_icon_custom_emoji_id': 42,
    });

    expect(passkey.id, 'id');
    expect(passkey.name, 'Pixel');
    expect(passkey.additionDate.millisecondsSinceEpoch, 100000);
    expect(passkey.lastUsageDate?.millisecondsSinceEpoch, 200000);
    expect(passkey.softwareIconCustomEmojiId, 42);
  });
}
