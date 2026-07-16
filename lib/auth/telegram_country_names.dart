import '../tdlib/td_client.dart';

typedef TelegramCountryNamesQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

/// Country names returned by Telegram for the active TDLib language.
///
/// Telegram iOS requests `help.getCountriesList` with the current language
/// code. TDLib's `getCountries` exposes that same server-maintained list, so we
/// use its localized `name` and retain the bundled names only as an offline
/// fallback.
class TelegramCountryNames {
  TelegramCountryNames({
    required TelegramCountryNamesQuery query,
    bool Function()? canQuery,
  }) : this._(query, canQuery ?? _alwaysCanQuery);

  TelegramCountryNames._shared()
    : this._(TdClient.shared.query, _tdClientIsActive);

  TelegramCountryNames._(this._query, this._canQuery);

  static final TelegramCountryNames shared = TelegramCountryNames._shared();

  final TelegramCountryNamesQuery _query;
  final bool Function() _canQuery;
  Map<String, String> _cached = const {};

  Map<String, String> get cached => _cached;

  Future<Map<String, String>> load({bool refresh = false}) async {
    if (!refresh && _cached.isNotEmpty) return _cached;
    if (!_canQuery()) return _cached;

    final response = await _query({
      '@type': 'getCountries',
    }).timeout(const Duration(seconds: 10));
    final parsed = parse(response);
    if (parsed.isNotEmpty) _cached = Map.unmodifiable(parsed);
    return _cached;
  }

  static Map<String, String> parse(Map<String, dynamic> response) {
    if (response['@type'] != 'countries') return const {};
    final rawCountries = response['countries'];
    if (rawCountries is! List) return const {};

    final names = <String, String>{};
    for (final raw in rawCountries) {
      if (raw is! Map) continue;
      final country = raw.cast<String, dynamic>();
      final iso = (country['country_code'] as String? ?? '')
          .trim()
          .toUpperCase();
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(iso)) continue;
      final localized = (country['name'] as String? ?? '').trim();
      final english = (country['english_name'] as String? ?? '').trim();
      final name = localized.isNotEmpty ? localized : english;
      if (name.isNotEmpty) names[iso] = name;
    }
    return names;
  }

  static bool _alwaysCanQuery() => true;
  static bool _tdClientIsActive() => TdClient.shared.hasActiveClient;
}
