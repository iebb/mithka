import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/profile/profile_identity_summary.dart';

void main() {
  group('fullProfileIdentityLines', () {
    test('keeps the phone separate from the Telegram ID and username', () {
      expect(
        fullProfileIdentityLines(
          formattedPhone: '+372 8198 1998',
          usernames: ['nekoko14', 'collectible'],
          userId: 12345,
        ),
        [
          (
            kind: ProfileIdentityKind.phoneNumber,
            text: '+372 8198 1998',
            copyText: '+372 8198 1998',
          ),
          (
            kind: ProfileIdentityKind.telegramId,
            text: 'TG: 12345',
            copyText: '12345',
          ),
          (
            kind: ProfileIdentityKind.username,
            text: '@nekoko14',
            copyText: '@nekoko14',
          ),
          (
            kind: ProfileIdentityKind.username,
            text: '@collectible',
            copyText: '@collectible',
          ),
        ],
      );
    });

    test('shows the Telegram ID even when no username exists', () {
      expect(
        fullProfileIdentityLines(
          formattedPhone: '',
          usernames: const [],
          userId: 12345,
        ),
        [
          (
            kind: ProfileIdentityKind.telegramId,
            text: 'TG: 12345',
            copyText: '12345',
          ),
        ],
      );
    });

    test('hides only the phone number, not the Telegram identity', () {
      expect(
        fullProfileIdentityLines(
          formattedPhone: '+372 8198 1998',
          usernames: ['nekoko14'],
          userId: 12345,
          hidePhone: true,
        ),
        [
          (
            kind: ProfileIdentityKind.telegramId,
            text: 'TG: 12345',
            copyText: '12345',
          ),
          (
            kind: ProfileIdentityKind.username,
            text: '@nekoko14',
            copyText: '@nekoko14',
          ),
        ],
      );
    });

    test('copies the phone as a pastable number, not the grouped label', () {
      final lines = fullProfileIdentityLines(
        formattedPhone: '+372 8198 1998',
        rawPhone: '37281981998',
        usernames: const [],
        userId: 12345,
      );
      expect(lines.first.text, '+372 8198 1998');
      expect(lines.first.copyText, '+37281981998');
    });
  });

  group('e164PhoneNumber', () {
    test('keeps the digits and drops the grouping', () {
      expect(e164PhoneNumber('372 8198-1998'), '+37281981998');
      expect(e164PhoneNumber('+37281981998'), '+37281981998');
    });

    test('is null when there is nothing to paste', () {
      expect(e164PhoneNumber(''), isNull);
      expect(e164PhoneNumber('   '), isNull);
      expect(e164PhoneNumber('no number'), isNull);
    });
  });
}
