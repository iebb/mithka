import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VideoHorizontalSwipeAction {
  disabled,
  adjustProgress,
  changeVideo,
  skipTenSeconds,
}

enum VideoVerticalSwipeAction { disabled, brightness, volume }

enum VideoCompletionAction { prompt, autoplayNext, replay, returnToChat }

class _VideoPlaybackPreferenceChanges extends ChangeNotifier {
  void emit() => notifyListeners();
}

class VideoPlaybackPreferences {
  const VideoPlaybackPreferences({
    this.horizontalSwipeAction = VideoHorizontalSwipeAction.changeVideo,
    this.leftVerticalSwipeAction = VideoVerticalSwipeAction.brightness,
    this.rightVerticalSwipeAction = VideoVerticalSwipeAction.volume,
    this.completionAction = VideoCompletionAction.prompt,
    this.androidVideoCompatibility = true,
    this.defaultPlaybackSpeed = 1.0,
    this.rememberedVolume = 1.0,
    this.rememberedMuted = false,
  });

  static const androidVideoCompatibilityPreferenceKey =
      'videoPlayback.androidVideoCompatibility';

  static const horizontalSwipePreferenceKey =
      'videoPlayback.horizontalSwipeAction';
  static const leftVerticalSwipePreferenceKey =
      'videoPlayback.leftVerticalSwipeAction';
  static const rightVerticalSwipePreferenceKey =
      'videoPlayback.rightVerticalSwipeAction';
  static const completionPreferenceKey = 'videoPlayback.completionAction';
  static const defaultPlaybackSpeedPreferenceKey =
      'videoPlayback.defaultPlaybackSpeed';
  static const rememberedVolumePreferenceKey = 'videoPlayback.rememberedVolume';
  static const rememberedMutedPreferenceKey = 'videoPlayback.rememberedMuted';

  /// Emits after a playback preference has been durably written.
  ///
  /// Detached desktop Settings runs in a separate Flutter engine, so its
  /// preference writes need an observable source that can trigger the
  /// existing settings-changed IPC back to the primary engine.
  static final _VideoPlaybackPreferenceChanges _changes =
      _VideoPlaybackPreferenceChanges();
  static ChangeNotifier get changes => _changes;

  final VideoHorizontalSwipeAction horizontalSwipeAction;
  final VideoVerticalSwipeAction leftVerticalSwipeAction;
  final VideoVerticalSwipeAction rightVerticalSwipeAction;
  final VideoCompletionAction completionAction;
  final bool androidVideoCompatibility;
  final double defaultPlaybackSpeed;
  final double rememberedVolume;
  final bool rememberedMuted;

  VideoPlaybackPreferences copyWith({
    VideoHorizontalSwipeAction? horizontalSwipeAction,
    VideoVerticalSwipeAction? leftVerticalSwipeAction,
    VideoVerticalSwipeAction? rightVerticalSwipeAction,
    VideoCompletionAction? completionAction,
    bool? androidVideoCompatibility,
    double? defaultPlaybackSpeed,
    double? rememberedVolume,
    bool? rememberedMuted,
  }) {
    return VideoPlaybackPreferences(
      horizontalSwipeAction:
          horizontalSwipeAction ?? this.horizontalSwipeAction,
      leftVerticalSwipeAction:
          leftVerticalSwipeAction ?? this.leftVerticalSwipeAction,
      rightVerticalSwipeAction:
          rightVerticalSwipeAction ?? this.rightVerticalSwipeAction,
      completionAction: completionAction ?? this.completionAction,
      androidVideoCompatibility:
          androidVideoCompatibility ?? this.androidVideoCompatibility,
      defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
      rememberedVolume: rememberedVolume ?? this.rememberedVolume,
      rememberedMuted: rememberedMuted ?? this.rememberedMuted,
    );
  }

  static Future<VideoPlaybackPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return fromPreferences(prefs);
  }

  static VideoPlaybackPreferences fromPreferences(SharedPreferences prefs) {
    final rawSpeed = prefs.getDouble(defaultPlaybackSpeedPreferenceKey) ?? 1.0;
    final rawVolume = prefs.getDouble(rememberedVolumePreferenceKey) ?? 1.0;
    return VideoPlaybackPreferences(
      androidVideoCompatibility:
          prefs.getBool(androidVideoCompatibilityPreferenceKey) ?? true,
      horizontalSwipeAction: _enumByName(
        VideoHorizontalSwipeAction.values,
        prefs.getString(horizontalSwipePreferenceKey),
        VideoHorizontalSwipeAction.changeVideo,
      ),
      leftVerticalSwipeAction: _enumByName(
        VideoVerticalSwipeAction.values,
        prefs.getString(leftVerticalSwipePreferenceKey),
        VideoVerticalSwipeAction.brightness,
      ),
      rightVerticalSwipeAction: _enumByName(
        VideoVerticalSwipeAction.values,
        prefs.getString(rightVerticalSwipePreferenceKey),
        VideoVerticalSwipeAction.volume,
      ),
      completionAction: _enumByName(
        VideoCompletionAction.values,
        prefs.getString(completionPreferenceKey),
        VideoCompletionAction.prompt,
      ),
      defaultPlaybackSpeed:
          rawSpeed.isFinite && rawSpeed >= 0.25 && rawSpeed <= 4.0
          ? rawSpeed
          : 1.0,
      rememberedVolume: rawVolume.isFinite
          ? rawVolume.clamp(0.0, 1.0).toDouble()
          : 1.0,
      rememberedMuted: prefs.getBool(rememberedMutedPreferenceKey) ?? false,
    );
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static Future<void> saveHorizontalSwipeAction(
    VideoHorizontalSwipeAction action,
  ) => _save(horizontalSwipePreferenceKey, action);

  static Future<void> saveLeftVerticalSwipeAction(
    VideoVerticalSwipeAction action,
  ) => _save(leftVerticalSwipePreferenceKey, action);

  static Future<void> saveRightVerticalSwipeAction(
    VideoVerticalSwipeAction action,
  ) => _save(rightVerticalSwipePreferenceKey, action);

  static Future<void> saveCompletionAction(VideoCompletionAction action) =>
      _save(completionPreferenceKey, action);

  static Future<void> saveAndroidVideoCompatibility(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (await prefs.setBool(androidVideoCompatibilityPreferenceKey, enabled)) {
      _changes.emit();
    }
  }

  static Future<void> saveDefaultPlaybackSpeed(double speed) async {
    if (!speed.isFinite || speed < 0.25 || speed > 4.0) return;
    final prefs = await SharedPreferences.getInstance();
    if (await prefs.setDouble(defaultPlaybackSpeedPreferenceKey, speed)) {
      _changes.emit();
    }
  }

  static Future<void> saveRememberedVolume({
    required double volume,
    required bool muted,
  }) async {
    if (!volume.isFinite) return;
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    final prefs = await SharedPreferences.getInstance();
    final a = await prefs.setDouble(rememberedVolumePreferenceKey, clamped);
    final b = await prefs.setBool(rememberedMutedPreferenceKey, muted);
    if (a || b) _changes.emit();
  }

  static Future<void> _save(String key, Enum value) async {
    final prefs = await SharedPreferences.getInstance();
    if (await prefs.setString(key, value.name)) _changes.emit();
  }
}
