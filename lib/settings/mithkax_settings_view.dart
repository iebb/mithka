//
//  mithkax_settings_view.dart
//
//  Mithka X 设置中心：本 fork 的自建功能（消息历史镜像、幽灵模式、
//  本地大会员）全部收拢在这一个入口里，主设置列表只留一行指进来。
//  Telegram API Terms §1.4 的功能在未 opt-in 的构建里整页不存在。
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../config/build_flags.dart';
import '../history/message_history_settings.dart';
import '../history/message_history_view.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import 'ghost_mode_settings_view.dart';
import 'local_premium.dart';

/// Hub page for every Mithka X fork feature. Exists only in opted-in
/// self-built binaries; the settings root omits the row otherwise.
class MithkaXSettingsView extends StatelessWidget {
  const MithkaXSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    if (!allowTelegramTosViolations) return const SizedBox.shrink();
    return SettingsPageScaffold(
      title: AppStringKeys.mithkaxSettingsTitle,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsSection(
            titleKey: AppStringKeys.mithkaxHistorySection,
            rows: [
              _HistorySwitches(),
              SettingsRow(
                key: const ValueKey('mithkax-history-viewer'),
                title: AppStringKeys.historySettingsRow,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.clock),
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => const MessageHistoryView(),
                  ),
                ),
              ),
            ],
          ),
          const SettingsNote(text: AppStringKeys.historyRecordNote),
          SettingsSection(
            titleKey: AppStringKeys.mithkaxGhostSection,
            rows: [
              SettingsRow(
                key: const ValueKey('mithkax-ghost-mode'),
                title: AppStringKeys.ghostModeTitle,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.eyeSlash),
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => const GhostModeSettingsView(),
                  ),
                ),
              ),
            ],
          ),
          SettingsSection(
            titleKey: AppStringKeys.mithkaxPremiumSection,
            rows: [_LocalPremiumRow()],
          ),
          const SettingsNote(text: AppStringKeys.localPremiumNote),
        ],
      ),
    );
  }
}

/// The three recording switches plus the snapshot scope switches, rebuilt by
/// the store's own notifications — without a listener the row reads a stale
/// bool after a tap and the switch looks dead.
class _HistorySwitches extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = MessageHistorySettings.shared;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsSwitchRow(
            key: const ValueKey('history-record-deleted'),
            title: AppStringKeys.historyRecordDeleted.l10n(context),
            value: settings.recordDeleted,
            onChanged: settings.setRecordDeleted,
          ),
          SettingsSwitchRow(
            key: const ValueKey('history-record-edits'),
            title: AppStringKeys.historyRecordEdits.l10n(context),
            value: settings.recordEdits,
            onChanged: settings.setRecordEdits,
          ),
          SettingsSwitchRow(
            key: const ValueKey('history-render-ghosts'),
            title: AppStringKeys.historyRenderGhosts.l10n(context),
            value: settings.renderGhosts,
            onChanged: settings.setRenderGhosts,
          ),
          SettingsSwitchRow(
            key: const ValueKey('history-snapshot-private'),
            title: AppStringKeys.historySnapshotPrivate.l10n(context),
            value: settings.snapshotPrivate,
            onChanged: settings.setSnapshotPrivate,
          ),
          SettingsSwitchRow(
            key: const ValueKey('history-snapshot-groups'),
            title: AppStringKeys.historySnapshotGroups.l10n(context),
            value: settings.snapshotGroups,
            onChanged: settings.setSnapshotGroups,
          ),
          SettingsSwitchRow(
            key: const ValueKey('history-snapshot-channels'),
            title: AppStringKeys.historySnapshotChannels.l10n(context),
            value: settings.snapshotChannels,
            onChanged: settings.setSnapshotChannels,
          ),
        ],
      ),
    );
  }
}

/// Local premium row, rebuilt from the store so the knob answers the tap.
class _LocalPremiumRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final premium = LocalPremium.shared;
    return ListenableBuilder(
      listenable: premium,
      builder: (context, _) => SettingsSwitchRow(
        key: const ValueKey('mithkax-local-premium'),
        title: AppStringKeys.localPremiumTitle.l10n(context),
        value: premium.enabled,
        onChanged: premium.setEnabled,
      ),
    );
  }
}
