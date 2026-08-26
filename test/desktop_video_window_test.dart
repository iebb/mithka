import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_video_window.dart';
import 'package:mithka/chat/video_player_view.dart';

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

  test('desktop byte progress is validated before reaching the inspector', () {
    final progress = decodeDesktopVideoProgress(
      '{"file_id":42,"downloaded":3145728,'
      '"prefix_downloaded":2097152,"total":8388608,'
      '"downloaded_ranges":[{"start":0,"end":2097152},'
      '{"start":6291456,"end":7340032}],'
      '"is_active":true,"is_completed":false}',
    );

    expect(progress?.fileId, 42);
    expect(progress?.downloaded, 3 * 1024 * 1024);
    expect(progress?.prefixDownloaded, 2 * 1024 * 1024);
    expect(progress?.total, 8 * 1024 * 1024);
    expect(progress?.isActive, isTrue);
    expect(progress?.downloadedRanges, hasLength(2));
    expect(progress?.downloadedRanges?[0].start, 0);
    expect(progress?.downloadedRanges?[0].end, 2 * 1024 * 1024);
    expect(progress?.downloadedRanges?[1].start, 6 * 1024 * 1024);
    expect(progress?.downloadedRanges?[1].end, 7 * 1024 * 1024);
    expect(decodeDesktopVideoProgress('{"path":"private"}'), isNull);
    expect(decodeDesktopVideoProgress('not json'), isNull);
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

  test('desktop player uses the redesigned chrome and live inspector', () {
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
    expect(window, contains('chromeBuilder:'));
    expect(window, contains('MithkaDesktopVideoChrome('));
    expect(window, contains('VideoStreamDebugger('));
    expect(window, contains('VideoStreamDebuggerOverlay('));
    expect(window, isNot(contains('if (!_debuggerVisible')));
    expect(window, isNot(contains('SizedBox(height: playerHeight')));
    expect(window, contains('debugPaintBaselinesEnabled = false'));
    expect(window, contains('debugPaintSizeEnabled = false'));
    expect(window, contains('DefaultTextStyle.merge('));
    expect(window, contains('decoration: TextDecoration.none'));
    expect(window, contains('tdVideoStreamProgressUri(arguments.uri)'));
    expect(window, contains("HeroAppIcons.pictureInPicture"));
    expect(window, contains('FVideoDesktopWindows.instance.open'));
  });

  test('video duration labels use clock formatting', () {
    expect(formatVideoPlayerDuration(Duration.zero), '0:00');
    expect(formatVideoPlayerDuration(const Duration(seconds: 4)), '0:04');
    expect(formatVideoPlayerDuration(const Duration(seconds: 7841)), '2:10:41');
    // Hours appear only once they exist, and never pad the leading unit.
    expect(formatVideoPlayerDuration(const Duration(seconds: 3600)), '1:00:00');
    expect(formatVideoPlayerDuration(const Duration(seconds: 3599)), '59:59');
    expect(formatVideoPlayerDuration(const Duration(seconds: -5)), '0:00');
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();
    expect(player, isNot(contains("seconds == 1 ? 'sec' : 'secs'")));
  });

  test('desktop video controls omit the decorative waveform', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();

    expect(player, isNot(contains('_MithkaVideoWaveform')));
    expect(player, isNot(contains('showWaveform')));
  });

  test('video seek controls use the owned ten-second glyph', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();

    expect(player, contains('AppSeekTenIcon('));
    expect(player, isNot(contains('HeroAppIcons.rotateLeft')));
    expect(player, isNot(contains('HeroAppIcons.rotateRight')));
  });

  test('desktop video controls omit read-only quality badges', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();
    final window = File('lib/app/desktop_video_window.dart').readAsStringSync();

    expect(player, isNot(contains('_MithkaVideoReadOnlyBadge')));
    expect(player, isNot(contains('qualityLabel')));
    expect(window, isNot(contains('qualityLabel')));
  });

  test('player and inspector typography never use bold weights', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();
    final inspector = File(
      'lib/chat/video_stream_debugger.dart',
    ).readAsStringSync();
    final forbiddenWeight = RegExp(r'FontWeight\.(?:bold|w[5-9]00)');

    expect(forbiddenWeight.allMatches(player), isEmpty);
    expect(forbiddenWeight.allMatches(inspector), isEmpty);
    expect(player, contains('fontWeight: FontWeight.w400'));
    expect(inspector, contains('fontWeight: FontWeight.w400'));
  });

  test('every stream inspector floats over its player surface', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();

    expect(player, contains('VideoStreamDebuggerOverlay('));
    expect(player, isNot(contains('SizedBox(height: playerHeight')));
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

  test('redesigned scrub preview stays inside the package slider surface', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();

    expect(player, contains('FVideoPlayer('));
    expect(player, contains('FVideoSlider('));
    expect(player, isNot(contains('Overlay.of(scrubberContext)')));
    expect(player, isNot(contains('_buildScrubPreviewOverlay(')));
    expect(player, isNot(contains('_showScrubPreviewOverlay(')));
  });
}
