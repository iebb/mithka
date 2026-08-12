import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_video_window.dart';

void main() {
  test('desktop video window arguments round-trip independently', () {
    final first = DesktopVideoWindowArguments(
      uri: Uri.parse('http://127.0.0.1:41001/video/1.mp4'),
      title: 'First video',
      width: 1920,
      height: 1080,
      muted: false,
    );
    final second = DesktopVideoWindowArguments(
      uri: Uri.parse('http://127.0.0.1:41002/video/2.mp4'),
      title: 'Second video',
      width: 720,
      height: 1280,
      muted: true,
    );

    final decodedFirst = DesktopVideoWindowArguments.tryParse(first.encode());
    final decodedSecond = DesktopVideoWindowArguments.tryParse(second.encode());

    expect(decodedFirst?.uri, first.uri);
    expect(decodedFirst?.title, first.title);
    expect(decodedSecond?.uri, second.uri);
    expect(decodedSecond?.muted, isTrue);
    expect(decodedSecond?.width, 720);
    expect(decodedSecond?.height, 1280);
  });

  test('main-window and malformed arguments are ignored', () {
    expect(DesktopVideoWindowArguments.tryParse(''), isNull);
    expect(DesktopVideoWindowArguments.tryParse('{"type":"main"}'), isNull);
    expect(DesktopVideoWindowArguments.tryParse('not json'), isNull);
  });

  test('desktop playback preparation retries a transient range miss', () async {
    var attempts = 0;

    final prepared = await prepareDesktopVideoPlayback(() async {
      attempts++;
      return attempts == 2;
    });

    expect(prepared, isTrue);
    expect(attempts, 2);
  });

  test(
    'desktop playback preparation stops after its bounded retries',
    () async {
      var attempts = 0;

      final prepared = await prepareDesktopVideoPlayback(() async {
        attempts++;
        return false;
      });

      expect(prepared, isFalse);
      expect(attempts, 2);
    },
  );

  test('desktop player delegates windowing and controls to f_videoplayer', () {
    final window = File('lib/app/desktop_video_window.dart').readAsStringSync();
    expect(window, contains('package:f_videoplayer/f_videoplayer.dart'));
    expect(window, contains('stream.prepareForPlayback'));
    expect(
      window.indexOf('stream.prepareForPlayback'),
      lessThan(window.indexOf('FVideoDesktopWindows.instance.open')),
    );
    // The window must appear while the bootstrap ranges are still filling:
    // awaiting preparation here is what made a tapped video look ignored.
    expect(window, contains('stream.holdRequestsUntilPrepared('));
    expect(window, isNot(contains('await prepareDesktopVideoPlayback(')));
    expect(
      window,
      isNot(contains('onClose: FVideoDesktopWindows.closeCurrentWindow')),
    );
    expect(window, isNot(contains('package:multi_window_manager/')));
    expect(window, isNot(contains('desktop_multi_window')));
    expect(window, contains('currentWindowCloseRevision.addListener'));
    expect(window, contains('unawaited(_controller?.pause())'));
    expect(window, contains('FVideoPictureInPicture.start('));
    expect(window, contains('FVideoDesktopWindows.focusCurrentWindow'));
    expect(window, contains('FVideoDesktopWindows.hideCurrentWindow'));
    expect(window, contains('FVideoDesktopWindows.closeCurrentWindow'));
    expect(window, contains('FVideoPlayer('));
    expect(window, contains('FVideoDesktopWindows.instance.open'));
  });

  test('macOS keeps the primary Flutter window visible at launch', () {
    final runner = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(runner, isNot(contains('hiddenWindowAtLaunch()')));
    expect(
      runner,
      contains(
        'MultiWindowManagerPlugin.RegisterGeneratedPlugins = { registry in',
      ),
    );
    expect(runner, contains('RegisterGeneratedPlugins(registry: registry)'));
    expect(runner, contains('DesktopClipboardImagesPlugin.register('));
    expect(runner, isNot(contains('MacOSSystemPictureInPicturePlugin')));
    expect(runner, isNot(contains('AVPictureInPictureController')));
  });

  test('app scrub geometry is delegated to package default chrome', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();

    expect(player, contains('FVideoPlayer('));
    expect(player, isNot(contains('Overlay.of(scrubberContext)')));
    expect(player, isNot(contains('_buildScrubPreviewOverlay(')));
    expect(player, isNot(contains('_showScrubPreviewOverlay(')));
  });
}
