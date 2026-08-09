import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_client.dart';
import 'bot_api_endpoint_view.dart';
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
  String _botApiEndpoint = 'https://api.telegram.org';

  @override
  void initState() {
    super.initState();
    _refreshRelayStatus();
    _refreshTransferBoostStatus();
    _refreshBotApiEndpoint();
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

  Future<void> _refreshBotApiEndpoint() async {
    try {
      final endpoint = await TdClient.shared.configuredBotApiEndpoint();
      if (mounted) setState(() => _botApiEndpoint = endpoint.toString());
    } on Object {
      // Keep the public default if a detached account transport is closing.
    }
  }

  Future<void> _openBotApiEndpointSettings() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const BotApiEndpointView()));
    await _refreshBotApiEndpoint();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStringKeys.advancedTitle,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsSection(
            titleKey: AppStringKeys.advancedInput,
            rows: [
              SettingsRow(
                title: AppStringKeys.richTextRelayBotTitle,
                value:
                    (_relayConfigured
                            ? AppStringKeys.richTextRelayBotConfigured
                            : AppStringKeys.richTextRelayBotNotConfigured)
                        .l10n(context),
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.key),
                onTap: _openRelaySettings,
              ),
            ],
          ),
          SettingsSection(
            titleKey: AppStringKeys.advancedNetwork,
            rows: [
              SettingsRow(
                title: AppStringKeys.loginBotApiEndpoint,
                value: _botApiEndpoint,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.server),
                onTap: _openBotApiEndpointSettings,
              ),
              SettingsRow(
                title: AppStringKeys.transferBoostTitle,
                value:
                    (_transferBoostEnabled
                            ? AppStringKeys.transferBoostEnabled
                            : AppStringKeys.transferBoostDisabled)
                        .l10n(context),
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.arrowsUpDown,
                ),
                onTap: _openTransferBoostSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
