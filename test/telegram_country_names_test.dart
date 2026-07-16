import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/country_picker.dart';
import 'package:mithka/auth/telegram_country_names.dart';

void main() {
  test('uses Telegram localized country names over bundled names', () async {
    final requests = <Map<String, dynamic>>[];
    final names = TelegramCountryNames(
      query: (request) async {
        requests.add(request);
        return {
          '@type': 'countries',
          'countries': [
            {
              '@type': 'countryInfo',
              'country_code': 'TW',
              'name': 'Taiwan',
              'english_name': 'Taiwan',
            },
            {
              '@type': 'countryInfo',
              'country_code': 'JP',
              'name': '日本',
              'english_name': 'Japan',
            },
          ],
        };
      },
    );

    final loaded = await names.load();

    expect(requests.single['@type'], 'getCountries');
    expect(loaded['TW'], 'Taiwan');
    expect(loaded['JP'], '日本');
    expect(Country.china.displayName(loaded), isNotEmpty);
    final taiwan = Country.all.singleWhere((country) => country.iso == 'TW');
    expect(taiwan.displayName(loaded), 'Taiwan');
  });

  test('falls back to Telegram English name when localized name is empty', () {
    final names = TelegramCountryNames.parse({
      '@type': 'countries',
      'countries': [
        {
          '@type': 'countryInfo',
          'country_code': 'GB',
          'name': '',
          'english_name': 'United Kingdom',
        },
        {
          '@type': 'countryInfo',
          'country_code': 'invalid',
          'name': 'Invalid',
          'english_name': 'Invalid',
        },
      ],
    });

    expect(names, {'GB': 'United Kingdom'});
  });
}
