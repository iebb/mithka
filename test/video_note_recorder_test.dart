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

  test('video-note recording gesture distinguishes lock and cancel', () {
    expect(
      videoNoteRecordGestureForDelta(dx: 0, dy: -71),
      VideoNoteRecordGesture.lock,
    );
    expect(
      videoNoteRecordGestureForDelta(dx: -91, dy: -100),
      VideoNoteRecordGesture.cancel,
    );
    expect(
      videoNoteRecordGestureForDelta(dx: -40, dy: -30),
      VideoNoteRecordGesture.continueRecording,
    );
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

  testWidgets('recorder chrome is a light film over the black preview', (
    tester,
  ) async {
    // No camera plugin handler in a widget test, so the preview reports its
    // unavailable state; the control chrome is what the camera route paints
    // over the black surface in every state.
    await tester.pumpWidget(const MaterialApp(home: VideoNoteRecorderView()));
    await tester.pump();

    // The route still reads as camera chrome: a black surface behind the
    // preview, not a raised gray slab.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.black,
      ),
      findsWidgets,
    );

    final recordButton = find.byKey(const ValueKey('videoNoteRecordButton'));
    expect(recordButton, findsOneWidget);
    final recordDecoration =
        tester.widget<Container>(recordButton).decoration! as BoxDecoration;
    expect(recordDecoration.shape, BoxShape.circle);
    expect(recordDecoration.border!.top.color, Colors.white);
    expect(recordDecoration.border!.top.width, 3);

    // The shutter disc keeps the full-strength red record affordance.
    final disc = find.byKey(const ValueKey('videoNoteRecordButtonDisc'));
    expect(disc, findsOneWidget);
    expect(
      (tester.widget<AnimatedContainer>(disc).decoration! as BoxDecoration)
          .color,
      const Color(0xFFE53935),
    );

    // An enabled round control: white at 16% with a 25% white outline.
    final closeButton = _roundButton('Close camera');
    expect(closeButton, findsOneWidget);
    final closeDecoration =
        tester.widget<Container>(closeButton).decoration! as BoxDecoration;
    expect(closeDecoration.color, const Color(0x29FFFFFF));
    expect(closeDecoration.border!.top.color, const Color(0x40FFFFFF));
    expect(recordDecoration.color, isNot(const Color(0x29FFFFFF)));

    // A disabled round control (the camera switch without a second lens)
    // fades to white at 8% instead of keeping a solid dark plate.
    final switchButton = _roundButton('Switch camera');
    expect(switchButton, findsOneWidget);
    final switchDecoration =
        tester.widget<Container>(switchButton).decoration! as BoxDecoration;
    expect(switchDecoration.color, const Color(0x14FFFFFF));
    expect(switchDecoration.border!.top.color, const Color(0x1FFFFFFF));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'preview footprint handles missing frames and exact square boundaries',
    () {
      const viewport = Size(834, 1194);
      for (final preview in [null, Size.zero]) {
        final footprint = videoNotePreviewFootprint(
          previewSize: preview,
          viewport: viewport,
          aspectRatio: 9 / 16,
        );
        expect(footprint.size, viewport);
        expect(footprint.coverCropped, isFalse);
      }
      for (final window in [const Size(1024, 1024), viewport]) {
        final footprint = videoNotePreviewFootprint(
          previewSize: const Size(720, 720),
          viewport: window,
          aspectRatio: 1,
        );
        expect(footprint.size, const Size(720, 720));
        expect(footprint.coverCropped, window.width != window.height);
      }
    },
  );

  group('videoNotePreviewAspectRatio', () {
    test('a landscape frame follows the device orientation', () {
      expect(videoNotePreviewAspectRatio(_value()), closeTo(9 / 16, 1e-9));
      expect(
        videoNotePreviewAspectRatio(
          _value(device: DeviceOrientation.landscapeLeft),
        ),
        closeTo(16 / 9, 1e-9),
      );
    });

    test('a portrait previewSize in portraitUp gets the package 16:9 box', () {
      // The pinned package's `aspectRatio` is width/height (0.5625 here) and a
      // portrait orientation takes its reciprocal. The previewSize shape is
      // irrelevant; any extra portrait/landscape comparison is the bug.
      expect(
        videoNotePreviewAspectRatio(_value(previewSize: const Size(720, 1280))),
        closeTo(16 / 9, 1e-9),
      );
      expect(
        videoNotePreviewAspectRatio(
          _value(
            previewSize: const Size(720, 1280),
            device: DeviceOrientation.landscapeRight,
          ),
        ),
        closeTo(9 / 16, 1e-9),
      );
    });

    test('a locked capture orientation wins over the device orientation', () {
      // The device turned landscape but the capture stays locked in portrait:
      // the frame, and therefore the box, stays portrait.
      expect(
        videoNotePreviewAspectRatio(
          _value(
            device: DeviceOrientation.landscapeLeft,
            locked: DeviceOrientation.portraitUp,
          ),
        ),
        closeTo(portraitBoxOfALandscapeFrame, 1e-9),
      );
      // Locked landscape while the device reports portrait: landscape box.
      expect(
        videoNotePreviewAspectRatio(
          _value(locked: DeviceOrientation.landscapeLeft),
        ),
        closeTo(landscapeBoxOfALandscapeFrame, 1e-9),
      );
    });

    test('a paused preview orientation wins over lock and device', () {
      // Same frame size throughout; only the applicable orientation changes.
      expect(
        videoNotePreviewAspectRatio(
          _value(
            locked: DeviceOrientation.landscapeLeft,
            paused: DeviceOrientation.portraitUp,
          ),
        ),
        closeTo(portraitBoxOfALandscapeFrame, 1e-9),
      );
      expect(
        videoNotePreviewAspectRatio(
          _value(
            device: DeviceOrientation.landscapeLeft,
            paused: DeviceOrientation.portraitUp,
          ),
        ),
        closeTo(portraitBoxOfALandscapeFrame, 1e-9),
      );
    });

    test('the recording orientation applies only while recording', () {
      // A 1280x720 frame recorded in landscapeRight: landscape box.
      expect(
        videoNotePreviewAspectRatio(
          _value(
            recording: DeviceOrientation.landscapeRight,
            isRecording: true,
          ),
        ),
        closeTo(landscapeBoxOfALandscapeFrame, 1e-9),
      );
      // With the recording stopped the recording orientation is ignored and
      // the (portrait) device orientation decides the box.
      expect(
        videoNotePreviewAspectRatio(
          _value(recording: DeviceOrientation.landscapeRight),
        ),
        closeTo(portraitBoxOfALandscapeFrame, 1e-9),
      );
    });

    test('a preview size that is not reported yet has no box ratio', () {
      // CameraPreview draws a bare Container while uninitialized, and the
      // package's own ratio getter force-unwraps the preview size; inventing
      // 1:1 here would size a box the package never draws.
      expect(videoNotePreviewAspectRatio(_value(previewSize: null)), isNull);
      expect(
        videoNotePreviewAspectRatio(_value(previewSize: Size.zero)),
        isNull,
      );
    });
  });

  group('VideoNotePreviewBox against the real CameraPreview', () {
    late _FakeCameraPlatform platform;

    setUp(() {
      platform = _FakeCameraPlatform();
      CameraPlatform.instance = platform;
    });

    tearDown(() async {
      // Not awaited: the controller's dispose completes through a fake-clock
      // timer the test runner no longer pumps, which would hang teardown.
      final controller = platform.controller;
      platform.controller = null;
      unawaited(controller?.dispose());
      CameraPlatform.instance = _FakeCameraPlatform();
    });

    testWidgets('a portrait previewSize covers the box at the package ratio', (
      tester,
    ) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      tester.view.physicalSize = const Size(390, 844);

      final controller = await _initializeCamera(
        platform,
        previewSize: const Size(720, 1280),
        device: DeviceOrientation.portraitUp,
      );
      await _pumpPreview(tester, controller, const Size(390, 844));

      _expectPreviewBox(
        tester,
        ratio: landscapeBoxOfAPortraitFrame,
        unconstrained: const Size(720, 1280),
      );
    });

    testWidgets('a landscape device orientation turns the box', (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      tester.view.physicalSize = const Size(390, 844);

      final controller = await _initializeCamera(
        platform,
        previewSize: const Size(1280, 720),
        device: DeviceOrientation.landscapeLeft,
      );
      await _pumpPreview(tester, controller, const Size(390, 844));

      _expectPreviewBox(
        tester,
        ratio: landscapeBoxOfALandscapeFrame,
        unconstrained: const Size(1280, 720),
      );
    });

    testWidgets('locked and paused orientations override the device', (
      tester,
    ) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      tester.view.physicalSize = const Size(390, 844);

      final controller = await _initializeCamera(
        platform,
        previewSize: const Size(1280, 720),
        device: DeviceOrientation.landscapeLeft,
      );
      await _pumpPreview(tester, controller, const Size(390, 844));
      _expectPreviewBox(
        tester,
        ratio: landscapeBoxOfALandscapeFrame,
        unconstrained: const Size(1280, 720),
      );

      // Locking the capture in portrait while the device stays landscape:
      // the package flips the box, and the box here must already match.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await tester.pump();
      expect(
        _cameraPreviewAspectRatio(tester),
        closeTo(portraitBoxOfALandscapeFrame, 1e-9),
      );

      // Unlocking hands the decision back to the (still landscape) device.
      await controller.unlockCaptureOrientation();
      await tester.pump();
      expect(
        _cameraPreviewAspectRatio(tester),
        closeTo(landscapeBoxOfALandscapeFrame, 1e-9),
      );

      // A paused preview freezes the orientation it was paused at, so a later
      // device rotation must no longer move the box.
      await platform.pushOrientation(DeviceOrientation.portraitUp);
      await tester.pump();
      await controller.pausePreview();
      await tester.pump();
      expect(
        _cameraPreviewAspectRatio(tester),
        closeTo(portraitBoxOfALandscapeFrame, 1e-9),
      );
      await platform.pushOrientation(DeviceOrientation.landscapeRight);
      await tester.pump();
      expect(
        _cameraPreviewAspectRatio(tester),
        closeTo(portraitBoxOfALandscapeFrame, 1e-9),
      );
    });

    testWidgets('a device rotation without a resize rebuilds the footprint', (
      tester,
    ) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      // Stage Manager: a window whose size does not follow the device.
      tester.view.physicalSize = const Size(390, 844);

      final controller = await _initializeCamera(
        platform,
        previewSize: const Size(1280, 720),
        device: DeviceOrientation.portraitUp,
      );
      await _pumpPreview(tester, controller, const Size(390, 844));
      _expectPreviewBox(
        tester,
        ratio: portraitBoxOfALandscapeFrame,
        unconstrained: const Size(1280, 720),
      );

      // Only the camera value changes; the window keeps its size.
      await platform.pushOrientation(DeviceOrientation.landscapeLeft);
      await tester.pump();

      _expectPreviewBox(
        tester,
        ratio: landscapeBoxOfALandscapeFrame,
        unconstrained: const Size(1280, 720),
      );
    });

    testWidgets('recording a different orientation rebuilds the footprint', (
      tester,
    ) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      tester.view.physicalSize = const Size(390, 844);

      final controller = await _initializeCamera(
        platform,
        previewSize: const Size(1280, 720),
        device: DeviceOrientation.portraitUp,
      );
      await _pumpPreview(tester, controller, const Size(390, 844));
      _expectPreviewBox(
        tester,
        ratio: portraitBoxOfALandscapeFrame,
        unconstrained: const Size(1280, 720),
      );

      // The device turned while the window stayed put; starting the recording
      // freezes the frame at that orientation.
      await platform.pushOrientation(DeviceOrientation.landscapeRight);
      await tester.pump();
      await controller.startVideoRecording();
      await tester.pump();

      _expectPreviewBox(
        tester,
        ratio: landscapeBoxOfALandscapeFrame,
        unconstrained: const Size(1280, 720),
      );

      // Stopping the recording drops back to the device orientation.
      await controller.stopVideoRecording();
      await tester.pump();
      expect(
        _cameraPreviewAspectRatio(tester),
        closeTo(landscapeBoxOfALandscapeFrame, 1e-9),
      );
    });
  });
}

