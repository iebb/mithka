//
//  locale_catalogue_test.dart
//
//  Covers the runtime half of localization: placeholder interpolation, CLDR
//  plural selection, and the fallback chain. Mithka owns every string it
//  renders, so a hole here shows up as a bare key on screen.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/locale_catalogue.dart';

import 'support/l10n_fixtures.dart';

final fixtures = L10nFixtures.load();

LocaleCatalogue catalogue({
  required String appKey,
  List<String> pluralCategories = const ['one', 'other'],
  Map<String, String> strings = const {},
  Map<String, Map<String, String>> plurals = const {},
  Map<String, String> countries = const {},
}) {
  return LocaleCatalogue(
    tag: appKey,
    appKey: appKey,
    pluralCategories: pluralCategories,
    strings: strings,
    plurals: plurals,
    countries: countries,
  );
}

void main() {
  tearDown(LocaleCatalogues.reset);

  group('plural resolution', () {
    setUp(() {
      LocaleCatalogues.install([
        catalogue(
          appKey: 'en',
          plurals: {
            'memberCount': {
              'one': '{count} member',
              'other': '{count} members',
            },
          },
        ),
        catalogue(
          appKey: 'ja',
          pluralCategories: const ['other'],
          plurals: {
            'memberCount': {'other': 'メンバー{count}人'},
          },
        ),
      ]);
    });

    test('picks the form for the count and supplies {count}', () {
      expect(AppStrings.pluralForLocale('en', 'memberCount', 1), '1 member');
      expect(AppStrings.pluralForLocale('en', 'memberCount', 5), '5 members');
    });

    test('extra placeholders travel alongside {count}', () {
      LocaleCatalogues.install([
        catalogue(
          appKey: 'en',
          plurals: {
            'inChat': {
              'one': '{count} member in {value1}',
              'other': '{count} members in {value1}',
            },
          },
        ),
      ]);
      expect(
        AppStrings.pluralForLocale('en', 'inChat', 2, {'value1': 'Design'}),
        '2 members in Design',
      );
    });
  });

  group('fallback chain', () {
    setUp(() {
      LocaleCatalogues.install([
        catalogue(
          appKey: 'en',
          strings: {'shared': 'English shared', 'englishOnly': 'English only'},
          countries: {'countryJP': 'Japan'},
        ),
        catalogue(
          appKey: 'de',
          strings: {'shared': 'Deutsch geteilt'},
          countries: {'countryJP': 'Japan (de)'},
        ),
      ]);
    });

    test('falls back to English for a key the locale lacks', () {
      expect(AppStrings.tForLocale('de', 'englishOnly'), 'English only');
    });

    test('falls back to English for an unloaded locale', () {
      expect(AppStrings.tForLocale('ko', 'shared'), 'English shared');
    });
  });

  group('placeholder interpolation', () {
    setUp(() {
      LocaleCatalogues.install([
        catalogue(
          appKey: 'en',
          strings: {
            'one': 'Hello {value1}',
            'two': '{value1} and {value2}',
            'repeat': '{value1} then {value1}',
            'none': 'No placeholders',
          },
        ),
      ]);
    });

    test('substitutes every placeholder', () {
      expect(
        AppStrings.tForLocale('en', 'two', {'value1': 'A', 'value2': 'B'}),
        'A and B',
      );
    });
  });
}
