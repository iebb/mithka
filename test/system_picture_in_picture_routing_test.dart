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

  test(
    'package chrome owns presentation controls while the host routes them',
    () {
      final player = File('lib/chat/video_player_view.dart').readAsStringSync();

      expect(player, contains('onPictureInPictureChanged:'));
      expect(player, contains('bottomTrailingBuilder:'));
      expect(player, contains('topTrailingBuilder:'));
      expect(player, contains('VideoDisplayMode.split'));
      expect(player, contains('FVideoPictureInPicture.startPrepared('));
      expect(player, contains('FVideoPictureInPicture.start('));
      expect(player, contains('Widget _playerBottomTrailing('));
      expect(player, contains('Widget _displayModeButton('));
      // Fullscreen supplies its own chrome since the video redesign; every
      // other presentation, picture-in-picture included, still takes the
      // package's, so this stays conditional rather than unconditional.
      expect(player, contains('chromeBuilder: widget.presentation =='));
      expect(player, isNot(contains('FVideoInteractionMode.delegateToChrome')));
    },
  );
}
