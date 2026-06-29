//
//  feature_settings_view.dart
//
//  功能: toggles for optional app sections and capability surfaces.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class FeatureSettingsView extends StatelessWidget {
  const FeatureSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '功能', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                _sectionHeader(context, '底部标签'),
                SettingsCard(
                  children: [
                    SettingsSwitchRow(
                      title: '频道',
                      value: theme.showChannelsTab,
                      onChanged: (value) => theme.showChannelsTab = value,
                    ),
                    const InsetDivider(leadingInset: 16),
                    SettingsSwitchRow(
                      title: '动态',
                      value: theme.showMomentsTab,
                      onChanged: (value) => theme.showMomentsTab = value,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.l10n(context),
        style: TextStyle(
          fontSize: AppTextSize.caption,
          color: context.colors.textTertiary,
        ),
      ),
    ),
  );
}
