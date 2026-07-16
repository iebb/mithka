import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/country_picker.dart';

/// Local-only filter for private chats from non-contacts in selected regions.
class CountryMessageFilter extends ChangeNotifier {
  CountryMessageFilter();

  static final CountryMessageFilter shared = CountryMessageFilter();

  static const _selectedCountriesKey = 'countryMessageFilter.selectedCountries';
  static const _exemptCommonPrivateGroupKey =
      'countryMessageFilter.exemptCommonPrivateGroup';
  static const _exemptThreeCommonGroupsKey =
      'countryMessageFilter.exemptThreeCommonGroups';
  static const _exemptPlainTextKey = 'countryMessageFilter.exemptPlainText';
  static const _exemptNonDefaultAvatarKey =
      'countryMessageFilter.exemptNonDefaultAvatar';

  SharedPreferences? _prefs;
  Set<String> _selectedCountries = const <String>{};
  bool _exemptCommonPrivateGroup = true;
  bool _exemptThreeCommonGroups = true;
  bool _exemptPlainText = true;
  bool _exemptNonDefaultAvatar = true;

  Set<String> get selectedCountries => Set.unmodifiable(_selectedCountries);
  bool get isEnabled => _selectedCountries.isNotEmpty;
  bool get exemptCommonPrivateGroup => _exemptCommonPrivateGroup;
  bool get exemptThreeCommonGroups => _exemptThreeCommonGroups;
  bool get exemptPlainText => _exemptPlainText;
  bool get exemptNonDefaultAvatar => _exemptNonDefaultAvatar;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _selectedCountries =
        (prefs.getStringList(_selectedCountriesKey) ?? const [])
            .map((iso) => iso.trim().toUpperCase())
            .where((iso) => Country.all.any((country) => country.iso == iso))
            .toSet();
    _exemptCommonPrivateGroup =
        prefs.getBool(_exemptCommonPrivateGroupKey) ?? true;
    _exemptThreeCommonGroups =
        prefs.getBool(_exemptThreeCommonGroupsKey) ?? true;
    _exemptPlainText = prefs.getBool(_exemptPlainTextKey) ?? true;
    _exemptNonDefaultAvatar = prefs.getBool(_exemptNonDefaultAvatarKey) ?? true;
  }

  void setCountrySelected(String iso, bool selected) {
    final normalized = iso.trim().toUpperCase();
    if (!Country.all.any((country) => country.iso == normalized)) return;
    final next = {..._selectedCountries};
    if (selected) {
      next.add(normalized);
    } else {
      next.remove(normalized);
    }
    if (setEquals(next, _selectedCountries)) return;
    _selectedCountries = next;
    _prefs?.setStringList(_selectedCountriesKey, next.toList()..sort());
    notifyListeners();
  }

  void setExemptCommonPrivateGroup(bool value) {
    if (_exemptCommonPrivateGroup == value) return;
    _exemptCommonPrivateGroup = value;
    _prefs?.setBool(_exemptCommonPrivateGroupKey, value);
    notifyListeners();
  }

  void setExemptThreeCommonGroups(bool value) {
    if (_exemptThreeCommonGroups == value) return;
    _exemptThreeCommonGroups = value;
    _prefs?.setBool(_exemptThreeCommonGroupsKey, value);
    notifyListeners();
  }

  void setExemptPlainText(bool value) {
    if (_exemptPlainText == value) return;
    _exemptPlainText = value;
    _prefs?.setBool(_exemptPlainTextKey, value);
    notifyListeners();
  }

  void setExemptNonDefaultAvatar(bool value) {
    if (_exemptNonDefaultAvatar == value) return;
    _exemptNonDefaultAvatar = value;
    _prefs?.setBool(_exemptNonDefaultAvatarKey, value);
    notifyListeners();
  }

  bool matchesUser({
    bool isContact = false,
    String? phoneNumber,
    String? countryCode,
  }) {
    if (!isEnabled) return false;
    final normalizedCountryCode = countryCode?.trim().toUpperCase();
    final accountCountry = Country.all
        .where((country) => country.iso == normalizedCountryCode)
        .firstOrNull;
    final digits = (phoneNumber ?? '').replaceAll(RegExp(r'\D'), '');
    final country = accountCountry ?? Country.match(digits);
    return country != null && _selectedCountries.contains(country.iso);
  }

  bool shouldExempt({
    required bool hasCommonPrivateGroup,
    required int commonGroupCount,
    required bool isPlainTextWithoutLinks,
    required bool hasNonDefaultAvatar,
  }) {
    return _exemptCommonPrivateGroup && hasCommonPrivateGroup ||
        _exemptThreeCommonGroups && commonGroupCount >= 3 ||
        _exemptPlainText && isPlainTextWithoutLinks ||
        _exemptNonDefaultAvatar && hasNonDefaultAvatar;
  }
}
