import 'dart:async';

import 'package:camera/camera.dart';
// The fake platform is the published camera interface the `camera` package
// itself talks to, not a new dependency.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_note_recorder_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

/// Mirrors how the recorder calls the rule: the ratio the preview box itself
/// uses decides the footprint, and the window is only what that box covers.
VideoNotePreviewFootprint footprintFor({
  required Size? previewSize,
  required Size viewport,
  required double aspectRatio,
}) {
  return videoNotePreviewFootprint(
    previewSize: previewSize,
    viewport: viewport,
    aspectRatio: aspectRatio,
  );
}

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

  test('landscape sensor in a portrait iPad viewport is cover-cropped', () {
    final footprint = footprintFor(
      previewSize: const Size(1280, 720),
      viewport: const Size(834, 1194),
      aspectRatio: portraitBoxOfALandscapeFrame,
    );

    expect(footprint.size.aspectRatio, closeTo(9 / 16, 1e-9));
    expect(footprint.coverCropped, isTrue);
  });

  test('landscape sensor in a landscape iPad viewport keeps 16:9', () {
    final footprint = footprintFor(
      previewSize: const Size(1280, 720),
      viewport: const Size(1194, 834),
      aspectRatio: landscapeBoxOfALandscapeFrame,
    );

    expect(footprint.size.aspectRatio, closeTo(16 / 9, 1e-9));
    expect(footprint.coverCropped, isTrue);
  });

  test(
    'a portrait landscape-frame box stays upright in a portrait viewport',
    () {
      final footprint = footprintFor(
        previewSize: const Size(1280, 720),
        viewport: const Size(834, 1194),
        aspectRatio: portraitBoxOfALandscapeFrame,
      );

      expect(footprint.size.aspectRatio, closeTo(9 / 16, 1e-9));
      expect(footprint.coverCropped, isTrue);
    },
  );

  test('a square sensor fills a square viewport and crops elsewhere', () {
    final exact = footprintFor(
      previewSize: const Size(720, 720),
      viewport: const Size(1024, 1024),
      aspectRatio: 1,
    );
    final portrait = footprintFor(
      previewSize: const Size(720, 720),
      viewport: const Size(834, 1194),
      aspectRatio: 1,
    );
    final landscape = footprintFor(
      previewSize: const Size(720, 720),
      viewport: const Size(1194, 834),
      aspectRatio: 1,
    );

    expect(exact.size.aspectRatio, closeTo(1, 1e-9));
    expect(exact.coverCropped, isFalse);
    expect(portrait.size.aspectRatio, closeTo(1, 1e-9));
    expect(portrait.coverCropped, isTrue);
    expect(landscape.size.aspectRatio, closeTo(1, 1e-9));
    expect(landscape.coverCropped, isTrue);
  });

  test('an unknown preview size falls back to the viewport', () {
    final footprint = footprintFor(
      previewSize: null,
      viewport: const Size(834, 1194),
      aspectRatio: 9 / 16,
    );

    expect(footprint.size.aspectRatio, closeTo(834 / 1194, 1e-9));
    expect(footprint.coverCropped, isFalse);
  });

  test('a zero preview size also falls back to the viewport', () {
    final footprint = footprintFor(
      previewSize: Size.zero,
      viewport: const Size(834, 1194),
      aspectRatio: 9 / 16,
    );

    expect(footprint.size, const Size(834, 1194));
    expect(footprint.coverCropped, isFalse);
  });

  test('large iPad viewports cover-fit in both orientations', () {
    final portrait = footprintFor(
      previewSize: const Size(1920, 1080),
      viewport: const Size(1024, 1366),
      aspectRatio: portraitBoxOfALandscapeFrame,
    );
    final landscape = footprintFor(
      previewSize: const Size(1920, 1080),
      viewport: const Size(1366, 1024),
      aspectRatio: landscapeBoxOfALandscapeFrame,
    );

    expect(portrait.size.aspectRatio, closeTo(9 / 16, 1e-9));
    expect(portrait.coverCropped, isTrue);
    expect(landscape.size.aspectRatio, closeTo(16 / 9, 1e-9));
    expect(landscape.coverCropped, isTrue);
  });

  test('a viewport that already matches the box ratio needs no crop', () {
    final footprint = footprintFor(
      previewSize: const Size(1280, 720),
      viewport: const Size(720, 1280),
      aspectRatio: portraitBoxOfALandscapeFrame,
    );

    expect(footprint.size.aspectRatio, closeTo(9 / 16, 1e-9));
    expect(footprint.coverCropped, isFalse);
  });

  test('a phone portrait viewport cover-fills instead of letterboxing', () {
    final footprint = footprintFor(
      previewSize: const Size(1280, 720),
      viewport: const Size(390, 844),
      aspectRatio: portraitBoxOfALandscapeFrame,
    );

    expect(footprint.size.aspectRatio, closeTo(9 / 16, 1e-9));
    expect(footprint.coverCropped, isTrue);
  });

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
    return XFile('video-note-test.mp4');
  }

  @override
  Widget buildPreview(int cameraId) {
    return const Texture(textureId: 7);
  }

  @override
  Future<void> dispose(int cameraId) async {}
}
