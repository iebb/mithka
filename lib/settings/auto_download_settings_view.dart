import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'auto_download_media_controller.dart';

class AutoDownloadSettingsView extends StatefulWidget {
  const AutoDownloadSettingsView({super.key});

  @override
  State<AutoDownloadSettingsView> createState() =>
      _AutoDownloadSettingsViewState();
}

class _AutoDownloadSettingsViewState extends State<AutoDownloadSettingsView> {
  static const _sizes = <int, String>{
    0: 'Never',
    1048576: '1 MB',
    5242880: '5 MB',
    20971520: '20 MB',
    104857600: '100 MB',
    524288000: '500 MB',
    2147483647: '2 GB',
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
                    'Photos',
                    profile.maxPhotoBytes,
                    (value) => _save(profile.copyWith(maxPhotoBytes: value)),
                  ),
                  const Divider(height: 1),
                  _sizeRow(
                    HeroAppIcons.video,
                    'Videos',
                    profile.maxVideoBytes,
                    (value) => _save(profile.copyWith(maxVideoBytes: value)),
                  ),
                  const Divider(height: 1),
                  _sizeRow(
                    HeroAppIcons.solidFolder,
                    'Files and music',
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
                    'Preload large videos for streaming',
                    profile.preloadLargeVideos,
                    (value) =>
                        _save(profile.copyWith(preloadLargeVideos: value)),
                  ),
                  const Divider(height: 1),
                  _toggle(
                    'Preload the next audio track',
                    profile.preloadNextAudio,
                    (value) => _save(profile.copyWith(preloadNextAudio: value)),
                  ),
                  const Divider(height: 1),
                  _toggle(
                    'Preload stories',
                    profile.preloadStories,
                    (value) => _save(profile.copyWith(preloadStories: value)),
                  ),
                  const Divider(height: 1),
                  _toggle(
                    'Use less data for calls',
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final entry in const {
            'networkTypeMobile': 'Mobile',
            'networkTypeWiFi': 'Wi-Fi',
            'networkTypeMobileRoaming': 'Roaming',
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
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    entry.value,
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
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _sizeRow(
    AppIconData icon,
    String title,
    int value,
    Future<void> Function(int value) onChanged,
  ) {
    final selected = _sizes.containsKey(value) ? value : _closestSize(value);
    return SettingsRow(
      leading: AppIcon(icon, size: 21, color: AppTheme.brand),
      title: title,
      value: _sizes[selected] ?? '',
      onTap: _controller.isApplying
          ? null
          : () => unawaited(_chooseSize(selected, onChanged)),
    );
  }

  Future<void> _chooseSize(
    int selected,
    Future<void> Function(int value) onChanged,
  ) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < _sizes.length; index++) ...[
                  if (index > 0) Divider(height: 1, color: c.divider),
                  SettingsRow(
                    title: _sizes.values.elementAt(index),
                    showChevron: false,
                    trailing: _sizes.keys.elementAt(index) == selected
                        ? const AppIcon(HeroAppIcons.check, size: 20)
                        : null,
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_sizes.keys.elementAt(index)),
                  ),
                ],
              ],
            ),
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
    var closest = _sizes.keys.first;
    var distance = (value - closest).abs();
    for (final candidate in _sizes.keys.skip(1)) {
      final next = (value - candidate).abs();
      if (next < distance) {
        closest = candidate;
        distance = next;
      }
    }
    return closest;
  }

  static String _networkLabel(String type) => switch (type) {
    'networkTypeWiFi' => 'When connected to Wi-Fi',
    'networkTypeMobileRoaming' => 'While roaming',
    _ => 'When using mobile data',
  };
}
