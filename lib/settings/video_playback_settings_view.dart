import 'package:flutter/material.dart';

import '../chat/video_playback_preferences.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class VideoPlaybackSettingsView extends StatefulWidget {
  const VideoPlaybackSettingsView({super.key});

  @override
  State<VideoPlaybackSettingsView> createState() =>
      _VideoPlaybackSettingsViewState();
}

class _VideoPlaybackSettingsViewState extends State<VideoPlaybackSettingsView> {
  VideoPlaybackPreferences _preferences = const VideoPlaybackPreferences();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await VideoPlaybackPreferences.load();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _loading = false;
    });
  }

  Future<void> _setSwipeAction(VideoHorizontalSwipeAction action) async {
    setState(
      () => _preferences = _preferences.copyWith(horizontalSwipeAction: action),
    );
    await VideoPlaybackPreferences.saveHorizontalSwipeAction(action);
  }

  Future<void> _setLeftVerticalSwipeAction(
    VideoVerticalSwipeAction action,
  ) async {
    setState(
      () =>
          _preferences = _preferences.copyWith(leftVerticalSwipeAction: action),
    );
    await VideoPlaybackPreferences.saveLeftVerticalSwipeAction(action);
  }

  Future<void> _setRightVerticalSwipeAction(
    VideoVerticalSwipeAction action,
  ) async {
    setState(
      () => _preferences = _preferences.copyWith(
        rightVerticalSwipeAction: action,
      ),
    );
    await VideoPlaybackPreferences.saveRightVerticalSwipeAction(action);
  }

  Future<void> _setCompletionAction(VideoCompletionAction action) async {
    setState(
      () => _preferences = _preferences.copyWith(completionAction: action),
    );
    await VideoPlaybackPreferences.saveCompletionAction(action);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStringKeys.videoPlaybackSettingsTitle,
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : SettingsListView(
              children: [
                const SettingsSectionHeader(
                  AppStringKeys.videoPlaybackHorizontalSwipe,
                ),
                _choiceCard<VideoHorizontalSwipeAction>(
                  values: VideoHorizontalSwipeAction.values,
                  selected: _preferences.horizontalSwipeAction,
                  label: _swipeLabel,
                  onSelected: _setSwipeAction,
                ),
                const SettingsSectionHeader(
                  AppStringKeys.videoPlaybackLeftVerticalSwipe,
                ),
                _choiceCard<VideoVerticalSwipeAction>(
                  values: VideoVerticalSwipeAction.values,
                  selected: _preferences.leftVerticalSwipeAction,
                  label: _verticalSwipeLabel,
                  onSelected: _setLeftVerticalSwipeAction,
                ),
                const SettingsSectionHeader(
                  AppStringKeys.videoPlaybackRightVerticalSwipe,
                ),
                _choiceCard<VideoVerticalSwipeAction>(
                  values: VideoVerticalSwipeAction.values,
                  selected: _preferences.rightVerticalSwipeAction,
                  label: _verticalSwipeLabel,
                  onSelected: _setRightVerticalSwipeAction,
                ),
                const SettingsSectionHeader(
                  AppStringKeys.videoPlaybackWhenFinished,
                ),
                _choiceCard<VideoCompletionAction>(
                  values: VideoCompletionAction.values,
                  selected: _preferences.completionAction,
                  label: _completionLabel,
                  onSelected: _setCompletionAction,
                ),
              ],
            ),
    );
  }

  Widget _choiceCard<T>({
    required List<T> values,
    required T selected,
    required String Function(T value) label,
    required ValueChanged<T> onSelected,
  }) {
    return SettingsCard.rows(
      dividerInset: AppMetric.settingsTextDividerInset,
      rows: [
        for (final value in values)
          SettingsRow(
            title: label(value),
            showChevron: false,
            onTap: () => onSelected(value),
            trailing: value == selected
                ? const AppIcon(HeroAppIcons.check, size: 18)
                : null,
          ),
      ],
    );
  }

  String _swipeLabel(VideoHorizontalSwipeAction action) => switch (action) {
    VideoHorizontalSwipeAction.disabled =>
      AppStringKeys.videoPlaybackSwipeDisabled,
    VideoHorizontalSwipeAction.adjustProgress =>
      AppStringKeys.videoPlaybackSwipeAdjustProgress,
    VideoHorizontalSwipeAction.changeVideo =>
      AppStringKeys.videoPlaybackSwipeChangeVideo,
    VideoHorizontalSwipeAction.skipTenSeconds =>
      AppStringKeys.videoPlaybackSwipeSkipTenSeconds,
  };

  String _verticalSwipeLabel(VideoVerticalSwipeAction action) =>
      switch (action) {
        VideoVerticalSwipeAction.disabled =>
          AppStringKeys.videoPlaybackSwipeDisabled,
        VideoVerticalSwipeAction.brightness =>
          AppStringKeys.videoPlaybackSwipeAdjustBrightness,
        VideoVerticalSwipeAction.volume =>
          AppStringKeys.videoPlaybackSwipeAdjustVolume,
      };

  String _completionLabel(VideoCompletionAction action) => switch (action) {
    VideoCompletionAction.prompt => AppStringKeys.videoPlaybackFinishedAsk,
    VideoCompletionAction.autoplayNext =>
      AppStringKeys.videoPlaybackFinishedAutoplayNext,
    VideoCompletionAction.replay => AppStringKeys.videoPlaybackFinishedReplay,
    VideoCompletionAction.returnToChat =>
      AppStringKeys.videoPlaybackFinishedReturnToChat,
  };
}
