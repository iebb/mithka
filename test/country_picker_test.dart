import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/country_picker.dart';

void main() {
  test('shared +7 Kazakhstan prefixes resolve to Kazakhstan while typing', () {
    expect(Country.match('77')?.iso, 'KZ');
    expect(Country.match('7701')?.iso, 'KZ');
    expect(Country.match('76')?.iso, 'KZ');
  });

  test('shared +7 Russian prefixes remain Russia', () {
    expect(Country.match('7912')?.iso, 'RU');
    expect(Country.match('7495')?.iso, 'RU');
  });
}
