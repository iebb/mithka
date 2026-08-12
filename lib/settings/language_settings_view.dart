import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_locale_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'translation_settings_view.dart';

class LanguageSettingsView extends StatelessWidget {
  const LanguageSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<AppLocaleController>();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.languageTitle),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsCard.rows(
            rows: [
              SettingsRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.globe),
                title: AppStringKeys.languageMithkaLanguage.l10n(context),
                value: locale.selectedLabel(context),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AppLanguageSettingsView(),
                  ),
                ),
              ),
              SettingsRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.comment),
                title: AppStrings.t(AppStringKeys.messageActionTranslate),
                value: AppStrings.t(AppStringKeys.translationSettingsTitle),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TranslationSettingsView(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AppLanguageSettingsView extends StatelessWidget {
  const AppLanguageSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppLocaleController>();
    const options = AppLocaleController.options;
    return SettingsPageScaffold(
      title: AppStringKeys.languageMithkaLanguage.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsCard.rows(
            dividerInset: AppMetric.settingsTextDividerInset,
            rows: [
              _LanguageRow(
                title: AppStringKeys.appLocaleFollowSystem.l10n(context),
                selected: controller.followsSystem,
                onTap: () => controller.locale = null,
              ),
              for (final option in options)
                _LanguageRow(
                  title: AppStrings.t(option.label),
                  selected:
                      !controller.followsSystem &&
                      AppLocaleController.labelFor(controller.locale!) ==
                          AppStrings.t(option.label),
                  onTap: () => controller.locale = option.locale,
                ),
            ],
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                  ],
                ),
              ),
              if (selected)
                AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand),
            ],
          ),
        ),
      ),
    );
  }
}