CameraValue _value({
  Size? previewSize = const Size(1280, 720),
  DeviceOrientation device = DeviceOrientation.portraitUp,
  DeviceOrientation? locked,
  DeviceOrientation? paused,
  DeviceOrientation? recording,
  bool isRecording = false,
}) {
  return CameraValue(
    isInitialized: true,
    isRecordingVideo: isRecording,
    isTakingPicture: false,
    isStreamingImages: false,
    isRecordingPaused: false,
    flashMode: FlashMode.auto,
    exposureMode: ExposureMode.auto,
    focusMode: FocusMode.auto,
    exposurePointSupported: false,
    focusPointSupported: false,
    description: const CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    previewSize: previewSize,
    deviceOrientation: device,
    lockedCaptureOrientation: locked,
    recordingOrientation: recording,
    previewPauseOrientation: paused,
  );
}

Future<CameraController> _initializeCamera(
  _FakeCameraPlatform platform, {
  required Size previewSize,
  required DeviceOrientation device,
}) async {
  platform.previewSize = previewSize;
  platform.deviceOrientation = device;
  final controller = CameraController(
    const CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    ResolutionPreset.high,
  );
  platform.controller = controller;
  // A fake that stops completing initialization must fail fast, not hang the
  // file for the runner's whole timeout.
  await controller.initialize().timeout(const Duration(seconds: 10));
  // The plugin reports the device orientation out of band, not in the init
  // event; without this the controller stays at portraitUp.
  await platform.pushOrientation(device);
  return controller;
}

/// Hosts the production [VideoNotePreviewBox] in a window of [window].
Future<void> _pumpPreview(
  WidgetTester tester,
  CameraController controller,
  Size window,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: window.width,
          height: window.height,
          child: VideoNotePreviewBox(controller: controller, viewport: window),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _cameraPreviewAspectRatio(WidgetTester tester) {
  final preview = find.byType(CameraPreview);
  expect(preview, findsOneWidget);
  return tester.getSize(preview).aspectRatio;
}

/// Asserts on the real [CameraPreview] box the recorder renders, not on the
/// helper's own number: first that it agrees with the package, then that its
/// layout is the package's own shape.
void _expectPreviewBox(
  WidgetTester tester, {
  required double ratio,
  required Size unconstrained,
}) {
  expect(_cameraPreviewAspectRatio(tester), closeTo(ratio, 1e-9));

  // Inside the FittedBox the preview box is laid out the way the package lays
  // it out: width/height when the applicable orientation is landscape, the
  // reciprocal otherwise, with no window influence on that shape.
  final box = tester.renderObject<RenderBox>(find.byType(CameraPreview));
  expect(
    box.getDryLayout(BoxConstraints.loose(unconstrained)).aspectRatio,
    closeTo(ratio, 1e-9),
  );
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
