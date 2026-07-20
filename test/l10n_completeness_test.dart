//
//  l10n_completeness_test.dart
//
//  Guards the "every string is localized in every supported language"
//  invariant. A key missing from any per-locale table would silently fall
//  back to English (or render the raw key name) in the UI, so this test
//  fails the build instead.
//

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/country_names.dart';
import 'package:mithka/l10n/messages/de.dart';
import 'package:mithka/l10n/messages/en.dart';
import 'package:mithka/l10n/messages/es.dart';
import 'package:mithka/l10n/messages/fr.dart';
import 'package:mithka/l10n/messages/ja.dart';
import 'package:mithka/l10n/messages/ko.dart';
import 'package:mithka/l10n/messages/zh_hans.dart';
import 'package:mithka/l10n/messages/zh_hant.dart';

const localeTables = <String, Map<String, String>>{
  'zhHans': zhHansMessages,
  'zhHant': zhHantMessages,
  'ja': jaMessages,
  'ko': koMessages,
  'en': enMessages,
  'fr': frMessages,
  'es': esMessages,
  'de': deMessages,
};

final placeholderPattern = RegExp(r'\{value\d\}');

Set<String> placeholdersOf(String value) =>
    placeholderPattern.allMatches(value).map((m) => m.group(0)!).toSet();

void main() {
  test('every supported locale resolves to a message table', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final key = AppLocalizations.localeKeyFor(locale);
      expect(
        localeTables.containsKey(key),
        isTrue,
        reason: 'locale $locale resolves to "$key" which has no table',
      );
    }
  });

  test('all locale tables share the exact key set', () {
    final reference = enMessages.keys.toSet();
    for (final entry in localeTables.entries) {
      final keys = entry.value.keys.toSet();
      expect(
        reference.difference(keys),
        isEmpty,
        reason: '${entry.key} is missing keys present in en',
      );
      expect(
        keys.difference(reference),
        isEmpty,
        reason: '${entry.key} has keys that en lacks',
      );
    }
  });

  test('no locale table contains an empty value', () {
    for (final entry in localeTables.entries) {
      for (final kv in entry.value.entries) {
        expect(
          kv.value.trim(),
          isNotEmpty,
          reason: '${entry.key}.${kv.key} is empty',
        );
      }
    }
  });

  test('placeholders match the English source in every locale', () {
    for (final entry in localeTables.entries) {
      for (final kv in entry.value.entries) {
        final expected = placeholdersOf(enMessages[kv.key] ?? '');
        expect(
          placeholdersOf(kv.value),
          expected,
          reason: '${entry.key}.${kv.key} placeholder mismatch',
        );
      }
    }
  });

  test('country names cover every locale with the same key set', () {
    final locales = localeTables.keys.toSet();
    expect(countryNames.keys.toSet(), locales);
    final reference = countryNames['en']!.keys.toSet();
    for (final entry in countryNames.entries) {
      expect(
        entry.value.keys.toSet(),
        reference,
        reason: 'countryNames[${entry.key}] key set differs from en',
      );
      for (final kv in entry.value.entries) {
        expect(
          kv.value.trim(),
          isNotEmpty,
          reason: 'countryNames[${entry.key}].${kv.key} is empty',
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
    final countries = countryNames['en']!.keys.toSet();
    for (final key in declared) {
      final resolvable = enMessages.containsKey(key) || countries.contains(key);
      expect(resolvable, isTrue, reason: 'key "$key" has no en entry');
      for (final entry in localeTables.entries) {
        if (countries.contains(key)) break;
        expect(
          entry.value.containsKey(key),
          isTrue,
          reason: 'key "$key" missing from ${entry.key}',
        );
      }
    }
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
      AppStrings.tForLocale(
        'zhHans',
        AppStringKeys.chatUnreadMessagesCount,
        {'value1': 1972},
      ),
      '1972条未读消息',
    );
  });

  test('tForLocale resolves country keys through countryNames', () {
    for (final localeKey in localeTables.keys) {
      final value = AppStrings.tForLocale(localeKey, 'countryJP');
      expect(value, countryNames[localeKey]!['countryJP']);
      expect(value, isNot('countryJP'));
    }
  });

  test('Telegram printf placeholders are interpolated for counted strings', () {
    AppStrings.telegramStringResolver = (_, _) => '%1\$d 条新消息';
    addTearDown(() => AppStrings.telegramStringResolver = null);

    expect(
      AppStrings.tForLocaleWithTelegram(
        'zhHans',
        AppStringKeys.chatNewMessagesCount,
        {'value1': 3},
      ),
      '3 条新消息',
    );
  });

  test('unresolved Telegram placeholders fall back to app strings', () {
    AppStrings.telegramStringResolver = (_, _) => '%1\$d 条新消息';
    addTearDown(() => AppStrings.telegramStringResolver = null);

    expect(
      AppStrings.tForLocaleWithTelegram(
        'zhHans',
        AppStringKeys.chatNewMessagesDivider,
      ),
      zhHansMessages[AppStringKeys.chatNewMessagesDivider],
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
        localeTables.containsKey(AppLocalizations.localeKeyFor(resolved)),
        isTrue,
        reason: '$tag has no message table',
      );
    }
  });

  test('per-locale tables carry translated (non-English) text', () {
    // Spot keys that must differ from English in CJK locales — guards against
    // wholesale copies of the English table masquerading as translations.
    const probes = [AppStringKeys.chatMeLabel, AppStringKeys.aboutTitle];
    for (final localeKey in ['zhHans', 'zhHant', 'ja', 'ko']) {
      for (final probe in probes) {
        expect(
          localeTables[localeKey]![probe],
          isNot(enMessages[probe]),
          reason: '$localeKey.$probe is identical to English',
        );
      }
    }
  });

  test('effective locale table is used by AppLocalizations.t', () {
    const l10n = AppLocalizations(Locale('ja'));
    expect(l10n.t(AppStringKeys.aboutTitle), jaMessages['aboutTitle']);
  });

  test('profile tools strings are translated and interpolate chat IDs', () {
    for (final localeKey in localeTables.keys) {
      final title = AppStrings.tForLocale(
        localeKey,
        AppStringKeys.profileToolsTitle,
      );
      final chatId = AppStrings.tForLocale(
        localeKey,
        AppStringKeys.profileToolsProfileChatId,
        {'value1': 42},
      );

      expect(title.trim(), isNotEmpty);
      if (localeKey != 'en') {
        expect(title, isNot(enMessages[AppStringKeys.profileToolsTitle]));
      }
      expect(chatId, contains('42'));
      expect(chatId, isNot(contains('{value1}')));
    }
  });
}
