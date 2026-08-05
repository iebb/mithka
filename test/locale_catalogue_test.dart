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

  group('plural category selection', () {
    test('English and German separate one from other', () {
      for (final appKey in ['en', 'de', 'es']) {
        expect(LocaleCatalogue.pluralCategoryFor(appKey, 0), 'other');
        expect(LocaleCatalogue.pluralCategoryFor(appKey, 1), 'one');
        expect(LocaleCatalogue.pluralCategoryFor(appKey, 2), 'other');
        expect(LocaleCatalogue.pluralCategoryFor(appKey, 21), 'other');
      }
    });

    test('French groups zero with one', () {
      expect(LocaleCatalogue.pluralCategoryFor('fr', 0), 'one');
      expect(LocaleCatalogue.pluralCategoryFor('fr', 1), 'one');
      expect(LocaleCatalogue.pluralCategoryFor('fr', 2), 'other');
    });

    test('CJK locales only ever select other', () {
      for (final appKey in ['zhHans', 'zhHant', 'ja', 'ko']) {
        for (final count in [0, 1, 2, 11, 100]) {
          expect(LocaleCatalogue.pluralCategoryFor(appKey, count), 'other');
        }
      }
    });

    test('a negative count uses the magnitude', () {
      expect(LocaleCatalogue.pluralCategoryFor('en', -1), 'one');
    });
  });

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

    test('a single-category locale renders its only form', () {
      expect(AppStrings.pluralForLocale('ja', 'memberCount', 1), 'メンバー1人');
      expect(AppStrings.pluralForLocale('ja', 'memberCount', 9), 'メンバー9人');
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

    test('a plural key read without a count uses the other form', () {
      expect(AppStrings.tForLocale('en', 'memberCount'), '{count} members');
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

    test('prefers the requested locale', () {
      expect(AppStrings.tForLocale('de', 'shared'), 'Deutsch geteilt');
    });

    test('falls back to English for a key the locale lacks', () {
      expect(AppStrings.tForLocale('de', 'englishOnly'), 'English only');
    });

    test('falls back to English for an unloaded locale', () {
      expect(AppStrings.tForLocale('ko', 'shared'), 'English shared');
    });

    test('returns the key when nothing defines it', () {
      expect(
        AppStrings.tForLocale('de', 'missingEverywhere'),
        'missingEverywhere',
      );
    });

    test('country names resolve per locale and fall back', () {
      expect(AppStrings.tForLocale('de', 'countryJP'), 'Japan (de)');
      expect(AppStrings.tForLocale('ko', 'countryJP'), 'Japan');
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

    test('substitutes a single placeholder', () {
      expect(
        AppStrings.tForLocale('en', 'one', {'value1': 'Ana'}),
        'Hello Ana',
      );
    });

    test('substitutes every placeholder', () {
      expect(
        AppStrings.tForLocale('en', 'two', {'value1': 'A', 'value2': 'B'}),
        'A and B',
      );
    });

    test('substitutes a repeated placeholder', () {
      expect(
        AppStrings.tForLocale('en', 'repeat', {'value1': 'x'}),
        'x then x',
      );
    });

    test('numbers are stringified', () {
      expect(AppStrings.tForLocale('en', 'one', {'value1': 42}), 'Hello 42');
    });

    test('a template without placeholders is returned unchanged', () {
      expect(
        AppStrings.tForLocale('en', 'none', {'value1': 'ignored'}),
        'No placeholders',
      );
    });
  });

  group('shipped catalogue', () {
    setUp(fixtures.install);

    test('resolves a real key in every locale', () {
      for (final appKey in L10nFixtures.appKeys) {
        final value = AppStrings.tForLocale(appKey, AppStringKeys.aboutTitle);
        expect(value, isNot(AppStringKeys.aboutTitle));
        expect(value.trim(), isNotEmpty);
      }
    });

    test('presence labels are translated away from English', () {
      final english = fixtures.messages('en')[AppStringKeys.presenceOnline];
      expect(english, isNotEmpty);
      for (final appKey in ['zhHans', 'zhHant', 'ja', 'ko']) {
        expect(
          fixtures.messages(appKey)[AppStringKeys.presenceOnline],
          isNot(english),
        );
      }
    });

    test('declared plural categories match the runtime rule', () {
      for (final appKey in L10nFixtures.appKeys) {
        final declared = fixtures[appKey].pluralCategories.toSet();
        final selected = {
          for (final count in [0, 1, 2, 5, 11, 21, 100])
            LocaleCatalogue.pluralCategoryFor(appKey, count),
        };
        expect(
          selected.difference(declared),
          isEmpty,
          reason: '$appKey selects a category it does not declare',
        );
      }
    });
  });
}
