import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/settings_selection_row.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import 'transfer_boost_config.dart';

class TransferBoostView extends StatefulWidget {
  const TransferBoostView({super.key});

  @override
  State<TransferBoostView> createState() => _TransferBoostViewState();
}

class _TransferBoostViewState extends State<TransferBoostView> {
  TransferBoostConfig _config = const TransferBoostConfig();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await TransferBoostConfig.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  Future<void> _save(TransferBoostConfig config) async {
    setState(() => _config = config);
    await TransferBoostConfig.save(config);
    if (mounted) {
      showToast(context, AppStringKeys.transferBoostRestartRequired);
    }
  }

  String _formatChunkSize(int bytes) {
    if (bytes >= TransferBoostConfig.mebibyte) {
      return '${bytes ~/ TransferBoostConfig.mebibyte} MB';
    }
    return '${bytes ~/ TransferBoostConfig.kibibyte} KB';
  }

  Widget _valueSelector({
    required String title,
    required List<int> values,
    required int selectedValue,
    required String Function(int value) labelFor,
    required AppIconData icon,
    required FutureOr<void> Function(int value) onSelected,
  }) => SettingsSelectionRow<int>(
    title: title,
    value: labelFor(selectedValue),
    leading: SettingsLeadingIcon(icon: icon),
    options: [
      for (final value in values)
        SettingsSelectionOption(
          id: 'transfer-boost-value-$value',
          value: value,
          label: labelFor(value),
          icon: icon,
        ),
    ],
    isSelected: (value) => value == selectedValue,
    onSelected: onSelected,
  );

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStringKeys.transferBoostTitle,
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : SettingsListView(
              children: [
                SettingsSection(
                  titleKey: AppStringKeys.transferBoostDownloadSection,
                  rows: [
                    SettingsSwitchRow(
                      title: AppStringKeys.transferBoostDownload,
                      value: _config.downloadEnabled,
                      leading: const SettingsLeadingIcon(
                        icon: HeroAppIcons.download,
                      ),
                      onChanged: (value) => unawaited(
                        _save(_config.copyWith(downloadEnabled: value)),
                      ),
                    ),
                    if (_config.downloadEnabled) ...[
                      _valueSelector(
                        title: AppStringKeys.transferBoostChunkSize,
                        values: TransferBoostConfig.downloadChunkSizesBytes,
                        selectedValue: _config.downloadChunkSizeBytes,
                        labelFor: _formatChunkSize,
                        icon: HeroAppIcons.compactDisc,
                        onSelected: (value) => _save(
                          _config.copyWith(downloadChunkSizeBytes: value),
                        ),
                      ),
                      _valueSelector(
                        title: AppStringKeys.transferBoostParallelism,
                        values: List<int>.generate(
                          TransferBoostConfig.maxParallelism,
                          (index) => index + 1,
                        ),
                        selectedValue: _config.downloadParallelism,
                        labelFor: (value) => '$value',
                        icon: HeroAppIcons.networkWired,
                        onSelected: (value) =>
                            _save(_config.copyWith(downloadParallelism: value)),
                      ),
                    ],
                  ],
                ),
                SettingsSection(
                  titleKey: AppStringKeys.transferBoostUploadSection,
                  rows: [
                    SettingsSwitchRow(
                      title: AppStringKeys.transferBoostUpload,
                      value: _config.uploadEnabled,
                      leading: const SettingsLeadingIcon(
                        icon: HeroAppIcons.upload,
                      ),
                      onChanged: (value) => unawaited(
                        _save(_config.copyWith(uploadEnabled: value)),
                      ),
                    ),
                    if (_config.uploadEnabled) ...[
                      _valueSelector(
                        title: AppStringKeys.transferBoostChunkSize,
                        values: TransferBoostConfig.uploadChunkSizesBytes,
                        selectedValue: _config.uploadChunkSizeBytes,
                        labelFor: _formatChunkSize,
                        icon: HeroAppIcons.compactDisc,
                        onSelected: (value) => _save(
                          _config.copyWith(uploadChunkSizeBytes: value),
                        ),
                      ),
                      _valueSelector(
                        title: AppStringKeys.transferBoostParallelism,
                        values: List<int>.generate(
                          TransferBoostConfig.maxParallelism,
                          (index) => index + 1,
                        ),
                        selectedValue: _config.uploadParallelism,
                        labelFor: (value) => '$value',
                        icon: HeroAppIcons.networkWired,
                        onSelected: (value) =>
                            _save(_config.copyWith(uploadParallelism: value)),
                      ),
                    ],
                  ],
                ),
                const SettingsNote(
                  text: AppStringKeys.transferBoostDescription,
                ),
              ],
            ),
    );
  }
}
