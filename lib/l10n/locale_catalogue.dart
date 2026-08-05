import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One locale's strings, loaded from `assets/l10n/<tag>.json`.
///
/// The catalogue ships as data rather than generated Dart so a translation
/// change is an asset change. It is produced from `translations/strings/` by
/// `translations/tools/gen_assets.py`.
@immutable
class LocaleCatalogue {
  const LocaleCatalogue({
    required this.tag,
    required this.appKey,
    required this.pluralCategories,
    required this.strings,
    required this.plurals,
    required this.countries,
  });

  factory LocaleCatalogue.fromJson(Map<String, dynamic> json) {
    return LocaleCatalogue(
      tag: json['locale'] as String,
      appKey: json['appKey'] as String,
      pluralCategories: List<String>.unmodifiable(
        (json['pluralCategories'] as List).cast<String>(),
      ),
      strings: Map<String, String>.unmodifiable(
        (json['strings'] as Map).cast<String, String>(),
      ),
      plurals: Map<String, Map<String, String>>.unmodifiable({
        for (final entry in (json['plurals'] as Map).entries)
          entry.key as String: Map<String, String>.unmodifiable(
            (entry.value as Map).cast<String, String>(),
          ),
      }),
      countries: Map<String, String>.unmodifiable(
        (json['countries'] as Map).cast<String, String>(),
      ),
    );
  }

  final String tag;
  final String appKey;
  final List<String> pluralCategories;
  final Map<String, String> strings;
  final Map<String, Map<String, String>> plurals;
  final Map<String, String> countries;

  /// The template for [key], or null when this locale does not define it.
  ///
  /// [count] selects the CLDR category for a counted key and is ignored for a
  /// plain one.
  String? template(String key, {num? count}) {
    final plain = strings[key];
    if (plain != null) return plain;
    final forms = plurals[key];
    if (forms == null) return null;
    final category = count == null ? 'other' : pluralCategoryFor(appKey, count);
    return forms[category] ?? forms['other'] ?? forms.values.firstOrNull;
  }

  bool get isCounted => plurals.isNotEmpty;

  /// CLDR plural category for [count] in [appKey].
  ///
  /// Only the categories that CLDR reaches for integers are implemented, which
  /// is all Mithka formats. `translations/locales.json` declares the same sets
  /// and `translations/tools/check.py` keeps the two in step.
  static String pluralCategoryFor(String appKey, num count) {
    final n = count.abs();
    switch (appKey) {
      case 'zhHans':
      case 'zhHant':
      case 'ja':
      case 'ko':
        return 'other';
      case 'fr':
        // French groups zero with one: "0 message", "1 message", "2 messages".
        return n < 2 ? 'one' : 'other';
      default:
        return n == 1 ? 'one' : 'other';
    }
  }
}

/// Loads and caches the locale catalogues.
abstract final class LocaleCatalogues {
  static const _directory = 'assets/l10n';
  static const fallbackAppKey = 'en';

  static final Map<String, LocaleCatalogue> _loaded = {};
  static final Map<String, Future<void>> _inFlight = {};
  static Map<String, String>? _tagForAppKey;

  /// Catalogues already in memory, keyed by app locale key.
  @visibleForTesting
  static Map<String, LocaleCatalogue> get loaded => _loaded;

  static LocaleCatalogue? forAppKey(String appKey) => _loaded[appKey];

  static LocaleCatalogue? get fallback => _loaded[fallbackAppKey];

  /// True once the English catalogue is available, which is the point at which
  /// every key is guaranteed to resolve to real text.
  static bool get isReady => _loaded.containsKey(fallbackAppKey);

  /// Loads [appKey] and the English fallback, if they are not already in
  /// memory. Safe to call repeatedly and concurrently.
  static Future<void> ensureLoaded(String appKey) async {
    await Future.wait([
      if (appKey != fallbackAppKey) _load(appKey),
      _load(fallbackAppKey),
    ]);
  }

  static Future<void> _load(String appKey) {
    if (_loaded.containsKey(appKey)) return SynchronousFuture(null);
    return _inFlight[appKey] ??= _read(appKey).whenComplete(() {
      _inFlight.remove(appKey);
    });
  }

  static Future<void> _read(String appKey) async {
    final tag = (await _manifest())[appKey];
    if (tag == null) {
      throw StateError('No locale asset registered for "$appKey"');
    }
    final source = await rootBundle.loadString('$_directory/$tag.json');
    _loaded[appKey] = LocaleCatalogue.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  static Future<Map<String, String>> _manifest() async {
    final cached = _tagForAppKey;
    if (cached != null) return cached;
    final source = await rootBundle.loadString('$_directory/manifest.json');
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final locales = (decoded['locales'] as List).cast<Map<String, dynamic>>();
    return _tagForAppKey = Map<String, String>.unmodifiable({
      for (final locale in locales)
        locale['appKey'] as String: locale['tag'] as String,
    });
  }

  @visibleForTesting
  static void reset() {
    _loaded.clear();
    _inFlight.clear();
    _tagForAppKey = null;
  }

  /// Installs catalogues directly, for tests that must not touch the bundle.
  @visibleForTesting
  static void install(Iterable<LocaleCatalogue> catalogues) {
    for (final catalogue in catalogues) {
      _loaded[catalogue.appKey] = catalogue;
    }
  }
}
