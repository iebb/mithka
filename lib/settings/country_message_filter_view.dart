import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../auth/country_picker.dart';
import '../auth/telegram_country_names.dart';
import '../components/app_icons.dart';
import '../components/country_flag.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'country_message_filter.dart';

class CountryMessageFilterView extends StatefulWidget {
  const CountryMessageFilterView({super.key});

  @override
  State<CountryMessageFilterView> createState() =>
      _CountryMessageFilterViewState();
}

class _CountryMessageFilterViewState extends State<CountryMessageFilterView> {
  final CountryMessageFilter _filter = CountryMessageFilter.shared;
  final TextEditingController _search = TextEditingController();
  Map<String, String> _telegramNames = TelegramCountryNames.shared.cached;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _filter.addListener(_onFilterChanged);
    _search.addListener(_onSearchChanged);
    unawaited(_loadTelegramCountryNames());
  }

  @override
  void dispose() {
    _filter.removeListener(_onFilterChanged);
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    setState(() => _query = _search.text.trim().toLowerCase());
  }

  Future<void> _loadTelegramCountryNames() async {
    try {
      final names = await TelegramCountryNames.shared.load(refresh: true);
      if (mounted && names.isNotEmpty) {
        setState(() => _telegramNames = names);
      }
    } catch (_) {
      // Keep the offline fallback when Telegram's list isn't available.
    }
  }

  String _displayName(Country country) => country.displayName(_telegramNames);

  List<Country> get _countries {
    final sorted = [...Country.all]
      ..sort((a, b) => _displayName(a).compareTo(_displayName(b)));
    if (_query.isEmpty) return sorted;
    return sorted
        .where((country) {
          final name = _displayName(country).toLowerCase();
          return name.contains(_query) ||
              country.iso.toLowerCase().contains(_query) ||
              country.dial.contains(_query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = _filter.selectedCountries;
    return SettingsPageScaffold(
      title: AppStringKeys.blockingCountry.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          SettingsSearchField(
            controller: _search,
            hintText: AppStringKeys.blockingCountrySearch,
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsCard.rows(
            rows: [
              for (final country in _countries)
                _countryRow(country, selected.contains(country.iso), c),
            ],
          ),
        ],
      ),
    );
  }

  Widget _countryRow(Country country, bool isSelected, AppColors c) {
    return SettingsRow(
      title: _displayName(country),
      leading: CountryFlag(iso: country.iso, size: 22),
      showChevron: false,
      onTap: () => _filter.setCountrySelected(country.iso, !isSelected),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+${country.dial}',
            style: TextStyle(fontSize: 14, color: c.textSecondary),
          ),
          const SizedBox(width: AppSpacing.lg),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: isSelected ? AppTheme.brand : c.textTertiary,
                width: 1.5,
              ),
            ),
            child: isSelected
                ? AppIcon(HeroAppIcons.check, size: 15, color: AppTheme.onBrand)
                : null,
          ),
        ],
      ),
    );
  }
}
