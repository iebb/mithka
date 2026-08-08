import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../theme/app_motion.dart';
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
    final c = context.colors;
    final profile = _profile;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(
              AppStringKeys.autoDownloadSettingsAutomaticMediaDownload,
            ),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _networkSelector(),
                const SizedBox(height: 14),
                _card([
                  SettingsRow(
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
                ]),
                const SizedBox(height: 14),
                Text(
                  AppStrings.t(
                    AppStringKeys.autoDownloadSettingsFileSizeLimits,
                  ),
                  style: TextStyle(fontSize: 13, color: c.textTertiary),
                ),
                const SizedBox(height: 6),
                _card([
                  _sizeRow(
                    HeroAppIcons.image,
                    AppStrings.t(AppStringKeys.autoDownloadSettingsPhotos),
                    profile.maxPhotoBytes,
                    (value) => _save(profile.copyWith(maxPhotoBytes: value)),
                  ),
                  const Divider(height: 1),
                  _sizeRow(
                    HeroAppIcons.video,
                    AppStrings.t(AppStringKeys.autoDownloadSettingsVideos),
                    profile.maxVideoBytes,
                    (value) => _save(profile.copyWith(maxVideoBytes: value)),
                  ),
                  const Divider(height: 1),
                  _sizeRow(
                    HeroAppIcons.solidFolder,
                    AppStrings.t(
                      AppStringKeys.autoDownloadSettingsFilesAndMusic,
                    ),
                    profile.maxOtherBytes,
                    (value) => _save(profile.copyWith(maxOtherBytes: value)),
                  ),
                ]),
                const SizedBox(height: 14),
                Text(
                  AppStrings.t(
                    AppStringKeys.autoDownloadSettingsPreloadingAndCalls,
                  ),
                  style: TextStyle(fontSize: 13, color: c.textTertiary),
                ),
                const SizedBox(height: 6),
                _card([
                  _toggle(
                    AppStrings.t(
                      AppStringKeys.autoDownloadSettingsPreloadLargeVideos,
                    ),
                    profile.preloadLargeVideos,
                    (value) =>
                        _save(profile.copyWith(preloadLargeVideos: value)),
                  ),
                  const Divider(height: 1),
                  _toggle(
                    AppStrings.t(
                      AppStringKeys.autoDownloadSettingsPreloadNextAudio,
                    ),
                    profile.preloadNextAudio,
                    (value) => _save(profile.copyWith(preloadNextAudio: value)),
                  ),
                  const Divider(height: 1),
                  _toggle(
                    AppStrings.t(
                      AppStringKeys.autoDownloadSettingsPreloadStories,
                    ),
                    profile.preloadStories,
                    (value) => _save(profile.copyWith(preloadStories: value)),
                  ),
                  const Divider(height: 1),
                  _toggle(
                    AppStrings.t(
                      AppStringKeys.autoDownloadSettingsUseLessDataForCalls,
                    ),
                    profile.useLessDataForCalls,
                    (value) =>
                        _save(profile.copyWith(useLessDataForCalls: value)),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(
                  AppStrings.t(
                    AppStringKeys
                        .autoDownloadSettingsTheseSettingsAreAppliedDirectlyToTDLibFor,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkSelector() {
    final c = context.colors;
    return SettingsPanel(
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

  Widget _card(List<Widget> children) {
    return SettingsCard(children: children);
  }

  Widget _sizeRow(
    AppIconData icon,
    String title,
    int value,
    Future<void> Function(int value) onChanged,
  ) {
    final selected = _sizes.contains(value) ? value : _closestSize(value);
    return SettingsRow(
      leading: AppIcon(icon, size: 21, color: AppTheme.brand),
      title: title,
      value: _sizeLabel(selected),
      onTap: _controller.isApplying
          ? null
          : () => unawaited(_chooseSize(selected, onChanged)),
    );
  }

  Future<void> _chooseSize(
    int selected,
    Future<void> Function(int value) onChanged,
  ) async {
    final value = await showAppModalSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          top: false,
          child: SettingsCard(
            margin: const EdgeInsets.all(10),
            children: [
              for (var index = 0; index < _sizes.length; index++) ...[
                if (index > 0) Divider(height: 1, color: c.divider),
                SettingsRow(
                  title: _sizeLabel(_sizes[index]),
                  showChevron: false,
                  trailing: _sizes[index] == selected
                      ? const AppIcon(HeroAppIcons.check, size: 20)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(_sizes[index]),
                ),
              ],
            ],
          ),
        );
      },
    );
    if (value != null && mounted) await onChanged(value);
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
