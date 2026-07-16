import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'rich_message_relay_config.dart';
import 'rich_message_relay_view.dart';
import 'transfer_boost_config.dart';
import 'transfer_boost_view.dart';

class AdvancedSettingsView extends StatefulWidget {
  const AdvancedSettingsView({super.key});

  @override
  State<AdvancedSettingsView> createState() => _AdvancedSettingsViewState();
}

class _AdvancedSettingsViewState extends State<AdvancedSettingsView> {
  bool _relayConfigured = false;
  bool _transferBoostEnabled = false;

  @override
  void initState() {
    super.initState();
    _refreshRelayStatus();
    _refreshTransferBoostStatus();
  }

  Future<void> _refreshRelayStatus() async {
    final configured = await RichMessageRelayConfig.isConfigured();
    if (mounted) setState(() => _relayConfigured = configured);
  }

  Future<void> _openRelaySettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RichMessageRelayView()),
    );
    await _refreshRelayStatus();
  }

  Future<void> _refreshTransferBoostStatus() async {
    final config = await TransferBoostConfig.load();
    if (mounted) setState(() => _transferBoostEnabled = config.enabled);
  }

  Future<void> _openTransferBoostSettings() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const TransferBoostView()));
    await _refreshTransferBoostStatus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.advancedTitle,
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
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    bottom: AppSpacing.sm,
                  ),
                  child: Text(
                    AppStringKeys.advancedInput.l10n(context),
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textTertiary,
                    ),
                  ),
                ),
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStringKeys.richTextRelayBotTitle,
                      value:
                          (_relayConfigured
                                  ? AppStringKeys.richTextRelayBotConfigured
                                  : AppStringKeys.richTextRelayBotNotConfigured)
                              .l10n(context),
                      leading: AppIcon(
                        HeroAppIcons.key,
                        size: 21,
                        color: AppTheme.brand,
                      ),
                      onTap: _openRelaySettings,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    bottom: AppSpacing.sm,
                  ),
                  child: Text(
                    AppStringKeys.advancedNetwork.l10n(context),
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textTertiary,
                    ),
                  ),
                ),
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStringKeys.transferBoostTitle,
                      value:
                          (_transferBoostEnabled
                                  ? AppStringKeys.transferBoostEnabled
                                  : AppStringKeys.transferBoostDisabled)
                              .l10n(context),
                      leading: AppIcon(
                        HeroAppIcons.arrowsUpDown,
                        size: 21,
                        color: AppTheme.brand,
                      ),
                      onTap: _openTransferBoostSettings,
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
}
