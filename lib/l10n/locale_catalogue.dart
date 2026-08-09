import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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

  /// The `.unmodifiable` factories already convert element by element, so no
  /// `.cast()` view goes in front of them: that would be a second checked pass
  /// over ~3450 entries on the pre-first-frame path.
  factory LocaleCatalogue.fromJson(Map<String, dynamic> json) {
    return LocaleCatalogue(
      tag: json['locale'] as String,
      appKey: json['appKey'] as String,
      pluralCategories: List<String>.unmodifiable(
        json['pluralCategories'] as List,
      ),
      strings: Map<String, String>.unmodifiable(json['strings'] as Map),
      plurals: Map<String, Map<String, String>>.unmodifiable({
        for (final entry in (json['plurals'] as Map).entries)
          entry.key as String: Map<String, String>.unmodifiable(
            entry.value as Map,
          ),
      }),
      countries: Map<String, String>.unmodifiable(json['countries'] as Map),
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

  /// True once at least one catalogue is available, which is the point at
  /// which a key resolves to real text rather than to itself.
  static bool get isReady => _loaded.isNotEmpty;

  /// True once [appKey] itself is in memory.
  static bool isLoaded(String appKey) => _loaded.containsKey(appKey);

  /// Loads [appKey], and queues the English fallback for an idle moment.
  ///
  /// Only [appKey] is awaited. `check.py` and `l10n_completeness_test.dart`
  /// both enforce that every locale declares the same keys as English, so the
  /// active catalogue alone resolves every lookup and the fallback is a net
  /// for a broken invariant, not part of the normal path. Awaiting it here
  /// doubled the JSON the first frame waits on for seven of the eight locales
  /// — and starting it right away merely moved that 180-220 KB decode onto an
  /// arbitrary frame in the first seconds of the session, so it waits for a gap
  /// in the scheduler instead.
  ///
  /// Safe to call repeatedly and concurrently.
  static Future<void> ensureLoaded(String appKey) {
    if (appKey == fallbackAppKey) return _load(appKey);
    final active = _load(appKey);
    unawaited(
      SchedulerBinding.instance.scheduleTask(
        () => _load(fallbackAppKey),
        Priority.idle,
      ),
    );
    return active;
  }

  /// Awaits the English fallback as well. Tests and tooling that assert on
  /// fallback behaviour need it present rather than merely scheduled.
  @visibleForTesting
  static Future<void> ensureLoadedWithFallback(String appKey) => Future.wait([
    if (appKey != fallbackAppKey) _load(appKey),
    _load(fallbackAppKey),
  ]);

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
