//
//  l10n_completeness_test.dart
//
//  Guards the "every string is localized in every supported language"
//  invariant. A key missing from any locale catalogue would silently fall
//  back to English (or render the raw key name) in the UI, so this test
//  fails the build instead.
//
//  The catalogues under test are the generated assets the app ships, so a
//  stale `assets/l10n` is caught here too.
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/locale_catalogue.dart';

import 'support/l10n_fixtures.dart';

final fixtures = L10nFixtures.load();

final placeholderPattern = RegExp(r'\{(?:value\d|count)\}');

Set<String> placeholdersOf(String value) =>
    placeholderPattern.allMatches(value).map((m) => m.group(0)!).toSet();

/// Every form of a key, so plural sets are checked the same way as strings.
Iterable<String> formsOf(LocaleCatalogue catalogue, String key) sync* {
  final plain = catalogue.strings[key];
  if (plain != null) yield plain;
  final plural = catalogue.plurals[key];
  if (plural != null) yield* plural.values;
}

void main() {
  setUp(fixtures.install);
  tearDown(LocaleCatalogues.reset);

  test('every supported locale resolves to a catalogue', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final key = AppLocalizations.localeKeyFor(locale);
      expect(
        fixtures.catalogues.containsKey(key),
        isTrue,
        reason: 'locale $locale resolves to "$key" which has no catalogue',
      );
    }
  });

  test('the asset manifest and supportedLocales agree', () {
    final manifest =
        jsonDecode(File('assets/l10n/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final tags = (manifest['locales'] as List)
        .cast<Map<String, dynamic>>()
        .map((entry) => entry['appKey'] as String)
        .toSet();
    final supported = AppLocalizations.supportedLocales
        .map(AppLocalizations.localeKeyFor)
        .toSet();
    expect(tags, supported);
  });

  test('all catalogues share the exact key set', () {
    final reference = fixtures.en.strings.keys.toSet();
    for (final appKey in L10nFixtures.appKeys) {
      final keys = fixtures.messages(appKey).keys.toSet();
      expect(
        reference.difference(keys),
        isEmpty,
        reason: '$appKey is missing keys present in en',
      );
      expect(
        keys.difference(reference),
        isEmpty,
        reason: '$appKey has keys that en lacks',
      );
    }
  });

  test('a counted key is a plural set in every locale', () {
    final counted = fixtures.en.plurals.keys.toSet();
    for (final appKey in L10nFixtures.appKeys) {
      expect(
        fixtures[appKey].plurals.keys.toSet(),
        counted,
        reason: '$appKey disagrees with en about which keys are counted',
      );
    }
  });

  test('a plural set declares exactly its locale plural categories', () {
    for (final appKey in L10nFixtures.appKeys) {
      final catalogue = fixtures[appKey];
      final expected = catalogue.pluralCategories.toSet();
      for (final entry in catalogue.plurals.entries) {
        expect(
          entry.value.keys.toSet(),
          expected,
          reason: '$appKey.${entry.key} plural categories differ',
        );
      }
    }
  });

  test('no catalogue contains an empty value', () {
    for (final appKey in L10nFixtures.appKeys) {
      final catalogue = fixtures[appKey];
      for (final key in catalogue.strings.keys.followedBy(
        catalogue.plurals.keys,
      )) {
        for (final form in formsOf(catalogue, key)) {
          expect(form.trim(), isNotEmpty, reason: '$appKey.$key is empty');
        }
      }
    }
  });

  test('name colors are described without a Premium restriction', () {
    const expected = <String, String>{
      'zhHans': '名字颜色',
      'zhHant': '名稱顏色',
      'ja': '名前の色',
      'ko': '이름 색상',
      'en': 'Name colors',
      'fr': 'Couleurs de nom',
      'es': 'Colores de nombre',
      'de': 'Namensfarben',
    };

    for (final entry in expected.entries) {
      expect(
        fixtures.messages(entry.key)[AppStringKeys.appearanceShowNameColors],
        entry.value,
      );
    }
  });

  test('Simplified Chinese AI model routing uses feature-specific labels', () {
    final zhHans = fixtures.messages('zhHans');
    expect(zhHans[AppStringKeys.aiTranslateUsing], '翻译使用');
    expect(zhHans[AppStringKeys.aiSummarizeUsing], '总结使用');
    expect(zhHans[AppStringKeys.aiProviders], '服务商');
    expect(zhHans[AppStringKeys.aiAddProvider], '添加服务商');
  });

  test('placeholders match the English source in every locale', () {
    final english = fixtures.en;
    for (final appKey in L10nFixtures.appKeys) {
      final catalogue = fixtures[appKey];
      for (final key in catalogue.strings.keys.followedBy(
        catalogue.plurals.keys,
      )) {
        final expected = placeholdersOf(formsOf(english, key).first);
        for (final form in formsOf(catalogue, key)) {
          expect(
            placeholdersOf(form),
            expected,
            reason: '$appKey.$key placeholder mismatch',
          );
        }
      }
    }
  });

  test('country names cover every locale with the same key set', () {
    final reference = fixtures.countries('en').keys.toSet();
    expect(reference, isNotEmpty);
    for (final appKey in L10nFixtures.appKeys) {
      final countries = fixtures.countries(appKey);
      expect(
        countries.keys.toSet(),
        reference,
        reason: 'countries[$appKey] key set differs from en',
      );
      for (final entry in countries.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: 'countries[$appKey].${entry.key} is empty',
        );
      }
    }
  });

  test('every AppStringKeys constant resolves in every locale', () {
    // AppStringKeys cannot be enumerated at runtime, so read the source.
    final source = File('lib/l10n/app_localizations.dart').readAsStringSync();
    final declared = RegExp(
      r"static const \w+ =\s*'([^']+)';",
    ).allMatches(source).map((m) => m.group(1)!).toSet();
    expect(declared, isNotEmpty);
    final countries = fixtures.countries('en').keys.toSet();
    for (final key in declared) {
      if (countries.contains(key)) continue;
      for (final appKey in L10nFixtures.appKeys) {
        final catalogue = fixtures[appKey];
        expect(
          catalogue.strings.containsKey(key) ||
              catalogue.plurals.containsKey(key),
          isTrue,
          reason: 'key "$key" missing from $appKey',
        );
      }
    }
  });

  test('every catalogue key is declared in AppStringKeys', () {
    final source = File('lib/l10n/app_localizations.dart').readAsStringSync();
    final declared = RegExp(
      r"static const \w+ =\s*'([^']+)';",
    ).allMatches(source).map((m) => m.group(1)!).toSet();
    final orphans =
        fixtures.en.strings.keys
            .followedBy(fixtures.en.plurals.keys)
            .where((key) => !declared.contains(key))
            .toList()
          ..sort();
    expect(
      orphans,
      isEmpty,
      reason: 'catalogue keys with no AppStringKeys constant: $orphans',
    );
  });

  test('tForLocale renders localized text, never the raw key', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final localeKey = AppLocalizations.localeKeyFor(locale);
      final value = AppStrings.tForLocale(localeKey, AppStringKeys.chatMeLabel);
      expect(value, isNot(AppStringKeys.chatMeLabel));
      expect(value.trim(), isNotEmpty);
    }
  });

  test('Simplified Chinese unread count uses the unread label', () {
    expect(
      AppStrings.tForLocale('zhHans', AppStringKeys.chatUnreadMessagesCount, {
        'value1': 1972,
      }),
      '1972条未读消息',
    );
  });

  test('tForLocale resolves country keys through the country map', () {
    for (final appKey in L10nFixtures.appKeys) {
      final value = AppStrings.tForLocale(appKey, 'countryJP');
      expect(value, fixtures.countries(appKey)['countryJP']);
      expect(value, isNot('countryJP'));
    }
  });

  test('an unknown locale falls back to English rather than the key', () {
    expect(
      AppStrings.tForLocale('xx', AppStringKeys.aboutTitle),
      fixtures.messages('en')[AppStringKeys.aboutTitle],
    );
  });

  test('locale tag round-trips through resolve for common device tags', () {
    for (final tag in [
      'zh-CN',
      'zh-TW',
      'zh-HK',
      'ja-JP',
      'ko-KR',
      'en-US',
      'fr-FR',
      'es-419',
      'de-DE',
    ]) {
      final locale = AppLocalizations.localeFromTag(tag)!;
      final resolved = AppLocalizations.resolve(locale);
      expect(
        AppLocalizations.isSupportedLocale(resolved),
        isTrue,
        reason: '$tag resolves to unsupported $resolved',
      );
      expect(
        fixtures.catalogues.containsKey(
          AppLocalizations.localeKeyFor(resolved),
        ),
        isTrue,
        reason: '$tag has no catalogue',
      );
    }
  });

  test('per-locale catalogues carry translated (non-English) text', () {
    // Spot keys that must differ from English in CJK locales — guards against
    // wholesale copies of the English catalogue masquerading as translations.
    const probes = [AppStringKeys.chatMeLabel, AppStringKeys.aboutTitle];
    for (final appKey in ['zhHans', 'zhHant', 'ja', 'ko']) {
      for (final probe in probes) {
        expect(
          fixtures.messages(appKey)[probe],
          isNot(fixtures.messages('en')[probe]),
          reason: '$appKey.$probe is identical to English',
        );
      }
    }
  });

  test('effective catalogue is used by AppLocalizations.t', () {
    const l10n = AppLocalizations(Locale('ja'));
    expect(
      l10n.t(AppStringKeys.aboutTitle),
      fixtures.messages('ja')['aboutTitle'],
    );
  });

  test('profile tools strings are translated and interpolate chat IDs', () {
    for (final appKey in L10nFixtures.appKeys) {
      final title = AppStrings.tForLocale(
        appKey,
        AppStringKeys.profileToolsTitle,
      );
      final chatId = AppStrings.tForLocale(
        appKey,
        AppStringKeys.profileToolsProfileChatId,
        {'value1': 42},
      );

      expect(title.trim(), isNotEmpty);
      if (appKey != 'en') {
        expect(
          title,
          isNot(fixtures.messages('en')[AppStringKeys.profileToolsTitle]),
        );
      }
      expect(chatId, contains('42'));
      expect(chatId, isNot(contains('{value1}')));
    }
  });
}
