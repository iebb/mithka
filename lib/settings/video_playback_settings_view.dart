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
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.videoPlaybackSettingsTitle,
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
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                    children: [
                      _sectionHeader(
                        AppStringKeys.videoPlaybackHorizontalSwipe,
                      ),
                      _choiceCard<VideoHorizontalSwipeAction>(
                        values: VideoHorizontalSwipeAction.values,
                        selected: _preferences.horizontalSwipeAction,
                        label: _swipeLabel,
                        onSelected: _setSwipeAction,
                      ),
                      const SizedBox(height: 18),
                      _sectionHeader(
                        AppStringKeys.videoPlaybackLeftVerticalSwipe,
                      ),
                      _choiceCard<VideoVerticalSwipeAction>(
                        values: VideoVerticalSwipeAction.values,
                        selected: _preferences.leftVerticalSwipeAction,
                        label: _verticalSwipeLabel,
                        onSelected: _setLeftVerticalSwipeAction,
                      ),
                      const SizedBox(height: 18),
                      _sectionHeader(
                        AppStringKeys.videoPlaybackRightVerticalSwipe,
                      ),
                      _choiceCard<VideoVerticalSwipeAction>(
                        values: VideoVerticalSwipeAction.values,
                        selected: _preferences.rightVerticalSwipeAction,
                        label: _verticalSwipeLabel,
                        onSelected: _setRightVerticalSwipeAction,
                      ),
                      const SizedBox(height: 18),
                      _sectionHeader(AppStringKeys.videoPlaybackWhenFinished),
                      _choiceCard<VideoCompletionAction>(
                        values: VideoCompletionAction.values,
                        selected: _preferences.completionAction,
                        label: _completionLabel,
                        onSelected: _setCompletionAction,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(left: 16, bottom: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.l10n(context),
        style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
      ),
    ),
  );

  Widget _choiceCard<T>({
    required List<T> values,
    required T selected,
    required String Function(T value) label,
    required ValueChanged<T> onSelected,
  }) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < values.length; index++) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(values[index]),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label(values[index]).l10n(context),
                          style: TextStyle(fontSize: 16, color: c.textPrimary),
                        ),
                      ),
                      if (values[index] == selected)
                        AppIcon(
                          HeroAppIcons.check,
                          size: 18,
                          color: AppTheme.brand,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (index + 1 < values.length) const InsetDivider(leadingInset: 16),
          ],
        ],
      ),
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
