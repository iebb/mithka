import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
// The fake platform is the published camera interface the `camera` package
// itself talks to, not a new dependency.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/composer/video_note_crop_service.dart';
import 'package:mithka/chat/composer/video_note_recorder_view.dart';
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

  testWidgets(
    'switching from selfie to rear uses the wide lens at 1× and enables zoom and focus',
    (tester) async {
      final previous = CameraPlatform.instance;
      final platform = _FakeCameraPlatform()
        ..cameras = const [
          CameraDescription(
            name: 'selfie',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 90,
          ),
          CameraDescription(
            name: 'tele',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
            lensType: CameraLensType.telephoto,
          ),
          CameraDescription(
            name: 'main',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
            lensType: CameraLensType.wide,
          ),
        ];
      CameraPlatform.instance = platform;
      addTearDown(() => CameraPlatform.instance = previous);
      await tester.pumpWidget(const MaterialApp(home: VideoNoteRecorderView()));
      await tester.pumpAndSettle();
      expect(platform.activeCamera.name, 'selfie');
      expect(find.text('2×'), findsNothing);
      final flip = _roundButton(
        AppStrings.t(AppStringKeys.videoNoteRecorderSwitchCamera),
      );
      await tester.tap(flip);
      await tester.pumpAndSettle();
      expect(platform.activeCamera.name, 'main');
      expect(platform.focusMode, FocusMode.auto);
      expect(platform.appliedZoom, [1]);
      await tester.tap(find.text('2×'));
      await tester.pumpAndSettle();
      expect(platform.appliedZoom.last, 2);
      await tester.tapAt(tester.getCenter(find.byType(VideoNotePreviewBox)));
      await tester.pump();
      expect(platform.focusPoint!.x, closeTo(0.5, 0.001));
      expect(platform.focusPoint!.y, closeTo(0.5, 0.001));
      await tester.tap(flip);
      await tester.pumpAndSettle();
      expect(find.text('2×'), findsNothing);
      await tester.tap(flip);
      await tester.pumpAndSettle();
      expect(platform.appliedZoom, [1, 2, 1]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'untyped Camera2 IDs prefer the conventional primary rear over the first rear',
    (tester) async {
      final previous = CameraPlatform.instance;
      final platform = _FakeCameraPlatform()
        ..cameras = const [
          CameraDescription(
            name: '2',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
          ),
          CameraDescription(
            name: '1',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 90,
          ),
          CameraDescription(
            name: '0',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
          ),
        ];
      CameraPlatform.instance = platform;
      addTearDown(() => CameraPlatform.instance = previous);
      await tester.pumpWidget(const MaterialApp(home: VideoNoteRecorderView()));
      await tester.pumpAndSettle();
      expect(platform.activeCamera.name, '1');
      await tester.tap(
        _roundButton(AppStrings.t(AppStringKeys.videoNoteRecorderSwitchCamera)),
      );
      await tester.pumpAndSettle();
      expect(platform.activeCamera.name, '0');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> openRecorder(
    WidgetTester tester,
    _FakeCameraPlatform platform,
  ) async {
    final previous = CameraPlatform.instance;
    CameraPlatform.instance = platform;
    addTearDown(() => CameraPlatform.instance = previous);
    await tester.pumpWidget(const MaterialApp(home: VideoNoteRecorderView()));
    await tester.pump();
  }

  Future<void> closeRecording(
    WidgetTester tester,
    _FakeCameraPlatform platform,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 100 && platform.disposals == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(platform.disposals, 1);
  }

  testWidgets(
    'rear-only startup picks wide; zoom and metering during recording leave capture running',
    (tester) async {
      final platform = _FakeCameraPlatform()
        ..min = 0.55
        ..max = 2.25
        ..rejectZoom = 2.25
        ..cameras = const [
          CameraDescription(
            name: 'ultra',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
            lensType: CameraLensType.ultraWide,
          ),
          CameraDescription(
            name: 'main',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
            lensType: CameraLensType.wide,
          ),
        ];
      await openRecorder(tester, platform);
      expect(platform.activeCamera.name, 'main');
      expect(platform.exposureMode, ExposureMode.auto);
      expect(find.text('0.55×'), findsOneWidget);
      expect(find.text('0.5×'), findsNothing);
      expect(find.text('3×'), findsNothing);
      final shutter = find.byKey(const ValueKey('videoNoteRecordButton'));
      await tester.tap(shutter);
      await tester.pump();
      await tester.tap(find.text('2×'));
      await tester.pump();
      await tester.tap(find.text('2.25×'));
      await tester.pump();
      final selected = find.ancestor(
        of: find.text('2×'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
      );
      expect(selected, findsOneWidget);
      expect(platform.appliedZoom, [1, 2]);
      expect(find.text('2.25×'), findsNothing);
      final footprint = tester.getRect(
        find.byKey(const ValueKey('videoNotePreviewFootprint')),
      );
      final point = footprint.center + const Offset(35, -25);
      await tester.tapAt(point);
      await tester.pump();
      expect(
        platform.focusPoint!.x,
        closeTo((point.dx - footprint.left) / footprint.width, 0.001),
      );
      expect(
        platform.focusPoint!.y,
        closeTo((point.dy - footprint.top) / footprint.height, 0.001),
      );
      expect(platform.starts, 1);
      expect(platform.stopCalls, 0);
      expect(
        tester
            .widget<CameraPreview>(find.byType(CameraPreview))
            .controller
            .value
            .isRecordingVideo,
        isTrue,
      );
      await closeRecording(tester, platform);
    },
  );

  testWidgets(
    'unavailable focus and invalid zoom range still permit recording',
    (tester) async {
      final platform = _FakeCameraPlatform()
        ..min = double.nan
        ..supportsPoint = false
        ..rejectAutoFocus = true;
      await openRecorder(tester, platform);
      expect(platform.exposureMode, ExposureMode.auto);
      await tester.tapAt(tester.getCenter(find.byType(CameraPreview)));
      expect(platform.focusPoint, isNull);
      expect(find.text('1×'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('videoNoteRecordButton')));
      await tester.pump();
      expect(platform.starts, 1);
      await closeRecording(tester, platform);
    },
  );

  testWidgets(
    'releasing a long press during a delayed start still stops the capture',
    (tester) async {
      final start = Completer<void>();
      final stop = Completer<XFile>();
      final platform = _FakeCameraPlatform()
        ..startGate = start
        ..stoppedVideo = stop.future;
      await openRecorder(tester, platform);
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('videoNoteRecordButton'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(platform.starts, 1);
      await press.up();
      await tester.pump();
      start.complete();
      await tester.pump();
      expect(platform.stopCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      stop.complete(XFile('unused-long-press-fixture.mp4'));
      await tester.pump();
      expect(platform.disposals, 1);
    },
  );

  testWidgets('a pending start is single-flight and is reclaimed on exit', (
    tester,
  ) async {
    final gate = Completer<void>();
    final platform = _FakeCameraPlatform()..startGate = gate;
    final dir = Directory.systemTemp.createTempSync('chat-camera-start-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/abandoned.mp4')..writeAsBytesSync([1]);
    platform.stoppedVideo = Future.value(XFile(file.path));
    await openRecorder(tester, platform);
    final shutter = find.byKey(const ValueKey('videoNoteRecordButton'));
    await tester.tap(shutter);
    await tester.tap(shutter);
    await tester.pump();
    expect(platform.starts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(platform.disposals, 0);
    gate.complete();
    for (int i = 0; i < 100 && platform.disposals == 0; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(platform.stopCalls, 1);
    expect(platform.disposals, 1);
    expect(file.existsSync(), isFalse);
  });

  testWidgets(
    'another recorder waits for the first route to release the device',
    (tester) async {
      final gate = Completer<void>();
      final platform = _FakeCameraPlatform()..disposeGate = gate;
      await openRecorder(tester, platform);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const MaterialApp(home: VideoNoteRecorderView()));
      await tester.pump();
      expect(platform.opens, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(platform.disposals, 1);
      expect(platform.opens, 2);
      expect(find.byType(CameraPreview), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'resume waits for the old camera and skips its stale preparation reply',
    (tester) async {
      final gate = Completer<void>();
      final platform = _FakeCameraPlatform()..prepareGate = gate;
      await openRecorder(tester, platform);
      // A real trip to the background, not a prompt over the app.
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(platform.opens, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(platform.opens, 2);
      expect(platform.exposureCalls, 1);
      expect(platform.disposals, 1);
      expect(find.byType(CameraPreview), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(platform.disposals, 2);
    },
  );

  testWidgets(
    'going back while recording detaches the preview before the camera is released',
    (tester) async {
      final previous = CameraPlatform.instance;
      final platform = _FakeCameraPlatform();
      CameraPlatform.instance = platform;
      addTearDown(() => CameraPlatform.instance = previous);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const SizedBox(key: ValueKey('recorder-home')),
        ),
      );
      unawaited(
        navigator.currentState!.push<VideoNoteCaptureResult>(
          MaterialPageRoute(builder: (_) => const VideoNoteRecorderView()),
        ),
      );
      await tester.pumpAndSettle();
      // A tap starts a locked recording, so the close button would cancel
      // instead of leaving; system Back is what pops the route here.
      await tester.tap(find.byKey(const ValueKey('videoNoteRecordButton')));
      await tester.pump();
      expect(platform.starts, 1);

      navigator.currentState!.pop();
      // The route stays mounted for its reverse transition while the stop and
      // release complete; every frame of it must build without the camera.
      // The release does real file I/O, which only advances inside runAsync.
      for (var frame = 0; frame < 30; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 8));
        expect(tester.takeException(), isNull, reason: 'frame $frame');
      }
      expect(platform.stopCalls, 1);
      expect(platform.disposals, 1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(VideoNoteRecorderView), findsNothing);
    },
  );

  testWidgets(
    'a permission prompt over a starting camera does not open it twice',
    (tester) async {
      final gate = Completer<void>();
      final platform = _FakeCameraPlatform()..prepareGate = gate;
      await openRecorder(tester, platform);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      gate.complete();
      await tester.pumpAndSettle();
      expect(platform.opens, 1);
      expect(platform.disposals, 0);
      expect(find.byType(CameraPreview), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'a camera release that never finishes does not strand the next recorder',
    (tester) async {
      final stuck = Completer<void>();
      final platform = _FakeCameraPlatform()..disposeGate = stuck;
      await openRecorder(tester, platform);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const MaterialApp(home: VideoNoteRecorderView()));
      await tester.pump(const Duration(seconds: 1));
      expect(platform.opens, 1, reason: 'still waiting for the first release');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(platform.opens, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      // Let the stuck release finish so the next test does not inherit it.
      stuck.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'failed preparation releases the camera and displays the reason',
    (tester) async {
      final platform = _FakeCameraPlatform()..failPreparation = true;
      await openRecorder(tester, platform);
      expect(find.textContaining('microphone busy'), findsOneWidget);
      expect(find.byType(CameraPreview), findsNothing);
      expect(platform.disposals, 1);
    },
  );

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
  int opens = 0;
  int disposals = 0;
  int starts = 0;
  ExposureMode? exposureMode;
  int exposureCalls = 0;
  bool rejectAutoFocus = false;
  bool supportsPoint = true;
  double min = 1;
  double? max;
  double? rejectZoom;
  Completer<void>? startGate;
  Completer<void>? prepareGate;
  Completer<void>? disposeGate;
  bool failPreparation = false;

  List<CameraDescription> cameras = const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  late CameraDescription activeCamera;
  final appliedZoom = <double>[];
  FocusMode? focusMode;
  Point<double>? focusPoint;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<double> getMinZoomLevel(int cameraId) async => min;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async =>
      max ?? (activeCamera.lensType == CameraLensType.wide ? 3 : 1);

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {
    if (zoom == rejectZoom) throw CameraException("zoomRejected", null);
    appliedZoom.add(zoom);
  }

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {
    if (rejectAutoFocus) throw CameraException("fixedFocus", null);
    focusMode = mode;
  }

  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {
    exposureCalls++;
    exposureMode = mode;
  }

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {
    focusPoint = point;
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    activeCamera = cameraDescription;
    return ++opens;
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
        supportsPoint,
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
  Future<void> prepareForVideoRecording() async {
    await prepareGate?.future;
    if (failPreparation) throw CameraException("prepare", "microphone busy");
  }

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
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    starts++;
    await startGate?.future;
  }

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
  Future<void> dispose(int cameraId) async {
    await disposeGate?.future;
    disposals++;
  }
}
