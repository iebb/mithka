//
//  kept_messages_settings_view.dart
//
//  Kept-message settings hub: the §1.4 self-build surfaces (message mirror,
//  ghost mode, local premium) collect behind one entry inside Advanced. The
//  whole page does not exist in builds without the compile-time opt-in.
//
//  开关的依赖关系在这里是可见的：总开关熄灭时全部记录开关变暗；「保存
//  已删除的消息」再管辖范围与快照两组——它们的记录路径都以它为前提。
//  幽灵渲染是纯显示开关，不受总开关牵连。每个区块都是带标题的
//  SettingsSection，卡片之间的间距由节标题自带，不再出现贴缝的分隔。
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

/// Hub page for every kept-message (§1.4) feature. Exists only in opted-in
/// self-built binaries; the settings root omits the row otherwise.
class KeptMessagesSettingsView extends StatelessWidget {
  const KeptMessagesSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    if (!allowTelegramTosViolations) return const SizedBox.shrink();
    return SettingsPageScaffold(
      title: AppStringKeys.keptSettingsTitle,
      onBack: () => Navigator.of(context).pop(),
      child: const SettingsListView(
        children: [
          _HistoryCoreSection(),
          _RecordScopeSection(),
          _SnapshotSection(),
          _SnapshotNote(),
          _TransferSection(),
          SettingsNote(text: AppStringKeys.historyRecordNote),
          _GhostSection(),
          _PremiumSection(),
        ],
      ),
    );
  }
}

/// A switch row plus a dimming wrapper: [active] false dims the row and
/// stops it answering taps — the setting genuinely cannot change while its
/// gate is off (the effective gating stays in the settings getters too, so
/// a stale pref can never leak into recording).
class _GatedSwitch extends StatelessWidget {
  const _GatedSwitch({
    required this.switchKey,
    required this.titleKey,
    required this.value,
    required this.onChanged,
    required this.active,
  });

  final Key switchKey;
  final String titleKey;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: active ? 1 : 0.45,
      child: SettingsSwitchRow(
        key: switchKey,
        title: titleKey.l10n(context),
        value: value,
        enabled: active,
        onChanged: onChanged,
      ),
    );
  }
}

/// Master switch and the three record features directly under it: what gets
/// recorded at all. The ghost render switch is display-only and stays lit
/// whatever the master says — turning recording off must not hide kept ghosts.
class _HistoryCoreSection extends StatelessWidget {
  const _HistoryCoreSection();

