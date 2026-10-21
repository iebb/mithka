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

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    // A test that leaves an export running must not leak it into the next one;
    // zero wait keeps cleanup attached to the platform future without stalling
    // the suite for the default five seconds.
    await VideoNoteCropService.abandonInFlight(timeout: Duration.zero);
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
        pending.complete(null);
      },
    );
  });

  group('VideoNoteCropService ownership', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mithka-crop-owner');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    File write(String name) =>
        File('${dir.path}/$name')..writeAsBytesSync(const [0, 0, 0, 1]);

    test(
      'a slow export still has its file reclaimed after a cleanup wait gives up',
      () async {
        final lateFile = write('late.mp4');
        final pending = Completer<Object?>();
        answer((_) => pending.future);

        // The export outlives the crop timeout and the bounded cleanup wait.
        final result = await VideoNoteCropService.crop(
          '${dir.path}/recording.mov',
          timeout: const Duration(milliseconds: 10),
        );
        expect(result, isNull);
        await VideoNoteCropService.abandonInFlight(
          timeout: const Duration(milliseconds: 50),
        );
        // Nothing was produced yet, so nothing could be deleted yet.
        expect(lateFile.existsSync(), isTrue);

        // The platform finishes long after cleanup returned: the deletion is
        // attached to this completion, not to the wait that gave up.
        pending.complete(lateFile.path);
        await pumpEventQueue();
        expect(
          lateFile.existsSync(),
          isFalse,
          reason: 'a late export of an abandoned request must be reclaimed',
        );
      },
    );

    test(
      'a completed but unaccepted crop is removed when the route is left',
      () async {
        final file = write('unaccepted.mp4');
        answer((_) async => file.path);
        expect(
          await VideoNoteCropService.crop('${dir.path}/recording.mov'),
          file.path,
        );
        // The caller never accepted: the service still owns the file.
        await VideoNoteCropService.abandonInFlight();
        expect(file.existsSync(), isFalse);
      },
    );

    test('an accepted crop survives cleanup', () async {
      final file = write('accepted.mp4');
      answer((_) async => file.path);
      final path = await VideoNoteCropService.crop('${dir.path}/recording.mov');
      expect(path, file.path);
      VideoNoteCropService.accept(path!);
      await VideoNoteCropService.abandonInFlight();
      expect(
        file.existsSync(),
        isTrue,
        reason: 'an accepted file belongs to the caller, not to cleanup',
      );
      // Only the caller's own deletion removes it.
      await file.delete();
      expect(file.existsSync(), isFalse);
    });

    test('accepting an unknown path is a no-op', () async {
      final file = write('stranger.mp4');
      answer((_) async => file.path);
      final path = await VideoNoteCropService.crop('${dir.path}/recording.mov');
      VideoNoteCropService.accept('${dir.path}/nothing-here.mp4');
      await VideoNoteCropService.abandonInFlight();
      expect(path, isNotNull);
      expect(file.existsSync(), isFalse);
    });

    test('ownership is per request, not per last export', () async {
      final acceptedFile = write('accepted.mp4');
      final abandonedFile = write('abandoned.mp4');
      var call = 0;
      answer((_) async => (call++ == 0 ? acceptedFile : abandonedFile).path);
      final first = await VideoNoteCropService.crop('${dir.path}/first.mov');
      final second = await VideoNoteCropService.crop('${dir.path}/second.mov');
      VideoNoteCropService.accept(first!);
      await VideoNoteCropService.abandonInFlight();
      expect(acceptedFile.existsSync(), isTrue);
      expect(
        abandonedFile.existsSync(),
        isFalse,
        reason: 'abandoning one request must not spare another request',
      );
      expect(second, abandonedFile.path);
      await acceptedFile.delete();
    });

    test(
      'never deletes the recording an abandoned request started from',
      () async {
        final recording = write('recording.mov');
        answer((_) async => recording.path);
        expect(
          await VideoNoteCropService.crop(recording.path),
          isNull,
          reason: 'an echoed input path is not a crop',
        );
        await VideoNoteCropService.abandonInFlight();
        expect(recording.existsSync(), isTrue);
      },
    );
  });

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

    test(
      'accepts the crop it sends and its abandon-then-accept boundary holds',
      () async {
        final recorded = write('recording.mov');
        final cropped = write('note.mp4');
        final accepted = <String>[];
        // Drive the real service: its request owns the file until
        // `videoNoteUploadPath` reaches the end and accepts it.
        answer((_) async => cropped.path);
        final path = await videoNoteUploadPath(
          recorded.path,
          accept: (path) {
            accepted.add(path);
            VideoNoteCropService.accept(path);
          },
        );
        expect(path, cropped.path);
        expect(accepted, [cropped.path]);
        expect(recorded.existsSync(), isFalse);

        // Accepted before the route was left: cleanup leaves it alone.
        await VideoNoteCropService.abandonInFlight();
        expect(
          cropped.existsSync(),
          isTrue,
          reason: 'the send path owns the accepted crop',
        );
        VideoNoteCropService.accept(cropped.path);
        await cropped.delete();
      },
    );

    test(
      'a crop the send path never accepted is reclaimed when the route is left',
      () async {
        final recorded = write('recording.mov');
        final cropped = write('note.mp4');
        answer((_) async => cropped.path);
        final path = await videoNoteUploadPath(recorded.path, accept: (_) {});
        expect(path, cropped.path);
        // The recorder was disposed in the gap after crop() returned but
        // before the handoff: no accept happened, so cleanup reclaims it.
        await VideoNoteCropService.abandonInFlight();
        expect(cropped.existsSync(), isFalse);
      },
    );
  });

  group('recorder source pins', () {
    final source = File(
      'lib/chat/video_note_recorder_view.dart',
    ).readAsStringSync();
    final finishStart = source.indexOf('Future<void> _finishRecording(');
    final cancelStart = source.indexOf('Future<void> _cancelRecording()');
    final buildStart = source.indexOf('String get _elapsedLabel');
    final finishBody = source.substring(finishStart, cancelStart);
    final cancelBody = source.substring(cancelStart, buildStart);

    test('crops the file from _finishRecording, not from _cancelRecording', () {
      expect(finishStart, greaterThan(0));
      expect(cancelStart, greaterThan(finishStart));
      expect(buildStart, greaterThan(cancelStart));
      expect(finishBody, contains('await videoNoteUploadPath(video.path)'));
      expect(cancelBody, isNot(contains('videoNoteUploadPath')));
      expect(cancelBody, isNot(contains('VideoNoteCropService')));
    });

    test('sends the resolved path rather than the raw recording', () {
      expect(
        finishBody,
        contains('VideoNoteCaptureResult(path: path, duration: seconds)'),
      );
      expect(finishBody, isNot(contains('path: video.path')));
    });

    test(
      'drops a crop the disposed recorder accepted, keeps the recording',
      () {
        final unmounted = finishBody.indexOf('if (!mounted)');
        expect(unmounted, greaterThan(0));
        final branch = finishBody.substring(
          unmounted,
          finishBody.indexOf('Navigator.of(', unmounted),
        );
        expect(branch, contains('VideoNoteCropService.abandonInFlight()'));
        expect(branch, contains('if (path != video.path)'));
        expect(branch, contains('await cropped.delete()'));
      },
    );

    test('accepts the crop only after the recording it replaces is gone', () {
      final acceptAt = source.indexOf('VideoNoteCropService.accept)(cropped)');
      final deleteAt = source.indexOf('if (await original.exists())');
      expect(deleteAt, greaterThan(0));
      expect(acceptAt, greaterThan(deleteAt));
      expect(
        source.indexOf('return cropped;', acceptAt),
        greaterThan(acceptAt),
        reason: 'accept happens immediately before the handoff',
      );
    });
  });
}
