import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
// The fake platform is the published camera interface the `camera` package
// itself talks to, not a new dependency.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_note_crop_service.dart';
import 'package:mithka/chat/video_note_recorder_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

/// The shapes the pinned package produces for the fixtures below, written out
/// so a test never just echoes the helper under test.
const portraitBoxOfALandscapeFrame = 9 / 16; // 1280x720, portraitUp
const landscapeBoxOfALandscapeFrame = 16 / 9; // 1280x720, landscapeLeft
const landscapeBoxOfAPortraitFrame = 16 / 9; // 720x1280, portraitUp

void main() {
  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
  });

  for (final cropStartedBeforeDisposal in [false, true]) {
    testWidgets(
      'real recorder disposal ${cropStartedBeforeDisposal ? 'during crop' : 'during camera stop'} reclaims only its own export',
      (tester) async {
        final previousPlatform = CameraPlatform.instance;
        final platform = _FakeCameraPlatform();
        CameraPlatform.instance = platform;
        final directory = Directory.systemTemp.createTempSync(
          'recorder-dispose-',
        );
        final recording = File('${directory.path}/recording.mov')
          ..writeAsBytesSync([1]);
        final cropped = File('${directory.path}/cropped.mp4');
        final other = File('${directory.path}/other.mp4')
          ..writeAsBytesSync([3]);
        final stopped = Completer<XFile>();
        final exported = Completer<String?>();
        platform.stoppedVideo = stopped.future;
        var cropsStarted = 0;
        const channel = MethodChannel('mithka/media_editor');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'cropVideoNote');
          if ((call.arguments as Map)['path'] == 'other-recording.mov') {
            return other.path;
          }
          expect((call.arguments as Map)['path'], recording.path);
          cropsStarted++;
          return exported.future;
        });
        addTearDown(() async {
          messenger.setMockMethodCallHandler(channel, null);
          CameraPlatform.instance = previousPlatform;
          await VideoNoteCropService.abandonInFlight(timeout: Duration.zero);
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });

        // A second producer is between native completion and acceptance. A
        // global sweep from State.dispose would wrongly delete this file.
        final otherTicket = VideoNoteCropService.start('other-recording.mov')!;
        expect(await tester.runAsync(otherTicket.resolve), other.path);
        await tester.pumpWidget(
          const MaterialApp(home: VideoNoteRecorderView()),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CameraPreview), findsOneWidget);
        final shutter = find.byKey(const ValueKey('videoNoteRecordButton'));
        await tester.tap(shutter);
        await tester.pump();
        await tester.tap(shutter);
        await tester.pump();
        expect(platform.stopCalls, 1);
        if (cropStartedBeforeDisposal) {
          stopped.complete(XFile(recording.path));
          await tester.pump();
          expect(cropsStarted, 1);
        }

        // Unmount the actual recording State, not a helper standing in for it.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(other.existsSync(), isTrue);
        if (!cropStartedBeforeDisposal) {
          stopped.complete(XFile(recording.path));
          await tester.pump();
          expect(cropsStarted, 0);
        } else {
          cropped.writeAsBytesSync([2]);
        }
        exported.complete(cropped.path);
        await tester.pump();
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
          if (!recording.existsSync() && !cropped.existsSync()) break;
        }
        expect(cropped.existsSync(), isFalse);
        expect(recording.existsSync(), isFalse);
        expect(other.existsSync(), isTrue);
        otherTicket.accept(other.path);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final cancelDuringCrop in [false, true]) {
    testWidgets(
      cancelDuringCrop
          ? 'closing a processing recorder cancels the send and reclaims its files'
          : 'a finished recorder hands its crop to the route consumer',
      (tester) async {
        final previousPlatform = CameraPlatform.instance;
        final platform = _FakeCameraPlatform();
        CameraPlatform.instance = platform;
        final directory = Directory.systemTemp.createTempSync('recorder-send-');
        final recording = File('${directory.path}/recording.mov')
          ..writeAsBytesSync([1]);
        final cropped = File('${directory.path}/cropped.mp4')
          ..writeAsBytesSync([2]);
        platform.stoppedVideo = Future.value(XFile(recording.path));
        const channel = MethodChannel('mithka/media_editor');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        var cropsStarted = 0;
        final exported = Completer<String?>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'cropVideoNote');
          expect((call.arguments as Map)['path'], recording.path);
          cropsStarted++;
          return exported.future;
        });
        addTearDown(() async {
          messenger.setMockMethodCallHandler(channel, null);
          CameraPlatform.instance = previousPlatform;
          await VideoNoteCropService.abandonInFlight(timeout: Duration.zero);
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const SizedBox(key: ValueKey('recorder-home')),
          ),
        );
        VideoNoteCaptureResult? result;
        var routeCompleted = false;
        unawaited(
          navigator.currentState!
              .push<VideoNoteCaptureResult>(
                MaterialPageRoute(
                  builder: (_) => const VideoNoteRecorderView(),
                ),
              )
              .then((value) {
                routeCompleted = true;
                result = value;
              }),
        );
        await tester.pumpAndSettle();
        final shutter = find.byKey(const ValueKey('videoNoteRecordButton'));
        await tester.tap(shutter);
        await tester.pump();
        await tester.tap(shutter);
        await tester.pump();
        expect(cropsStarted, 1);
        if (cancelDuringCrop) {
          await tester.tap(_roundButton('Close camera'));
          // Complete the native reply while the popped route is still mounted
          // for its reverse animation. Mounted alone is not route ownership.
          await tester.pump();
          expect(routeCompleted, isTrue);
          expect(result, isNull);
          expect(find.byType(VideoNoteRecorderView), findsOneWidget);
        }
        exported.complete(cropped.path);
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (routeCompleted &&
              !recording.existsSync() &&
              cropped.existsSync() == !cancelDuringCrop) {
            break;
          }
        }
        await tester.pumpAndSettle();
        expect(routeCompleted, isTrue);
        expect(result?.path, cancelDuringCrop ? isNull : cropped.path);
        if (!cancelDuringCrop) expect(result?.duration, 1);
        expect(find.byType(VideoNoteRecorderView), findsNothing);
        expect(find.byKey(const ValueKey('recorder-home')), findsOneWidget);
        expect(recording.existsSync(), isFalse);
        expect(cropped.existsSync(), !cancelDuringCrop);
        await VideoNoteCropService.abandonInFlight(timeout: Duration.zero);
        expect(cropped.existsSync(), !cancelDuringCrop);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Finder _roundButton(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.key == ValueKey('videoNoteRecorderRoundButton-$label'),
);

