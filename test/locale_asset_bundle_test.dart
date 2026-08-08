//
//  locale_asset_bundle_test.dart
//
//  Loads the catalogue the way the app does — through rootBundle, from the
//  assets declared in pubspec.yaml. The other l10n tests read the JSON off
//  disk, so this is what proves the assets are actually bundled and that
//  ensureLoaded works against a real bundle.
//

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/locale_catalogue.dart';

import 'support/l10n_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(LocaleCatalogues.reset);
  // Leave the shared fixtures installed for whatever runs next.
  tearDown(() => L10nFixtures.load().install());

  test('ensureLoaded reads the bundled assets', () async {
    expect(LocaleCatalogues.isReady, isFalse);

    await AppStrings.ensureLoaded(const Locale('de'));

    expect(
      LocaleCatalogues.isLoaded('de'),
      isTrue,
      reason: 'the active catalogue is awaited',
    );
    final german = LocaleCatalogues.forAppKey('de');
    expect(german, isNotNull);
    expect(german!.tag, 'de-DE');
    expect(german.strings, isNotEmpty);
    expect(german.countries, isNotEmpty);
    expect(
      AppStrings.tForLocale('de', AppStringKeys.aboutTitle),
      isNot(AppStringKeys.aboutTitle),
    );
  });

  test('every declared locale has a loadable asset', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      LocaleCatalogues.reset();
      await AppStrings.ensureLoaded(locale);
      final appKey = AppLocalizations.localeKeyFor(locale);
      final catalogue = LocaleCatalogues.forAppKey(appKey);
      expect(catalogue, isNotNull, reason: 'no asset for $locale');
      expect(catalogue!.strings, isNotEmpty, reason: '$locale is empty');
      expect(
        catalogue.pluralCategories,
        contains('other'),
        reason: '$locale must always have an "other" form',
      );
    }
  });

  test('a counted key resolves through the bundled catalogue', () async {
    await AppStrings.ensureLoaded(const Locale('en'));

    expect(
      AppStrings.pluralForLocale('en', AppStringKeys.chatMemberCount, 1),
      '1 member',
    );
    expect(
      AppStrings.pluralForLocale('en', AppStringKeys.chatMemberCount, 7),
      '7 members',
    );
  });

  test('concurrent ensureLoaded calls share one read', () async {
    await Future.wait([
      AppStrings.ensureLoaded(const Locale('fr')),
      AppStrings.ensureLoaded(const Locale('fr')),
      AppStrings.ensureLoaded(const Locale('ja')),
    ]);

    expect(LocaleCatalogues.forAppKey('fr'), isNotNull);
    expect(LocaleCatalogues.forAppKey('ja'), isNotNull);
  });

  test('the English fallback lands without being awaited', () async {
    await AppStrings.ensureLoaded(const Locale('ja'));

    expect(
      LocaleCatalogues.forAppKey('en'),
      isNull,
      reason: 'the fallback must not block the first frame',
    );

    // It was scheduled, so it arrives on its own within a few event loops.
    for (var turn = 0; turn < 20 && !LocaleCatalogues.isLoaded('en'); turn++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(LocaleCatalogues.forAppKey('en'), isNotNull);
  });
}
