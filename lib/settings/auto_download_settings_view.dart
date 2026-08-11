import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/settings_selection_row.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../platform/adaptive_platform.dart';
import '../theme/app_theme.dart';
import 'auto_download_media_controller.dart';

class AutoDownloadSettingsView extends StatefulWidget {
  const AutoDownloadSettingsView({super.key});

  @override
  State<AutoDownloadSettingsView> createState() =>
      _AutoDownloadSettingsViewState();
}

class _AutoDownloadSettingsViewState extends State<AutoDownloadSettingsView> {
  static const _sizes = <int>[
    0,
    1048576,
    5242880,
    20971520,
    104857600,
    524288000,
    2147483647,
  ];

  // Byte units are written the same way in every locale; only "Never" is copy.
  static String _sizeLabel(int bytes) => switch (bytes) {
    0 => AppStrings.t(AppStringKeys.autoDownloadSettingsSizeNever),
    1048576 => '1 MB',
    5242880 => '5 MB',
    20971520 => '20 MB',
    104857600 => '100 MB',
    524288000 => '500 MB',
    _ => '2 GB',
  };
  final _controller = AutoDownloadMediaController.shared;
  String _network = 'networkTypeMobile';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (isDesktopTargetPlatform(Theme.of(context).platform)) {
      _network = 'networkTypeWiFi';
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  AutoDownloadProfile get _profile => switch (_network) {
    'networkTypeWiFi' => _controller.wifi,
    'networkTypeMobileRoaming' => _controller.roaming,
    _ => _controller.mobile,
  };

  Future<void> _save(AutoDownloadProfile profile) async {
    try {
      await _controller.setProfile(_network, profile);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    return SettingsPageScaffold(
      title: AppStrings.t(
        AppStringKeys.autoDownloadSettingsAutomaticMediaDownload,
      ),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          if (!desktop) ...[
            _networkSelector(),
            const SizedBox(height: AppSpacing.lg),
          ],
          SettingsCard.rows(
            rows: [
              SettingsRow(
                key: ValueKey('auto-download-profile-$_network'),
                title: AppStrings.t(
                  AppStringKeys.autoDownloadSettingsAutomaticDownload,
                ),
                value: _networkLabel(_network),
                showChevron: false,
                onTap: _controller.isApplying
                    ? null
                    : () => unawaited(
                        _save(profile.copyWith(enabled: !profile.enabled)),
                      ),
                trailing: AppSwitch(
                  value: profile.enabled,
                  enabled: !_controller.isApplying,
                  onChanged: (value) =>
                      unawaited(_save(profile.copyWith(enabled: value))),
                ),
              ),
            ],
          ),
          SettingsSection(
            titleKey: AppStringKeys.autoDownloadSettingsFileSizeLimits,
            rows: [
              _sizeRow(
                HeroAppIcons.image,
                AppStrings.t(AppStringKeys.autoDownloadSettingsPhotos),
                profile.maxPhotoBytes,
                (value) => _save(profile.copyWith(maxPhotoBytes: value)),
              ),
              _sizeRow(
                HeroAppIcons.video,
                AppStrings.t(AppStringKeys.autoDownloadSettingsVideos),
                profile.maxVideoBytes,
                (value) => _save(profile.copyWith(maxVideoBytes: value)),
              ),
              _sizeRow(
                HeroAppIcons.solidFolder,
                AppStrings.t(AppStringKeys.autoDownloadSettingsFilesAndMusic),
                profile.maxOtherBytes,
                (value) => _save(profile.copyWith(maxOtherBytes: value)),
              ),
            ],
          ),
          SettingsSection(
            titleKey: AppStringKeys.autoDownloadSettingsPreloadingAndCalls,
            rows: [
              _toggle(
                AppStrings.t(
                  AppStringKeys.autoDownloadSettingsPreloadLargeVideos,
                ),
                profile.preloadLargeVideos,
                (value) => _save(profile.copyWith(preloadLargeVideos: value)),
              ),
              _toggle(
                AppStrings.t(
                  AppStringKeys.autoDownloadSettingsPreloadNextAudio,
                ),
                profile.preloadNextAudio,
                (value) => _save(profile.copyWith(preloadNextAudio: value)),
              ),
              _toggle(
                AppStrings.t(AppStringKeys.autoDownloadSettingsPreloadStories),
                profile.preloadStories,
                (value) => _save(profile.copyWith(preloadStories: value)),
              ),
              _toggle(
                AppStrings.t(
                  AppStringKeys.autoDownloadSettingsUseLessDataForCalls,
                ),
                profile.useLessDataForCalls,
                (value) => _save(profile.copyWith(useLessDataForCalls: value)),
              ),
            ],
          ),
          SettingsNote(
            text: AppStrings.t(
              AppStringKeys
                  .autoDownloadSettingsTheseSettingsAreAppliedDirectlyToTDLibFor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkSelector() {
    final c = context.colors;
    return SettingsPanel(
      key: const ValueKey('auto-download-network-selector'),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final entry in const {
            'networkTypeMobile':
                AppStringKeys.autoDownloadSettingsNetworkMobile,
            'networkTypeWiFi': AppStringKeys.autoDownloadSettingsNetworkWiFi,
            'networkTypeMobileRoaming':
                AppStringKeys.autoDownloadSettingsNetworkRoaming,
          }.entries)
            Expanded(
              child: GestureDetector(
                key: ValueKey('auto-download-network-${entry.key}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _network = entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _network == entry.key
                        ? AppTheme.brand.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    AppStrings.t(entry.value),
                    style: TextStyle(
                      color: _network == entry.key
                          ? AppTheme.brand
                          : c.textSecondary,
                      fontWeight: _network == entry.key
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sizeRow(
    AppIconData icon,
    String title,
    int value,
    Future<void> Function(int value) onChanged,
  ) {
    final selected = _sizes.contains(value) ? value : _closestSize(value);
    return SettingsSelectionRow<int>(
      leading: SettingsLeadingIcon(icon: icon),
      title: title,
      value: _sizeLabel(selected),
      enabled: !_controller.isApplying,
      options: [
        for (final size in _sizes)
          SettingsSelectionOption(
            id: 'auto-download-size-$size',
            value: size,
            label: _sizeLabel(size),
            icon: icon,
          ),
      ],
      isSelected: (size) => size == selected,
      onSelected: onChanged,
    );
  }

  Widget _toggle(
    String title,
    bool value,
    Future<void> Function(bool) update,
  ) => SettingsSwitchRow(
    title: title,
    value: value,
    onChanged: (next) {
      if (!_controller.isApplying) unawaited(update(next));
    },
  );

  int _closestSize(int value) {
    var closest = _sizes.first;
    var distance = (value - closest).abs();
    for (final candidate in _sizes.skip(1)) {
      final next = (value - candidate).abs();
      if (next < distance) {
        closest = candidate;
        distance = next;
      }
    }
    return closest;
  }

  static String _networkLabel(String type) => switch (type) {
    'networkTypeWiFi' => AppStrings.t(
      AppStringKeys.autoDownloadSettingsWhenConnectedToWiFi,
    ),
    'networkTypeMobileRoaming' => AppStrings.t(
      AppStringKeys.autoDownloadSettingsWhileRoaming,
    ),
    _ => AppStrings.t(AppStringKeys.autoDownloadSettingsWhenUsingMobileData),
  };
}