/// The published camera interface the `camera` package talks to: enough of it
/// for a real [CameraController] and [CameraPreview] to initialize and paint a
/// texture, while orientations can be pushed exactly as the device would.
class _FakeCameraPlatform extends CameraPlatform {
  final StreamController<CameraInitializedEvent> _initialized =
      StreamController<CameraInitializedEvent>.broadcast();
  // The real plugin's error stream never completes either; `.first` on it is
  // left pending for the camera's lifetime, not failed with "No element".

  final StreamController<DeviceOrientationChangedEvent> _orientation =
      StreamController<DeviceOrientationChangedEvent>.broadcast();

  Size previewSize = const Size(1280, 720);
  DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp;
  CameraController? controller;
  Future<XFile>? stoppedVideo;
  int stopCalls = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    return const [
      CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    return 1;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    // The controller subscribes to its init event before this call returns, so
    // the event can be delivered synchronously; any timer or microtask here
    // would need a pump that cannot happen while `initialize()` is awaited.
    _initialized.add(
      CameraInitializedEvent(
        cameraId,
        previewSize.width,
        previewSize.height,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) {
    return _initialized.stream;
  }

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) {
    // The plugin's error stream stays open for the camera's lifetime. A closed
    // stream would instead fail the controller's `.first` with "No element",
    // so this one never emits and never ends.
    return Stream<CameraErrorEvent>.multi((_) {});
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() {
    return _orientation.stream;
  }

  /// Emits a device rotation exactly as the platform would, without resizing
  /// the window.
  Future<void> pushOrientation(DeviceOrientation orientation) async {
    deviceOrientation = orientation;
    // A broadcast stream delivers synchronously, so the controller's value is
    // already updated when this returns.
    _orientation.add(DeviceOrientationChangedEvent(orientation));
  }

  @override
  Future<void> prepareForVideoRecording() async {}

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}

  @override
  Future<void> unlockCaptureOrientation(int cameraId) async {}

  @override
  Future<void> pausePreview(int cameraId) async {}

  @override
  Future<void> resumePreview(int cameraId) async {}

  @override
  Future<void> startVideoRecording(
    int cameraId, {
    Duration? maxVideoDuration,
  }) async {}

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {}

  @override
  Future<void> pauseVideoRecording(int cameraId) async {}

  @override
  Future<void> resumeVideoRecording(int cameraId) async {}

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stopCalls++;
    final pending = stoppedVideo;
    if (pending != null) return pending;
    return XFile('video-note-test.mp4');
  }

  @override
  Widget buildPreview(int cameraId) {
    return const Texture(textureId: 7);
  }

  @override
  Future<void> dispose(int cameraId) async {}
}
