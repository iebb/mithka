import 'dart:async';

import 'package:flutter/material.dart';

import '../chats/local_pin_store.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../config/build_flags.dart';
import '../history/message_history_view.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_motion.dart';
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

  /// The server's pin cap, for the switch's explanatory line. The default
  /// matches the server's own default until the option answers.
  int _serverPinLimit = 5;

  @override
  void initState() {
    super.initState();
    _refreshRelayStatus();
    _refreshTransferBoostStatus();
    _refreshBotApiEndpoint();
    LocalPinStore.shared.addListener(_handleLocalPinStoreChanged);
    unawaited(_refreshServerPinLimit());
  }

  @override
  void dispose() {
    LocalPinStore.shared.removeListener(_handleLocalPinStoreChanged);
    super.dispose();
  }

  void _handleLocalPinStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setUnlimitedLocalPins(bool enabled) async {
    await LocalPinStore.shared.setUnlimitedEnabled(enabled);
  }

  Future<void> _refreshServerPinLimit() async {
    try {
      final option = await TdClient.shared.query({
        '@type': 'getOption',
        'name': 'pinned_chat_count_max',
      });
      final value = option.integer('value');
      if (mounted && value != null && value > 0) {
        setState(() => _serverPinLimit = value);
      }
    } catch (_) {
      // Keep the server default until the option answers.
    }
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
          // Device-only pins beyond the server cap: everything stays in this
          // app's own preference store, and the store is inert while the
          // switch is off (the default).
          const SettingsSectionHeader(AppStringKeys.chatListLocalPinEnabled),
          SettingsCard.rows(
            rows: [
              SettingsSwitchRow(
                key: const ValueKey('local-pins-unlimited'),
                title: AppStrings.t(AppStringKeys.chatListLocalPinEnabled),
                subtitle: AppStrings.t(
                  AppStringKeys.chatListLocalPinLimitReached,
                  {'value1': '$_serverPinLimit'},
                ),
                value: LocalPinStore.shared.unlimitedEnabled,
                onChanged: (value) => unawaited(_setUnlimitedLocalPins(value)),
              ),
            ],
          ),
          // Telegram §1.4 exception: the mirror and its viewer ship only in
          // opted-in self-builds; with the flag off there is no entry point.
          if (allowTelegramTosViolations)
            SettingsSection(
              titleKey: AppStringKeys.historyTitle,
              rows: [
                SettingsRow(
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
        ],
      ),
    );
  }
}
