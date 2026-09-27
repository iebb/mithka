import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/app_camera_view.dart';
import 'package:mithka/theme/app_theme.dart';

const _camera = CameraDescription(
  name: 'rear',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 0,
);

void main() {
  test('camera retries after returning from permission settings', () {
    expect(appCameraShouldRetryOnResume(recording: false), isTrue);
    expect(appCameraShouldRetryOnResume(recording: true), isFalse);
  });

  for (final throws in [false, true]) {
    testWidgets('resume retries camera enumeration (initial error: $throws)', (
      tester,
    ) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: AppCameraView(
            allowVideo: false,
            allowGallery: false,
            availableCamerasForTesting: () async {
              if (++attempts == 1) {
                if (throws) throw CameraException('unavailable', 'retry later');
                return [];
              }
              return [_camera];
            },
            controllerForTesting: _PreviewController.new,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-preview')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final allowVideo in [false, true]) {
    testWidgets('microphone is requested only for video ($allowVideo)', (
      tester,
    ) async {
      bool? enableAudio;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: AppCameraView(
            allowVideo: allowVideo,
            availableCamerasForTesting: () async => [_camera],
            controllerForTesting: (camera, audio) {
              enableAudio = audio;
              return _PreviewController(camera, audio);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(enableAudio, allowVideo);
      expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('resume replaces a controller that failed permission checks', (
    tester,
  ) async {
    var controllers = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: AppCameraView(
          availableCamerasForTesting: () async => [_camera],
          controllerForTesting: (camera, audio) =>
              _PreviewController(camera, audio, denyAccess: ++controllers == 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('camera-preview')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controllers, 2);
    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resume does not duplicate pending camera enumeration', (
    tester,
  ) async {
    final cameras = Completer<List<CameraDescription>>();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: AppCameraView(
          availableCamerasForTesting: () {
            attempts++;
            return cameras.future;
          },
          controllerForTesting: _PreviewController.new,
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    cameras.complete([_camera]);
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('portrait live preview uses the camera preview aspect ratio', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: AppCameraView(
          availableCamerasForTesting: () async => [_camera],
          controllerForTesting: _PreviewController.new,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final preview = tester.getSize(find.byType(CameraPreview));
    expect(preview.width / preview.height, closeTo(480 / 640, 0.001));
    expect(preview.width, closeTo(374, 0.001));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _PreviewController extends CameraController {
  _PreviewController(
    CameraDescription camera,
    bool enableAudio, {
    this.denyAccess = false,
  }) : super(camera, ResolutionPreset.high, enableAudio: enableAudio);

  final bool denyAccess;

  @override
  Future<void> initialize() async {
    if (denyAccess) throw CameraException('CameraAccessDenied', 'test');
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(640, 480),
    );
  }

  @override
  Widget buildPreview() => const SizedBox(key: ValueKey('camera-preview'));
}
