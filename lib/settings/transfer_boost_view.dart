import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
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
    required Color iconColor,
    required ValueChanged<int> onSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: values.length,
              separatorBuilder: (_, _) => const InsetDivider(leadingInset: 56),
              itemBuilder: (context, index) {
                final value = values[index];
                final selected = selectedValue == value;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (!selected) onSelected(value);
                  },
                  child: SizedBox(
                    height: AppMetric.settingsRowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          SettingsIconTile(
                            icon: icon,
                            backgroundColor: iconColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              labelFor(value),
                              style: TextStyle(
                                fontSize: AppTextSize.body,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          if (selected)
                            AppIcon(
                              HeroAppIcons.check,
                              size: 18,
                              color: AppTheme.brand,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String key) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(
        key.l10n(context),
        style: TextStyle(fontSize: AppTextSize.caption, color: c.textTertiary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.transferBoostTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.section,
                    ),
                    children: [
                      _sectionLabel(
                        context,
                        AppStringKeys.transferBoostDownloadSection,
                      ),
                      SettingsCard(
                        children: [
                          SettingsSwitchRow(
                            title: AppStringKeys.transferBoostDownload,
                            value: _config.downloadEnabled,
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.download,
                              backgroundColor: Color(0xFF34A2DF),
                            ),
                            onChanged: (value) => unawaited(
                              _save(_config.copyWith(downloadEnabled: value)),
                            ),
                          ),
                          if (_config.downloadEnabled) ...[
                            const InsetDivider(leadingInset: 48),
                            SettingsRow(
                              title: AppStringKeys.transferBoostChunkSize,
                              value: _formatChunkSize(
                                _config.downloadChunkSizeBytes,
                              ),
                              leading: const SettingsIconTile(
                                icon: HeroAppIcons.compactDisc,
                                backgroundColor: Color(0xFFAF52DE),
                              ),
                              onTap: () => _showValuePicker(
                                values:
                                    TransferBoostConfig.downloadChunkSizesBytes,
                                selectedValue: _config.downloadChunkSizeBytes,
                                labelFor: _formatChunkSize,
                                icon: HeroAppIcons.compactDisc,
                                iconColor: const Color(0xFFAF52DE),
                                onSelected: (value) => unawaited(
                                  _save(
                                    _config.copyWith(
                                      downloadChunkSizeBytes: value,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const InsetDivider(leadingInset: 48),
                            SettingsRow(
                              title: AppStringKeys.transferBoostParallelism,
                              value: '${_config.downloadParallelism}',
                              leading: const SettingsIconTile(
                                icon: HeroAppIcons.networkWired,
                                backgroundColor: Color(0xFFFF9500),
                              ),
                              onTap: () => _showValuePicker(
                                values: List<int>.generate(
                                  TransferBoostConfig.maxParallelism,
                                  (index) => index + 1,
                                ),
                                selectedValue: _config.downloadParallelism,
                                labelFor: (value) => '$value',
                                icon: HeroAppIcons.networkWired,
                                iconColor: const Color(0xFFFF9500),
                                onSelected: (value) => unawaited(
                                  _save(
                                    _config.copyWith(
                                      downloadParallelism: value,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _sectionLabel(
                        context,
                        AppStringKeys.transferBoostUploadSection,
                      ),
                      SettingsCard(
                        children: [
                          SettingsSwitchRow(
                            title: AppStringKeys.transferBoostUpload,
                            value: _config.uploadEnabled,
                            leading: const SettingsIconTile(
                              icon: HeroAppIcons.upload,
                              backgroundColor: Color(0xFF34C759),
                            ),
                            onChanged: (value) => unawaited(
                              _save(_config.copyWith(uploadEnabled: value)),
                            ),
                          ),
                          if (_config.uploadEnabled) ...[
                            const InsetDivider(leadingInset: 48),
                            SettingsRow(
                              title: AppStringKeys.transferBoostChunkSize,
                              value: _formatChunkSize(
                                _config.uploadChunkSizeBytes,
                              ),
                              leading: const SettingsIconTile(
                                icon: HeroAppIcons.compactDisc,
                                backgroundColor: Color(0xFFAF52DE),
                              ),
                              onTap: () => _showValuePicker(
                                values:
                                    TransferBoostConfig.uploadChunkSizesBytes,
                                selectedValue: _config.uploadChunkSizeBytes,
                                labelFor: _formatChunkSize,
                                icon: HeroAppIcons.compactDisc,
                                iconColor: const Color(0xFFAF52DE),
                                onSelected: (value) => unawaited(
                                  _save(
                                    _config.copyWith(
                                      uploadChunkSizeBytes: value,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const InsetDivider(leadingInset: 48),
                            SettingsRow(
                              title: AppStringKeys.transferBoostParallelism,
                              value: '${_config.uploadParallelism}',
                              leading: const SettingsIconTile(
                                icon: HeroAppIcons.networkWired,
                                backgroundColor: Color(0xFFFF9500),
                              ),
                              onTap: () => _showValuePicker(
                                values: List<int>.generate(
                                  TransferBoostConfig.maxParallelism,
                                  (index) => index + 1,
                                ),
                                selectedValue: _config.uploadParallelism,
                                labelFor: (value) => '$value',
                                icon: HeroAppIcons.networkWired,
                                iconColor: const Color(0xFFFF9500),
                                onSelected: (value) => unawaited(
                                  _save(
                                    _config.copyWith(uploadParallelism: value),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          AppStringKeys.transferBoostDescription.l10n(context),
                          style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: c.textTertiary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
