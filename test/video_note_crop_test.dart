import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_note_crop_service.dart';
import 'package:mithka/chat/video_note_recorder_view.dart';

/// The recorder widget needs a real `CameraController`, which the existing
/// harness in `test/video_note_recorder_test.dart` cannot provide. The decision
/// `_finishRecording` makes after the camera stops is therefore extracted as
/// `videoNoteUploadPath` and driven directly here, and a source pin proves that
/// `_finishRecording` is the only place the recorder reaches for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mithka/media_editor');

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('VideoNoteCropService', () {
    test('sends the recording path and returns the cropped file', () async {
      MethodCall? captured;
      answer((call) async {
        captured = call;
        return '/tmp/cropped-note.mp4';
      });
      final result = await VideoNoteCropService.crop('/tmp/recording.mov');
      expect(result, '/tmp/cropped-note.mp4');
      expect(captured?.method, 'cropVideoNote');
      expect(captured?.arguments, {'path': '/tmp/recording.mov'});
    });

    test('returns null when no platform editor is registered', () async {
      // No handler installed: the messenger answers null, which Dart reports
      // as MissingPluginException.
      expect(await VideoNoteCropService.crop('/tmp/recording.mov'), isNull);
    });

    test('returns null when the native editor refuses the file', () async {
      answer(
        (_) async => throw PlatformException(
          code: 'video_crop_failed',
          message: 'The cropped video note failed verification',
        ),
      );
      expect(await VideoNoteCropService.crop('/tmp/recording.mov'), isNull);
    });

    test('returns null when the native editor answers nothing', () async {
      answer((_) async => null);
      expect(await VideoNoteCropService.crop('/tmp/recording.mov'), isNull);
    });

    test('returns null when the native editor echoes the input path', () async {
      answer((_) async => '/tmp/recording.mov');
      expect(await VideoNoteCropService.crop('/tmp/recording.mov'), isNull);
    });

    test(
      'returns null for an empty path without touching the channel',
      () async {
        var calls = 0;
        answer((_) async {
          calls++;
          return '/tmp/cropped-note.mp4';
        });
        expect(await VideoNoteCropService.crop('  '), isNull);
        expect(calls, 0);
      },
    );

    test(
      'gives up on a slow re-encode so the note can still be sent',
      () async {
        final pending = Completer<Object?>();
        answer((_) => pending.future);
        final result = await VideoNoteCropService.crop(
          '/tmp/recording.mov',
          timeout: const Duration(milliseconds: 20),
        );
        expect(result, isNull);
      },
    );
  });

  test(
    'a late completion after the route is left leaves no unowned file',
    () async {
      final dir = await Directory.systemTemp.createTemp('mithka-crop-late');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final lateFile = File('${dir.path}/late.mp4')
        ..writeAsBytesSync(const [0, 0, 0, 1]);
      final pending = Completer<Object?>();
      answer((_) => pending.future);

      // The caller gives up (its route closed) while the exporter runs.
      final result = await VideoNoteCropService.crop(
        '/tmp/recording.mov',
        timeout: const Duration(milliseconds: 20),
      );
      expect(result, isNull);
      expect(lateFile.existsSync(), isTrue);

      // The exporter finishes after the caller is gone: the file it named
      // must not be left behind.
      pending.complete(lateFile.path);
      await VideoNoteCropService.abandonInFlight(
        timeout: const Duration(milliseconds: 200),
      );
      expect(lateFile.existsSync(), isFalse);
    },
  );

  test(
    'a completion inside the window is handed to the caller, not deleted',
    () async {
      final dir = await Directory.systemTemp.createTemp('mithka-crop-live');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final file = File('${dir.path}/live.mp4')
        ..writeAsBytesSync(const [0, 0, 0, 1]);
      answer((_) async => file.path);
      expect(await VideoNoteCropService.crop('/tmp/recording.mov'), file.path);
      // Nothing was abandoned, so cleanup has nothing to do.
      await VideoNoteCropService.abandonInFlight();
      expect(file.existsSync(), isTrue);
    },
  );
  group('isSquareVideoNote', () {
    test('accepts frames that are square within one pixel', () {
      expect(isSquareVideoNote(720, 720), isTrue);
      expect(isSquareVideoNote(721, 720), isTrue);
      expect(isSquareVideoNote(720, 721), isTrue);
    });

    test('rejects wide, tall and degenerate frames', () {
      expect(isSquareVideoNote(1280, 720), isFalse);
      expect(isSquareVideoNote(720, 1280), isFalse);
      expect(isSquareVideoNote(722, 720), isFalse);
      expect(isSquareVideoNote(720, 722), isFalse);
      expect(isSquareVideoNote(0, 0), isFalse);
      expect(isSquareVideoNote(-720, -720), isFalse);
    });
  });

  group('videoNoteUploadPath', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mithka-video-note-test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    File write(String name) =>
        File('${dir.path}/$name')..writeAsBytesSync([0, 1, 2, 3]);

    test(
      'sends the cropped file and drops the recording it replaced',
      () async {
        final recording = write('recording.mov');
        final cropped = write('note.mp4');
        final path = await videoNoteUploadPath(
          recording.path,
          crop: (_) async => cropped.path,
        );
        expect(path, cropped.path);
        expect(cropped.existsSync(), isTrue);
        expect(
          recording.existsSync(),
          isFalse,
          reason: 'the cache must not keep two copies of the note',
        );
      },
    );

    test('keeps the recording when the crop produced nothing', () async {
      final recording = write('recording.mov');
      final path = await videoNoteUploadPath(
        recording.path,
        crop: (_) async => null,
      );
      expect(path, recording.path);
      expect(recording.existsSync(), isTrue);
    });

    test('keeps the recording when the crop throws', () async {
      final recording = write('recording.mov');
      final path = await videoNoteUploadPath(
        recording.path,
        crop: (_) async => throw PlatformException(code: 'unsupported'),
      );
      expect(path, recording.path);
      expect(recording.existsSync(), isTrue);
    });

    test('keeps the recording when the crop names a missing file', () async {
      final recording = write('recording.mov');
      final path = await videoNoteUploadPath(
        recording.path,
        crop: (_) async => '${dir.path}/gone.mp4',
      );
      expect(path, recording.path);
      expect(recording.existsSync(), isTrue);
    });

    test('never deletes a recording that is itself the answer', () async {
      final recording = write('recording.mov');
      final path = await videoNoteUploadPath(
        recording.path,
        crop: (path) async => path,
      );
      expect(path, recording.path);
      expect(recording.existsSync(), isTrue);
    });
  });

  group('recorder source pins', () {
    final source = File(
      'lib/chat/video_note_recorder_view.dart',
    ).readAsStringSync();
    final finishStart = source.indexOf('Future<void> _finishRecording()');
    final cancelStart = source.indexOf('Future<void> _cancelRecording()');
    final buildStart = source.indexOf('String get _elapsedLabel');

    test('crops the file from _finishRecording, not from _cancelRecording', () {
      expect(finishStart, greaterThan(0));
      expect(cancelStart, greaterThan(finishStart));
      expect(buildStart, greaterThan(cancelStart));
      final finishBody = source.substring(finishStart, cancelStart);
      final cancelBody = source.substring(cancelStart, buildStart);
      expect(finishBody, contains('await videoNoteUploadPath(video.path)'));
      expect(cancelBody, isNot(contains('videoNoteUploadPath')));
      expect(cancelBody, isNot(contains('VideoNoteCropService')));
    });

    test('sends the resolved path rather than the raw recording', () {
      final finishBody = source.substring(finishStart, cancelStart);
      expect(
        finishBody,
        contains('VideoNoteCaptureResult(path: path, duration: seconds)'),
      );
      expect(finishBody, isNot(contains('path: video.path')));
    });
  });
}
