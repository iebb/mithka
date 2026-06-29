import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/ui_components.dart';
import '../l10n/app_locale_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class LanguageSettingsView extends StatelessWidget {
  const LanguageSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = context.watch<AppLocaleController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '语言', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                SettingsCard(
                  children: [
                    _LanguageRow(
                      title: '跟随系统'.l10n(context),
                      selected: locale.followsSystem,
                      onTap: () => locale.locale = null,
                    ),
                    const InsetDivider(leadingInset: 16),
                    for (final option in AppLocaleController.options) ...[
                      _LanguageRow(
                        title: option.label,
                        selected:
                            !locale.followsSystem &&
                            AppLocaleController.labelFor(locale.locale!) ==
                                option.label,
                        onTap: () => locale.locale = option.locale,
                      ),
                      if (option != AppLocaleController.options.last)
                        const InsetDivider(leadingInset: 16),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
              if (selected)
                FaIcon(FontAwesomeIcons.check, size: 18, color: AppTheme.brand),
            ],
          ),
        ),
      ),
    );
  }
}