  @override
  Widget build(BuildContext context) {
    final settings = MessageHistorySettings.shared;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final masterOn = settings.enableAll;
        return SettingsSection(
          titleKey: AppStringKeys.keptHistorySection,
          rows: [
            SettingsSwitchRow(
              key: const ValueKey('history-enable-all'),
              title: AppStringKeys.historyEnableAll.l10n(context),
              value: settings.enableAll,
              onChanged: settings.setEnableAll,
            ),
            _GatedSwitch(
              switchKey: const ValueKey('history-record-deleted'),
              titleKey: AppStringKeys.historyRecordDeleted,
              value: settings.recordDeleted,
              onChanged: settings.setRecordDeleted,
              active: masterOn,
            ),
            _GatedSwitch(
              switchKey: const ValueKey('history-record-edits'),
              titleKey: AppStringKeys.historyRecordEdits,
              value: settings.recordEdits,
              onChanged: settings.setRecordEdits,
              active: masterOn,
            ),
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

/// Per conversation-type recording dims. They narrow the deleted-recording
/// switch (a type that is off records nothing for its chats), so both the
/// master switch and the deleted-recording switch must be on for them to
/// bite; the rows dim when either is off.
class _RecordScopeSection extends StatelessWidget {
  const _RecordScopeSection();

  @override
  Widget build(BuildContext context) {
    final settings = MessageHistorySettings.shared;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final active = settings.enableAll && settings.recordDeleted;
        return SettingsSection(
          titleKey: AppStringKeys.historyRecordSection,
          rows: [
            _GatedSwitch(
              switchKey: const ValueKey('history-record-private'),
              titleKey: AppStringKeys.historyRecordPrivate,
              value: settings.recordPrivate,
              onChanged: settings.setRecordPrivate,
              active: active,
            ),
            _GatedSwitch(
              switchKey: const ValueKey('history-record-groups'),
              titleKey: AppStringKeys.historyRecordGroups,
              value: settings.recordGroups,
              onChanged: settings.setRecordGroups,
              active: active,
            ),
            _GatedSwitch(
              switchKey: const ValueKey('history-record-channels'),
              titleKey: AppStringKeys.historyRecordChannels,
              value: settings.recordChannels,
              onChanged: settings.setRecordChannels,
              active: active,
            ),
            _GatedSwitch(
              switchKey: const ValueKey('history-record-bots'),
              titleKey: AppStringKeys.historyRecordBots,
              value: settings.recordBots,
              onChanged: settings.setRecordBots,
              active: active,
            ),
          ],
        );
      },
    );
  }
}

/// Media snapshots per conversation class. The snapshot path only runs for
/// messages the mirror records, so it needs the same chain as the record
/// dims above.
class _SnapshotSection extends StatelessWidget {
  const _SnapshotSection();

  @override
  Widget build(BuildContext context) {
    final settings = MessageHistorySettings.shared;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final active = settings.enableAll && settings.recordDeleted;
        return SettingsSection(
          titleKey: AppStringKeys.historySnapshotSection,
          rows: [
            _GatedSwitch(
              switchKey: const ValueKey('history-snapshot-private'),
              titleKey: AppStringKeys.historySnapshotPrivate,
              value: settings.snapshotPrivate,
              onChanged: settings.setSnapshotPrivate,
              active: active,
            ),
            _GatedSwitch(
              switchKey: const ValueKey('history-snapshot-groups'),
              titleKey: AppStringKeys.historySnapshotGroups,
              value: settings.snapshotGroups,
              onChanged: settings.setSnapshotGroups,
              active: active,
            ),
            _GatedSwitch(
              switchKey: const ValueKey('history-snapshot-channels'),
              titleKey: AppStringKeys.historySnapshotChannels,
              value: settings.snapshotChannels,
              onChanged: settings.setSnapshotChannels,
              active: active,
            ),
          ],
        );
      },
    );
  }
}

/// The snapshot section's explanatory line. Lives BETWEEN sections as its
/// own scroll child — a note inside the section's rows would sit on the
/// card's white surface with a different inset than every other note in
/// the app, which all render on the grouped background below a card.
class _SnapshotNote extends StatelessWidget {
  const _SnapshotNote();

  @override
  Widget build(BuildContext context) {
    return const SettingsNote(text: AppStringKeys.historySnapshotNote);
  }
}

/// Export/import entry plus the deleted-badge style picker — the mirror's
/// data-management block.
class _TransferSection extends StatelessWidget {
  const _TransferSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      titleKey: AppStringKeys.historyTransferSection,
      rows: [
        SettingsRow(
          key: const ValueKey('kept-history-transfer'),
          title: AppStringKeys.historyTransferTitle.l10n(context),
          leading: const SettingsLeadingIcon(icon: HeroAppIcons.share),
          onTap: () => Navigator.of(context).push(
            AppPageRoute<void>(
              pageBuilder: (_, _, _) => const MessageHistoryTransferView(),
            ),
          ),
        ),
        _BadgeStyleRow(),
      ],
    );
  }
}

/// Ghost-mode navigation (anti-recall style stealth), independent of the
/// history mirror.
class _GhostSection extends StatelessWidget {
  const _GhostSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      titleKey: AppStringKeys.keptGhostSection,
      rows: [
        SettingsRow(
          key: const ValueKey('kept-ghost-mode'),
          title: AppStringKeys.ghostModeTitle,
          leading: const SettingsLeadingIcon(icon: HeroAppIcons.eyeSlash),
          onTap: () => Navigator.of(context).push(
            AppPageRoute<void>(
              pageBuilder: (_, _, _) => const GhostModeSettingsView(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Local premium toggle.
class _PremiumSection extends StatelessWidget {
  const _PremiumSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      titleKey: AppStringKeys.keptPremiumSection,
      rows: [_LocalPremiumRow()],
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
        key: const ValueKey('kept-badge-style'),
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
                key: ValueKey('kept-badge-style-${style.name}'),
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
        key: const ValueKey('kept-local-premium'),
        title: AppStringKeys.localPremiumTitle.l10n(context),
        value: premium.enabled,
        onChanged: premium.setEnabled,
      ),
    );
  }
}
