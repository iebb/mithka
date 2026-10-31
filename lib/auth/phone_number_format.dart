import 'package:dlibphonenumber/dlibphonenumber.dart';

/// Formats international phone entry without changing its digits.
String formatLoginPhoneNumber(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '+';
  final raw = '+$digits';
  try {
    final util = PhoneNumberUtil.instance;
    final formatter = util.getAsYouTypeFormatter('US');
    var formatted = formatter.inputDigit('+');
    for (final digit in digits.split('')) {
      formatted = formatter.inputDigit(digit);
    }
    formatted = formatted.trim();
    if (formatted != raw) return formatted;

    // Some regions have no national grouping rule for mobile numbers (e.g.
    // Gibraltar). The live formatter then returns the raw input, even dropping
    // the country-code separator. International formatting retains that space.
    final fallback = util.format(
      util.parse(raw, null),
      PhoneNumberFormat.international,
    );
    // Parsing can normalize incomplete input. Never let that change the digits
    // being entered, including meaningful leading zeros or an overlong number.
    return fallback.replaceAll(RegExp(r'[^0-9]'), '') == digits
        ? fallback
        : raw;
  } catch (_) {
    return raw;
  }
}
