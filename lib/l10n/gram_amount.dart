//
//  gram_amount.dart
//
//  Gram amounts as the user reads them ("1.5 GRAM"). Shared by every message
//  that shows Gram, so the gift and transfer cards format alike.
//

import 'package:intl/intl.dart';

import 'app_localizations.dart';

abstract final class GramAmount {
  /// TDLib counts Gram in its smallest unit, 10^-9 Gram.
  static const unitsPerGram = 1000000000;

  /// "1.5 GRAM" from smallest units, in the given or current app locale.
  static String format(int units, {String? localeKey}) {
    final locale = localeKey ?? AppStrings.currentLocaleKey;
    return AppStrings.tForLocale(locale, AppStringKeys.gramAmount, {
      'value1': formatNumber(units, localeKey: locale),
    });
  }

  /// Smallest units as a Gram number with the locale's grouping and decimal
  /// separator and trailing zeros trimmed: 1500000000 -> "1.5", 2000000000 ->
  /// "2", 12345678000000 -> "12,345.678" ("12.345,678" in German). Exact for
  /// every 64-bit amount: the fraction never goes through a double.
  static String formatNumber(int units, {String? localeKey}) {
    final format = NumberFormat.decimalPattern(
      _intlLocale(localeKey ?? AppStrings.currentLocaleKey),
    );
    final magnitude = units.abs();
    final whole = format.format(magnitude ~/ unitsPerGram);
    final fraction = (magnitude % unitsPerGram)
        .toString()
        .padLeft(9, '0')
        .replaceFirst(_trailingZeros, '');
    final sign = units < 0 ? format.symbols.MINUS_SIGN : '';
    if (fraction.isEmpty) return '$sign$whole';
    return '$sign$whole${format.symbols.DECIMAL_SEP}$fraction';
  }

  static final _trailingZeros = RegExp(r'0+$');

  static String _intlLocale(String localeKey) {
    final locale = switch (localeKey) {
      'zhHans' => 'zh',
      'zhHant' => 'zh_TW',
      _ => localeKey,
    };
    return NumberFormat.localeExists(locale) ? locale : 'en';
  }
}
