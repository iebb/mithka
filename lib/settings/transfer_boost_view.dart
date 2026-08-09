import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
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

  void _showValuePicker({
    required List<int> values,
    required int selectedValue,
    required String Function(int value) labelFor,
    required AppIconData icon,
    required ValueChanged<int> onSelected,
  }) {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: SettingsCard.rows(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            rows: [
              for (final value in values)
                Builder(
                  builder: (context) {
                    final selected = selectedValue == value;
                    return SettingsRow(
                      title: labelFor(value),
                      leading: SettingsLeadingIcon(icon: icon),
                      showChevron: false,
                      trailing: selected
                          ? const AppIcon(HeroAppIcons.check, size: 18)
                          : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        if (!selected) onSelected(value);
                      },
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

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
                      SettingsRow(
                        title: AppStringKeys.transferBoostChunkSize,
                        value: _formatChunkSize(_config.downloadChunkSizeBytes),
                        leading: const SettingsLeadingIcon(
                          icon: HeroAppIcons.compactDisc,
                        ),
                        onTap: () => _showValuePicker(
                          values: TransferBoostConfig.downloadChunkSizesBytes,
                          selectedValue: _config.downloadChunkSizeBytes,
                          labelFor: _formatChunkSize,
                          icon: HeroAppIcons.compactDisc,
                          onSelected: (value) => unawaited(
                            _save(
                              _config.copyWith(downloadChunkSizeBytes: value),
                            ),
                          ),
                        ),
                      ),
                      SettingsRow(
                        title: AppStringKeys.transferBoostParallelism,
                        value: '${_config.downloadParallelism}',
                        leading: const SettingsLeadingIcon(
                          icon: HeroAppIcons.networkWired,
                        ),
                        onTap: () => _showValuePicker(
                          values: List<int>.generate(
                            TransferBoostConfig.maxParallelism,
                            (index) => index + 1,
                          ),
                          selectedValue: _config.downloadParallelism,
                          labelFor: (value) => '$value',
                          icon: HeroAppIcons.networkWired,
                          onSelected: (value) => unawaited(
                            _save(_config.copyWith(downloadParallelism: value)),
                          ),
                        ),
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
                      SettingsRow(
                        title: AppStringKeys.transferBoostChunkSize,
                        value: _formatChunkSize(_config.uploadChunkSizeBytes),
                        leading: const SettingsLeadingIcon(
                          icon: HeroAppIcons.compactDisc,
                        ),
                        onTap: () => _showValuePicker(
                          values: TransferBoostConfig.uploadChunkSizesBytes,
                          selectedValue: _config.uploadChunkSizeBytes,
                          labelFor: _formatChunkSize,
                          icon: HeroAppIcons.compactDisc,
                          onSelected: (value) => unawaited(
                            _save(
                              _config.copyWith(uploadChunkSizeBytes: value),
                            ),
                          ),
                        ),
                      ),
                      SettingsRow(
                        title: AppStringKeys.transferBoostParallelism,
                        value: '${_config.uploadParallelism}',
                        leading: const SettingsLeadingIcon(
                          icon: HeroAppIcons.networkWired,
                        ),
                        onTap: () => _showValuePicker(
                          values: List<int>.generate(
                            TransferBoostConfig.maxParallelism,
                            (index) => index + 1,
                          ),
                          selectedValue: _config.uploadParallelism,
                          labelFor: (value) => '$value',
                          icon: HeroAppIcons.networkWired,
                          onSelected: (value) => unawaited(
                            _save(_config.copyWith(uploadParallelism: value)),
                          ),
                        ),
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
