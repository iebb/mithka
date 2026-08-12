//
//  feature_settings_view.dart
//
//  功能: toggles for optional app sections and capability surfaces.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../moments/short_video_availability.dart';
import '../theme/theme_controller.dart';
import 'safety_notice_controller.dart';

class FeatureSettingsView extends StatelessWidget {
  const FeatureSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final safetyNotice = context.watch<SafetyNoticeController>();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.featureTitle),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsSection(
            titleKey: AppStringKeys.featureBottomTabs,
            rows: [
              SettingsSwitchRow(
                title: AppStrings.t(AppStringKeys.tabChannels),
                value: theme.showChannelsTab,
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.towerBroadcast,
                ),
                onChanged: (value) => theme.showChannelsTab = value,
              ),
              SettingsSwitchRow(
                title: AppStrings.t(AppStringKeys.tabMoments),
                value: theme.showMomentsTab,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.camera),
                onChanged: (value) => theme.showMomentsTab = value,
              ),
              if (shortVideosAvailableOnPlatform()) ...[
                SettingsSwitchRow(
                  title: AppStrings.t(AppStringKeys.momentsShortVideos),
                  value: theme.showShortVideos,
                  leading: const SettingsLeadingIcon(icon: HeroAppIcons.video),
                  onChanged: (value) => theme.showShortVideos = value,
                ),
              ],
            ],
          ),
          SettingsSection(
            titleKey: AppStringKeys.communityTitle,
            rows: [
              SettingsSwitchRow(
                title: AppStrings.t(AppStringKeys.featureCommunitiesEnabled),
                value: theme.communitiesEnabled,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.users),
                onChanged: (value) => theme.communitiesEnabled = value,
              ),
            ],
          ),
          SettingsSection(
            titleKey: AppStringKeys.featureSafety,
            rows: [
              SettingsSwitchRow(
                title: AppStrings.t(AppStringKeys.featureDisableSafetyNotice),
                value: safetyNotice.disabled,
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.shieldHalved,
                ),
                onChanged: (value) => safetyNotice.disabled = value,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
