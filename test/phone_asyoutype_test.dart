import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/phone_number_format.dart';

String fmt(String input) => formatLoginPhoneNumber(input);

void main() {
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
