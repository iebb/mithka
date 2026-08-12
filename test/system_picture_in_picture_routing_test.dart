import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video PiP uses system controllers instead of an app overlay', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();
    final splitHost = File(
      'lib/app/global_video_split_host.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/app/video_split_controller.dart',
    ).readAsStringSync();
    final chat = File('lib/chat/chat_view.dart').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/ad/neko/mithka/MainActivity.kt',
    ).readAsStringSync();
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(player, contains('FVideoPictureInPicture.startPrepared('));
    expect(player, contains('FVideoPictureInPicture.start('));
    expect(splitHost, isNot(contains('OverlayEntry')));
    expect(controller, isNot(contains('VideoPiPController')));
    expect(chat, isNot(contains('_showVideoPictureInPicture')));
    expect(appDelegate, isNot(contains('FVideoPictureInPictureBridge')));
    expect(
      mainActivity,
      contains('FVideoPictureInPicturePlugin.onUserLeaveHint'),
    );
    expect(
      mainActivity,
      contains(
        'add("com.iebb.f_videoplayer_pip.'
        'FVideoPictureInPicturePlugin")',
      ),
    );
    expect(mainActivity, contains('onPictureInPictureRequested'));
    expect(mainActivity, contains('onPictureInPictureModeChanged'));
    expect(
      androidManifest,
      contains('android:supportsPictureInPicture="true"'),
    );
    expect(androidManifest, isNot(contains('SYSTEM_ALERT_WINDOW')));
  });

  test('one display mode control owns split and PiP routing', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();

    expect(player, contains('AppStringKeys.videoPlayerToggleDisplayMode'));
    expect(player, contains('void _toggleModeMenu()'));
    expect(player, contains('void _selectDisplayMode(VideoDisplayMode mode)'));
    expect(player, contains('if (mode == VideoDisplayMode.pictureInPicture)'));
    expect(player, contains('unawaited(_enterPictureInPicture());'));
    expect(player, isNot(contains('Widget _modeSwitchButton(')));
    expect(player, isNot(contains('Widget _systemPictureInPictureButton(')));
    expect(player, isNot(contains('PopupMenuButton<VideoDisplayMode>')));
  });
}
