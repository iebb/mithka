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

  test(
    'desktop player uses package windowing and native keyboard controls',
    () {
      final window = File(
        'lib/app/desktop_video_window.dart',
      ).readAsStringSync();
      final packageWindow = File(
        'packages/mithka_video_player/lib/src/desktop_video_windows.dart',
      ).readAsStringSync();
      final desktopWindowImplementation = File(
        'packages/mithka_video_player/lib/src/desktop_video_windows_io.dart',
      ).readAsStringSync();
      final portableWindowStub = File(
        'packages/mithka_video_player/lib/src/desktop_video_windows_stub.dart',
      ).readAsStringSync();
      final player = File(
        'packages/mithka_video_player/lib/src/video_player.dart',
      ).readAsStringSync();

      expect(window, contains('package:mithka_video_player/'));
      expect(window, isNot(contains('package:multi_window_manager/')));
      expect(packageWindow, isNot(contains('package:multi_window_manager/')));
      expect(packageWindow, isNot(contains("import 'dart:io'")));
      expect(
        desktopWindowImplementation,
        contains('package:multi_window_manager/'),
      );
      expect(portableWindowStub, isNot(contains('multi_window_manager')));
      expect(window, isNot(contains('desktop_multi_window')));
      expect(player, contains('LogicalKeyboardKey.space'));
      expect(player, contains('LogicalKeyboardKey.arrowLeft'));
      expect(player, contains('LogicalKeyboardKey.arrowRight'));
      expect(player, contains('LogicalKeyboardKey.keyM'));
      expect(player, contains('onDoubleTapDown:'));
      expect(
        player,
        contains('textDirection == TextDirection.rtl\n        ? 1 - fraction'),
      );
      expect(
        player,
        contains('math.max(0, trackWidth - thumbRadius * 2) * visualFraction'),
      );
      expect(player, contains('thumbCenter - previewWidth / 2'));
      expect(player, contains('math.max(0.0, trackWidth - previewWidth)'));
    },
  );

  test('macOS keeps the primary Flutter window visible at launch', () {
    final runner = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(runner, isNot(contains('hiddenWindowAtLaunch()')));
    expect(
      runner,
      contains(
        'MultiWindowManagerPlugin.RegisterGeneratedPlugins = '
        'RegisterGeneratedPlugins',
      ),
    );
  });

  test('scrub preview converts through the root overlay coordinates', () {
    final player = File('lib/chat/video_player_view.dart').readAsStringSync();

    expect(
      player,
      contains('Overlay.of(scrubberContext).context.findRenderObject()'),
    );
    expect(player, contains('overlayBox.globalToLocal(globalTarget)'));
    expect(player, isNot(contains('ancestor: overlayBox')));
  });
}
