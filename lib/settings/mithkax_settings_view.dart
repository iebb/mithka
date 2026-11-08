//
//  mithkax_settings_view.dart
//
//  Mithka X 设置中心：本 fork 的自建功能收拢在这一个入口里，主设置列表
//  只留一行指进来。Telegram API Terms §1.4 的功能在未 opt-in 的构建里
//  整页不存在。消息历史没有统一的查看入口——浏览按聊天走，导出导入
//  与删除标记样式在这里配置。
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../config/build_flags.dart';
import '../history/message_history_settings.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'ghost_mode_settings_view.dart';
import 'local_premium.dart';
import 'message_history_transfer_view.dart';

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
            rows: [_HistorySwitches()],
          ),
          SettingsCard.rows(
            rows: [
              SettingsRow(
                key: const ValueKey('mithkax-history-transfer'),
                title: AppStringKeys.historyTransferTitle.l10n(context),
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.share),
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) =>
                        const MessageHistoryTransferView(),
                  ),
                ),
              ),
              _BadgeStyleRow(),
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

/// The mirror's runtime switches, rebuilt by the settings store's own
/// notifications — without a listener the row reads a stale bool after a
/// tap and the switch looks dead. Sub-switches that depend on a master
/// switch render dimmed while it is off (the exteraless visual): they stay
/// tappable so the user can pre-configure, and the effective value stays
/// gated in the settings getters.
class _HistorySwitches extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = MessageHistorySettings.shared;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final enabled = settings.enableAll;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsSwitchRow(
              key: const ValueKey('history-enable-all'),
              title: AppStringKeys.historyEnableAll.l10n(context),
              value: settings.enableAll,
              onChanged: settings.setEnableAll,
            ),
            Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Column(
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
                    key: const ValueKey('history-record-read-times'),
                    title: AppStringKeys.historyRecordReadTimes.l10n(context),
                    value: settings.recordReadTimes,
                    onChanged: settings.setRecordReadTimes,
                  ),
                  SettingsSwitchRow(
                    key: const ValueKey('history-record-private'),
                    title: AppStringKeys.historyRecordPrivate.l10n(context),
                    value: settings.recordPrivate,
                    onChanged: settings.setRecordPrivate,
                  ),
                  SettingsSwitchRow(
                    key: const ValueKey('history-record-groups'),
                    title: AppStringKeys.historyRecordGroups.l10n(context),
                    value: settings.recordGroups,
                    onChanged: settings.setRecordGroups,
                  ),
                  SettingsSwitchRow(
                    key: const ValueKey('history-record-channels'),
                    title: AppStringKeys.historyRecordChannels.l10n(context),
                    value: settings.recordChannels,
                    onChanged: settings.setRecordChannels,
                  ),
                  SettingsSwitchRow(
                    key: const ValueKey('history-record-bots'),
                    title: AppStringKeys.historyRecordBots.l10n(context),
                    value: settings.recordBots,
                    onChanged: settings.setRecordBots,
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
            ),
            // Display-only: independent of the master recording switch.
            SettingsSwitchRow(
              key: const ValueKey('history-render-ghosts'),
              title: AppStringKeys.historyRenderGhosts.l10n(context),
              value: settings.renderGhosts,
              onChanged: settings.setRenderGhosts,
            ),
          ],
        );
      },
    );
  }
}

/// Deleted-badge style picker: icon / text / both.
class _BadgeStyleRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = MessageHistorySettings.shared;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SettingsRow(
        key: const ValueKey('mithkax-badge-style'),
        title: AppStringKeys.historyBadgeStyleTitle.l10n(context),
        value: _styleLabel(context, settings.badgeStyle),
        leading: const SettingsLeadingIcon(icon: HeroAppIcons.trash),
        onTap: () => _pickStyle(context, settings),
      ),
    );
  }

  String _styleLabel(
    BuildContext context,
    GhostBadgeStyle style,
  ) => switch (style) {
    GhostBadgeStyle.icon => AppStringKeys.historyBadgeStyleIcon.l10n(context),
    GhostBadgeStyle.text => AppStringKeys.historyBadgeStyleText.l10n(context),
    GhostBadgeStyle.both => AppStringKeys.historyBadgeStyleBoth.l10n(context),
  };

  Future<void> _pickStyle(
    BuildContext context,
    MessageHistorySettings settings,
  ) async {
    String label(GhostBadgeStyle style) => _styleLabel(context, style);
    final picked = await showModalBottomSheet<GhostBadgeStyle>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final style in GhostBadgeStyle.values)
              ListTile(
                key: ValueKey('mithkax-badge-style-${style.name}'),
                title: Text(label(style)),
                trailing: settings.badgeStyle == style
                    ? AppIcon(
                        HeroAppIcons.circleCheck,
                        size: 18,
                        color: context.colors.linkBlue,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(style),
              ),
          ],
        ),
      ),
    );
    if (picked != null) settings.setBadgeStyle(picked);
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
