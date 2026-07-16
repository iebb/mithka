import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../auth/country_picker.dart';
import '../auth/telegram_country_names.dart';
import '../components/app_icons.dart';
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
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.blockingCountry.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Container(
              height: AppMetric.searchHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                children: [
                  AppIcon(
                    HeroAppIcons.magnifyingGlass,
                    size: AppMetric.searchIcon,
                    color: c.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      autocorrect: false,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: AppStringKeys.blockingCountrySearch.l10n(
                          context,
                        ),
                        hintStyle: TextStyle(color: c.textTertiary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: _countries.length,
              itemBuilder: (context, index) {
                final country = _countries[index];
                final isSelected = selected.contains(country.iso);
                return Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 1),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        _filter.setCountrySelected(country.iso, !isSelected),
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(
                          index == 0 || index == _countries.length - 1 ? 10 : 0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            country.flag,
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _displayName(country),
                              style: TextStyle(
                                fontSize: 16,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '+${country.dial}',
                            style: TextStyle(
                              fontSize: 14,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.brand
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.brand
                                    : c.textTertiary,
                                width: 1.5,
                              ),
                            ),
                            child: isSelected
                                ? AppIcon(
                                    HeroAppIcons.check,
                                    size: 15,
                                    color: AppTheme.onBrand,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
