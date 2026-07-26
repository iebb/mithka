import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_playback_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('video playback preferences use the requested defaults', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = await VideoPlaybackPreferences.load();

    expect(
      preferences.horizontalSwipeAction,
      VideoHorizontalSwipeAction.adjustProgress,
    );
    expect(
      preferences.leftVerticalSwipeAction,
      VideoVerticalSwipeAction.brightness,
    );
    expect(
      preferences.rightVerticalSwipeAction,
      VideoVerticalSwipeAction.volume,
    );
    expect(preferences.completionAction, VideoCompletionAction.prompt);
  });

  test('video playback preferences persist all custom actions', () async {
    SharedPreferences.setMockInitialValues({});

    await VideoPlaybackPreferences.saveHorizontalSwipeAction(
      VideoHorizontalSwipeAction.changeVideo,
    );
    await VideoPlaybackPreferences.saveLeftVerticalSwipeAction(
      VideoVerticalSwipeAction.volume,
    );
    await VideoPlaybackPreferences.saveRightVerticalSwipeAction(
      VideoVerticalSwipeAction.disabled,
    );
    await VideoPlaybackPreferences.saveCompletionAction(
      VideoCompletionAction.autoplayNext,
    );

    final preferences = await VideoPlaybackPreferences.load();
    expect(
      preferences.horizontalSwipeAction,
      VideoHorizontalSwipeAction.changeVideo,
    );
    expect(
      preferences.leftVerticalSwipeAction,
      VideoVerticalSwipeAction.volume,
    );
    expect(
      preferences.rightVerticalSwipeAction,
      VideoVerticalSwipeAction.disabled,
    );
    expect(preferences.completionAction, VideoCompletionAction.autoplayNext);
  });

  test('unknown saved values fall back safely', () async {
    SharedPreferences.setMockInitialValues({
      VideoPlaybackPreferences.horizontalSwipePreferenceKey: 'unknown',
      VideoPlaybackPreferences.leftVerticalSwipePreferenceKey: 'unknown',
      VideoPlaybackPreferences.rightVerticalSwipePreferenceKey: 'unknown',
      VideoPlaybackPreferences.completionPreferenceKey: 'unknown',
    });

    final preferences = await VideoPlaybackPreferences.load();

    expect(
      preferences.horizontalSwipeAction,
      VideoHorizontalSwipeAction.adjustProgress,
    );
    expect(
      preferences.leftVerticalSwipeAction,
      VideoVerticalSwipeAction.brightness,
    );
    expect(
      preferences.rightVerticalSwipeAction,
      VideoVerticalSwipeAction.volume,
    );
    expect(preferences.completionAction, VideoCompletionAction.prompt);
  });
}
