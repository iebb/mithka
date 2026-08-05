import 'dart:convert';
import 'dart:io';

import 'package:mithka/l10n/locale_catalogue.dart';

/// Reads the generated locale assets straight off disk.
///
/// Tests assert against the shipped catalogue rather than a Dart table, so a
/// translation regression is caught in the same file the app actually loads.
/// `rootBundle` is unavailable in a plain `flutter test` without a widget
/// binding, and these assertions are pure data checks, so they read the files.
class L10nFixtures {
  L10nFixtures._(this.catalogues);

  factory L10nFixtures.load() {
    final directory = Directory('assets/l10n');
    if (!directory.existsSync()) {
      throw StateError(
        'assets/l10n is missing; run translations/tools/gen_assets.py',
      );
    }
    final manifest =
        jsonDecode(File('assets/l10n/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final entries = (manifest['locales'] as List).cast<Map<String, dynamic>>();
    return L10nFixtures._({
      for (final entry in entries)
        entry['appKey'] as String: LocaleCatalogue.fromJson(
          jsonDecode(
                File('assets/l10n/${entry['tag']}.json').readAsStringSync(),
              )
              as Map<String, dynamic>,
        ),
    });
  }

  final Map<String, LocaleCatalogue> catalogues;

  static const appKeys = <String>[
    'en',
    'zhHans',
    'zhHant',
    'ja',
    'ko',
    'fr',
    'es',
    'de',
  ];

  LocaleCatalogue operator [](String appKey) {
    final catalogue = catalogues[appKey];
    if (catalogue == null) throw StateError('No catalogue for "$appKey"');
    return catalogue;
  }

  LocaleCatalogue get en => this['en'];

  Iterable<LocaleCatalogue> get all => appKeys.map((key) => this[key]);

  /// Flat message strings for [appKey], excluding country names.
  Map<String, String> messages(String appKey) => this[appKey].strings;

  Map<String, String> countries(String appKey) => this[appKey].countries;

  /// Installs these catalogues into [LocaleCatalogues] so `AppStrings` resolves
  /// without touching the asset bundle.
  void install() {
    LocaleCatalogues.reset();
    LocaleCatalogues.install(all);
  }
}
