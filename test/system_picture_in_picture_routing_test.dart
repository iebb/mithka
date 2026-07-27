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
    final bridge = File(
      'lib/platform/system_picture_in_picture.dart',
    ).readAsStringSync();
    final android = File(
      'third_party/system_picture_in_picture/android/src/main/kotlin/ad/neko/mithka/system_picture_in_picture/SystemPictureInPicturePlugin.kt',
    ).readAsStringSync();
    final iosPlugin = File(
      'third_party/system_picture_in_picture/ios/Classes/SystemPictureInPicturePlugin.swift',
    ).readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/ad/neko/mithka/MainActivity.kt',
    ).readAsStringSync();

    expect(player, contains('SystemPictureInPicture.startPrepared('));
    expect(player, contains('SystemPictureInPicture.start('));
    expect(splitHost, isNot(contains('OverlayEntry')));
    expect(controller, isNot(contains('VideoPiPController')));
    expect(chat, isNot(contains('_showVideoPictureInPicture')));
    expect(bridge, contains('Platform.isIOS || Platform.isAndroid'));
    expect(android, contains('enterPictureInPictureMode'));
    expect(android, contains('setAspectRatio'));
    expect(iosPlugin, contains('AVPictureInPictureController'));
    expect(appDelegate, isNot(contains('SystemPictureInPictureBridge')));
    expect(mainActivity, isNot(contains('SystemPictureInPicturePlugin')));
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

  test('Apple PiP backends share the restore and final-position contract', () {
    final fallback = File(
      'third_party/system_picture_in_picture/ios/Classes/SystemPictureInPicturePlugin.swift',
    ).readAsStringSync();
    final fvpIos = File(
      'third_party/fvp/ios/Classes/FvpPlugin.mm',
    ).readAsStringSync();
    final fvpDarwin = File(
      'third_party/fvp/darwin/Classes/FvpPlugin.mm',
    ).readAsStringSync();
    final fvpSpm = File(
      'third_party/fvp/darwin/fvp/Sources/fvp/FvpPlugin.mm',
    ).readAsStringSync();

    expect(fallback, contains('"restoreRequested"'));
    expect(fallback, contains('"positionMs": stoppedPositionMs'));
    expect(fvpSpm, contains('invokeMethod:@"restoreRequested"'));
    expect(fvpSpm, contains('@"positionMs": @(stoppedPositionMs)'));
    expect(fvpIos, fvpSpm);
    expect(fvpDarwin, fvpSpm);
  });
}
