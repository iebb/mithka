import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_note_crop_service.dart';
import 'package:mithka/chat/video_note_recorder_view.dart';

/// Service/channel boundaries are driven directly here. The companion recorder
/// tests also mount the real recorder State and dispose it during camera stop
/// and native export, proving cleanup cannot reclaim another producer's file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mithka/media_editor');

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  // Deletion is real file I/O, so a fixed number of event-queue turns can lose
  // the race on a busy runner. Wait for it instead, within a bound.
  Future<void> settleDeletion(File file) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (file.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
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
        await settleDeletion(lateFile);
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
        await settleDeletion(file);
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

    test('keeps the recording when the crop throws', () async {
      final recording = write('recording.mov');
      final path = await videoNoteUploadPath(
        recording.path,
        crop: (_) async => throw PlatformException(code: 'unsupported'),
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
        await settleDeletion(cropped);
        expect(
          cropped.existsSync(),
          isFalse,
          reason: 'a crop the send path never took must be reclaimed',
        );
      },
    );
  });
}
