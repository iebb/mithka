import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_first_contact_info.dart';

void main() {
  test('parses first-contact account info with a hidden phone number', () {
    final info = ChatFirstContactInfo.fromActionBar({
      '@type': 'chatActionBarReportAddBlock',
      'account_info': {
        '@type': 'accountInfo',
        'registration_month': 4,
        'registration_year': 2025,
        'phone_number_country_code': 'uz',
      },
    });

    expect(info, isNotNull);
    expect(info!.countryCode, 'UZ');
    expect(info.registrationMonth, 4);
    expect(info.registrationYear, 2025);
    expect(info.hasRegistrationDate, isTrue);
    expect(info.isContact, isFalse);
    expect(info.isOfficial, isFalse);
  });

  test('uses user contact and verification state when available', () {
    final info = ChatFirstContactInfo.fromActionBar(
      {
        '@type': 'chatActionBarReportAddBlock',
        'account_info': {
          '@type': 'accountInfo',
          'registration_month': 4,
          'registration_year': 2025,
          'phone_number_country_code': 'UZ',
        },
      },
      user: {
        '@type': 'user',
        'is_contact': true,
        'verification_status': {
          '@type': 'verificationStatus',
          'is_verified': true,
        },
      },
    );

    expect(info!.isContact, isTrue);
    expect(info.isOfficial, isTrue);
  });

  test('is absent for chat action bars without account info', () {
    expect(
      ChatFirstContactInfo.fromActionBar({'@type': 'chatActionBarReportSpam'}),
      isNull,
    );
  });
}
