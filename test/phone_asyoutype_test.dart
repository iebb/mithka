import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/phone_number_format.dart';

String fmt(String input) => formatLoginPhoneNumber(input);

void main() {
  test('as-you-type: empty input stays "+"', () {
    expect(fmt(''), '+');
    expect(fmt('+'), '+');
  });

  test('as-you-type: groups per country and never loses digits', () {
    for (final n in [
      '+8613800138000',
      '+14155550123',
      '+61412345678',
      '+442071838750',
    ]) {
      final out = fmt(n);
      // digits preserved exactly
      expect(out.replaceAll(RegExp(r'[^0-9]'), ''), n.substring(1));
      // international format: starts with '+' and is grouped with a separator
      expect(out.startsWith('+'), isTrue, reason: out);
      expect(
        out.contains(RegExp(r'[\s-]')),
        isTrue,
        reason: 'should group: $out',
      );
    }
  });

  test('as-you-type: CN mobile international grouping', () {
    // Sanity that a known number formats to the expected international layout.
    expect(fmt('+8613800138000'), '+86 138 0013 8000');
  });

  test('Gibraltar mobiles retain the calling-code separator while typing', () {
    for (final digits in ['35057123456', '35060101234']) {
      for (var length = 4; length <= digits.length; length++) {
        final partial = digits.substring(0, length);
        expect(fmt(partial), '+350 ${partial.substring(3)}');
      }
    }
    expect(fmt('+350 5712 3456'), '+350 57123456');
    expect(fmt('+35020012345'), '+350 200 12345');
    expect(fmt('+350'), '+350');
  });

  test(
    'fallback formatting preserves digits on deletion and invalid input',
    () {
      for (final number in [
        '+350571234567890',
        '+390212345678',
        '+99912345678',
      ]) {
        for (var length = number.length; length > 0; length--) {
          final partial = number.substring(0, length);
          expect(
            fmt(partial).replaceAll(RegExp(r'[^0-9]'), ''),
            partial.replaceAll(RegExp(r'[^0-9]'), ''),
          );
        }
      }
    },
  );
}
