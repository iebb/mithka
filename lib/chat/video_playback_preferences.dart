import 'package:shared_preferences/shared_preferences.dart';

enum VideoHorizontalSwipeAction {
  disabled,
  adjustProgress,
  changeVideo,
  skipTenSeconds,
}

enum VideoVerticalSwipeAction { disabled, brightness, volume }

enum VideoCompletionAction { prompt, autoplayNext, replay, returnToChat }

class VideoPlaybackPreferences {
  const VideoPlaybackPreferences({
    this.horizontalSwipeAction = VideoHorizontalSwipeAction.adjustProgress,
    this.leftVerticalSwipeAction = VideoVerticalSwipeAction.brightness,
    this.rightVerticalSwipeAction = VideoVerticalSwipeAction.volume,
    this.completionAction = VideoCompletionAction.prompt,
  });

  static const horizontalSwipePreferenceKey =
      'videoPlayback.horizontalSwipeAction';
  static const leftVerticalSwipePreferenceKey =
      'videoPlayback.leftVerticalSwipeAction';
  static const rightVerticalSwipePreferenceKey =
      'videoPlayback.rightVerticalSwipeAction';
  static const completionPreferenceKey = 'videoPlayback.completionAction';

  final VideoHorizontalSwipeAction horizontalSwipeAction;
  final VideoVerticalSwipeAction leftVerticalSwipeAction;
  final VideoVerticalSwipeAction rightVerticalSwipeAction;
  final VideoCompletionAction completionAction;

  VideoPlaybackPreferences copyWith({
    VideoHorizontalSwipeAction? horizontalSwipeAction,
    VideoVerticalSwipeAction? leftVerticalSwipeAction,
    VideoVerticalSwipeAction? rightVerticalSwipeAction,
    VideoCompletionAction? completionAction,
  }) {
    return VideoPlaybackPreferences(
      horizontalSwipeAction:
          horizontalSwipeAction ?? this.horizontalSwipeAction,
      leftVerticalSwipeAction:
          leftVerticalSwipeAction ?? this.leftVerticalSwipeAction,
      rightVerticalSwipeAction:
          rightVerticalSwipeAction ?? this.rightVerticalSwipeAction,
      completionAction: completionAction ?? this.completionAction,
    );
  }

  static Future<VideoPlaybackPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return fromPreferences(prefs);
  }

  static VideoPlaybackPreferences fromPreferences(SharedPreferences prefs) {
    return VideoPlaybackPreferences(
      horizontalSwipeAction: _enumByName(
        VideoHorizontalSwipeAction.values,
        prefs.getString(horizontalSwipePreferenceKey),
        VideoHorizontalSwipeAction.adjustProgress,
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
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(horizontalSwipePreferenceKey, action.name);
  }

  static Future<void> saveLeftVerticalSwipeAction(
    VideoVerticalSwipeAction action,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(leftVerticalSwipePreferenceKey, action.name);
  }

  static Future<void> saveRightVerticalSwipeAction(
    VideoVerticalSwipeAction action,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(rightVerticalSwipePreferenceKey, action.name);
  }

  static Future<void> saveCompletionAction(VideoCompletionAction action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(completionPreferenceKey, action.name);
  }
}
