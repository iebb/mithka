//
//  developer_settings_view.dart
//
//  Hidden diagnostics toggles used while reproducing device-only issues.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'api_credentials_view.dart';
import 'developer_mode_controller.dart';

class DeveloperSettingsView extends StatelessWidget {
  const DeveloperSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final developer = context.watch<DeveloperModeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.developerModeTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.apiCredentialsTitle),
                      value: AppStrings.t(
                        AppStringKeys.apiCredentialsCustomClientApi,
                      ),
                      leading: AppIcon(
                        HeroAppIcons.cloudArrowDown,
                        size: 21,
                        color: AppTheme.brand,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ApiCredentialsView(),
                        ),
                      ),
                    ),
                    const InsetDivider(leadingInset: 48),
                    SettingsSwitchRow(
                      title: AppStrings.t(
                        AppStringKeys.developerModePiPBoundsOverlay,
                      ),
                      value: developer.showPiPBounds,
                      onChanged: (value) =>
                          context
                                  .read<DeveloperModeController>()
                                  .showPiPBounds =
                              value,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    AppStrings.t(
                      AppStringKeys.developerModePiPBoundsOverlayDescription,
                    ),
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textTertiary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
