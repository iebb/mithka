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
        final ticket = VideoNoteCropService.start('${dir.path}/recording.mov');
        expect(
          await ticket!.resolve(timeout: const Duration(milliseconds: 10)),
          isNull,
        );
        await ticket.abandon(timeout: const Duration(milliseconds: 50));
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
      'late beyond cleanup timeout is still reclaimed by the platform itself',
      () async {
        // Regression for the review's P2: cleanup used to be a five-second
        // wait that gave up and left nobody behind to reclaim a later success.
        // The reclaim now rides the platform future's own completion, so the
        // export finishing long after every wait expired still deletes its
        // temp file, while an accepted send file is never touched.
        final temp = write('late-beyond-timeout.mp4');
        final keep = write('accepted-send.mp4');
        final pending = Completer<Object?>();
        answer(
          (call) => call.arguments['path'] == '${dir.path}/abandoned.mov'
              ? pending.future
              : Future<Object?>.value(keep.path),
        );

        final abandoned = VideoNoteCropService.start(
          '${dir.path}/abandoned.mov',
        );
        expect(
          await abandoned!.resolve(timeout: const Duration(milliseconds: 10)),
          isNull,
        );
        // Both the crop timeout and a zero-length cleanup wait are exhausted
        // long before the platform answers.
        await abandoned.abandon(timeout: Duration.zero);

        // A second recorder resolved its crop and the send path took the file.
        final kept = VideoNoteCropService.start('${dir.path}/kept.mov');
        expect(await kept!.resolve(), keep.path);
        kept.accept(keep.path);

        // The abandoned cleanup wait has given up; the platform is still
        // running and the accepted file belongs to the send path.
        expect(temp.existsSync(), isTrue);
        expect(keep.existsSync(), isTrue);

        pending.complete(temp.path);
        await pumpEventQueue();
        await pumpEventQueue();
        expect(
          temp.existsSync(),
          isFalse,
          reason: 'a late export nobody owns must be reclaimed',
        );
        expect(
          keep.existsSync(),
          isTrue,
          reason: 'an accepted send file must survive a late platform answer',
        );
        // Only the send path's own deletion removes it.
        await keep.delete();
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
        await pumpEventQueue();
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
      await pumpEventQueue();
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
      await pumpEventQueue();
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
      'a surrendered ticket does not touch another recorder\'s accepted crop',
      () async {
        // Regression for the review's "dispose between service delivery and
        // recorder handoff" race, in its cross-instance form: one recorder
        // tearing its route down used to sweep every in-flight export,
        // including a second recorder's accepted send file.
        final dying = write('dying.mp4');
        final live = write('live.mp4');
        var call = 0;
        answer((_) async => (call++ == 0 ? dying : live).path);

        final dyingTicket = VideoNoteCropService.start(
          '${dir.path}/dying-recording.mov',
        );
        expect(
          await dyingTicket!.resolve(timeout: const Duration(seconds: 1)),
          dying.path,
        );
        final liveTicket = VideoNoteCropService.start(
          '${dir.path}/live-recording.mov',
        );
        expect(
          await liveTicket!.resolve(timeout: const Duration(seconds: 1)),
          live.path,
        );
        // The live recorder hands its file to the send path; the dying one
        // never gets there because its route was disposed first.
        liveTicket.accept(live.path);
        await dyingTicket.abandon(timeout: Duration.zero);
        await pumpEventQueue();

        expect(
          dying.existsSync(),
          isFalse,
          reason: 'the disposed recorder must surrender its own crop',
        );
        expect(
          live.existsSync(),
          isTrue,
          reason: 'a live recorder\'s accepted send file must survive',
        );
        await live.delete();
      },
    );

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
        await pumpEventQueue();
        expect(cropped.existsSync(), isFalse);
      },
    );

    test(
      'dispose between delivery and handoff keeps the accepted send file',
      () async {
        // Regression for the review's P2: the delivery flag used to be set
        // while `videoNoteUploadPath` was still awaiting its file checks, so a
        // recorder disposed in that gap left an accepted-but-unsent crop that
        // nobody owned. The flag is now set only after the file is verified and
        // the recording it replaces is gone, and the recorder's own ticket
        // reclaims exactly its own crop.
        final recorded = write('recording.mov');
        final cropped = write('note.mp4');
        answer((_) async => cropped.path);

        VideoNoteCropTicket? ticket;
        var accepted = false;
        final path = await videoNoteUploadPath(
          recorded.path,
          onStarted: (started) => ticket = started,
          accept: (_) => accepted = true,
        );
        expect(path, cropped.path);
        expect(ticket, isNotNull);
        // The recorder disposed between the service delivering the path and
        // the send path taking the file: accept never ran on the real service.
        expect(accepted, isTrue);
        // The recorder's own ticket takes over and reclaims its own crop.
        await ticket!.abandon(timeout: Duration.zero);
        await pumpEventQueue();
        expect(
          cropped.existsSync(),
          isFalse,
          reason: 'a crop the send path never took must be reclaimed',
        );
      },
    );

    test(
      'dispose between delivery and handoff keeps the accepted send file alive',
      () async {
        // The same gap, but this time the send path did take the file before
        // the recorder was disposed: the accepted send file must survive.
        final recorded = write('recording.mov');
        final cropped = write('note.mp4');
        answer((_) async => cropped.path);

        VideoNoteCropTicket? ticket;
        final path = await videoNoteUploadPath(
          recorded.path,
          onStarted: (started) => ticket = started,
        );
        expect(path, cropped.path);
        // `videoNoteUploadPath` accepted on the ticket itself (no accept hook
        // passed), so the file now belongs to the send path.
        expect(ticket, isNotNull);
        // A late sweep (another recorder's dispose or a test tearDown) must
        // not delete a file the send path already owns.
        await VideoNoteCropService.abandonInFlight();
        await pumpEventQueue();
        expect(
          cropped.existsSync(),
          isTrue,
          reason: 'the send path owns the accepted crop and must keep it',
        );
        await cropped.delete();
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
      expect(finishBody, contains('await videoNoteUploadPath('));
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
        expect(branch, contains('_abandonCropAfterResolve(path, video.path)'));
      },
    );

    test('hands its own ticket to the send path or cleanup', () {
      // The recorder must scope its cleanup to its own ticket: a global sweep
      // in _finishRecording or dispose reclaims a second recorder's crop.
      expect(finishBody, contains('onStarted: (ticket) => _cropTicket ='));
      expect(finishBody, isNot(contains('abandonInFlight')));
      final disposeAt = source.lastIndexOf('void dispose()');
      expect(disposeAt, greaterThan(0));
      final disposeBody = source.substring(disposeAt);
      expect(disposeBody, contains('_cropTicket'));
      expect(disposeBody, contains('ticket.abandon()'));
    });

    test('accepts the crop only after the recording it replaces is gone', () {
      final acceptAt = source.indexOf('local.accept(cropped);');
      expect(acceptAt, greaterThan(0));
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
