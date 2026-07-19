import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'data_storage_service.dart';

class NetworkUsageView extends StatefulWidget {
  const NetworkUsageView({super.key});

  @override
  State<NetworkUsageView> createState() => _NetworkUsageViewState();
}

class _NetworkUsageViewState extends State<NetworkUsageView> {
  final _service = const DataStorageService();
  List<Map<String, dynamic>> _entries = const [];
  int _sinceDate = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.networkStatistics();
      if (!mounted) return;
      setState(() {
        _entries = result.objects('entries') ?? const [];
        _sinceDate = result.integer('since_date') ?? 0;
      });
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.networkUsageResetNetworkStatistics),
      message:
          'Sent, received and call-duration counters will restart at zero.',
      confirmText: AppStrings.t(AppStringKeys.networkUsageReset),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _service.resetNetworkStatistics();
      await _load();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Map<String, (int, int, double)> get _byNetwork {
    final totals = <String, (int, int, double)>{};
    for (final entry in _entries) {
      final network = entry.obj('network_type')?.type ?? 'networkTypeOther';
      final current = totals[network] ?? (0, 0, 0);
      totals[network] = (
        current.$1 + (entry.int64('sent_bytes') ?? 0),
        current.$2 + (entry.int64('received_bytes') ?? 0),
        current.$3 + (entry.dbl('duration') ?? 0),
      );
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final totals = _byNetwork;
    final sent = totals.values.fold<int>(0, (sum, value) => sum + value.$1);
    final received = totals.values.fold<int>(0, (sum, value) => sum + value.$2);
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.networkUsageNetworkUsage),
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loading ? null : _reset,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  AppStrings.t(AppStringKeys.networkUsageReset),
                  style: TextStyle(
                    color: _loading ? c.textTertiary : AppTheme.brand,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            _metric(HeroAppIcons.arrowUp, 'Sent', _bytes(sent)),
                            Container(width: 1, height: 48, color: c.divider),
                            _metric(
                              HeroAppIcons.arrowDown,
                              'Received',
                              _bytes(received),
                            ),
                          ],
                        ),
                      ),
                      if (_sinceDate > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.t(AppStringKeys.networkUsageSinceValue1, {
                            'value1': DateText.messageDetailLabel(_sinceDate),
                          }),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: c.textTertiary),
                        ),
                      ],
                      const SizedBox(height: 18),
                      for (final network in totals.entries) ...[
                        Text(
                          _networkName(network.key),
                          style: TextStyle(fontSize: 13, color: c.textTertiary),
                        ),
                        const SizedBox(height: 6),
                        _networkCard(network.key, network.value),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        AppStrings.t(AppStringKeys.networkUsageByMediaType),
                        style: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
                      const SizedBox(height: 6),
                      _typeCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metric(AppIconData icon, String label, String value) {
    final c = context.colors;
    return Expanded(
      child: Column(
        children: [
          AppIcon(icon, size: 20, color: AppTheme.brand),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: c.textSecondary)),
        ],
      ),
    );
  }

  Widget _networkCard(String type, (int, int, double) value) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SettingsRow(
            title: AppStrings.t(AppStringKeys.messageInfoSent),
            value: _bytes(value.$1),
            showChevron: false,
          ),
          const Divider(height: 1),
          SettingsRow(
            title: AppStrings.t(AppStringKeys.networkUsageReceived),
            value: _bytes(value.$2),
            showChevron: false,
          ),
          if (value.$3 > 0) ...[
            const Divider(height: 1),
            SettingsRow(
              title: AppStrings.t(AppStringKeys.networkUsageCallDuration),
              value: _duration(value.$3.round()),
              showChevron: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeCard() {
    final c = context.colors;
    final totals = <String, (int, int)>{};
    for (final entry in _entries) {
      final type = entry.type == 'networkStatisticsEntryCall'
          ? 'Calls'
          : _fileType(entry.obj('file_type')?.type);
      final old = totals[type] ?? (0, 0);
      totals[type] = (
        old.$1 + (entry.int64('sent_bytes') ?? 0),
        old.$2 + (entry.int64('received_bytes') ?? 0),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: totals.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                AppStrings.t(AppStringKeys.networkUsageNoNetworkUsageRecorded),
                style: TextStyle(color: c.textSecondary),
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < totals.length; index++) ...[
                  SettingsRow(
                    title:
                        '${totals.keys.elementAt(index)} · ↑ ${_bytes(totals.values.elementAt(index).$1)}',
                    value: '↓ ${_bytes(totals.values.elementAt(index).$2)}',
                    showChevron: false,
                  ),
                  if (index != totals.length - 1) const Divider(height: 1),
                ],
              ],
            ),
    );
  }

  static String _networkName(String type) => switch (type) {
    'networkTypeWiFi' => 'Wi-Fi',
    'networkTypeMobile' => 'Mobile data',
    'networkTypeMobileRoaming' => 'Roaming',
    'networkTypeNone' => 'Offline',
    _ => 'Other network',
  };

  static String _fileType(String? type) => switch (type) {
    'fileTypePhoto' => 'Photos',
    'fileTypeVideo' => 'Videos',
    'fileTypeVoiceNote' => 'Voice messages',
    'fileTypeVideoNote' => 'Video messages',
    'fileTypeAudio' => 'Music',
    'fileTypeDocument' => 'Files',
    'fileTypeAnimation' => 'GIFs',
    'fileTypeStory' => 'Stories',
    _ => 'Other',
  };

  static String _duration(int seconds) =>
      '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';

  static String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }
}
