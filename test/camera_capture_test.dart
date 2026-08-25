//
//  camera_capture_test.dart
//
//  The composer camera routes by the "save captured photos" preference. The
//  system camera app owns the album copy and cannot be told to skip it, so
//  opting out has to keep the shot away from the system camera entirely.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mithka/chat/media_library_saver.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/media/app_camera_view.dart';
import 'package:mithka/media/camera_capture.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets('opting out captures through the in-app photo-only camera', (
    tester,
  ) async {
    final context = await _pumpHost(tester);

    CameraCapture? capture;
    final pending = captureComposerPhoto(
      context,
      saveToAlbum: false,
    ).then((result) => capture = result);
    await _pumpRoute(tester);

    final camera = tester.widget<AppCameraView>(find.byType(AppCameraView));
    expect(camera.allowVideo, isFalse);
    expect(camera.allowGallery, isFalse);

    _popCamera(tester, AppCameraResult.capture(XFile('/tmp/shot.jpg')));
    await _pumpRoute(tester);
    await pending;

    expect(capture, isNotNull);
    expect(capture!.file.path, '/tmp/shot.jpg');
    expect(
      capture!.albumResult,
      isNull,
      reason: 'nothing is written to the album when the preference is off',
    );
  });

  testWidgets('backing out of the in-app camera captures nothing', (
    tester,
  ) async {
    final context = await _pumpHost(tester);

    var completed = false;
    CameraCapture? capture;
    final pending = captureComposerPhoto(context, saveToAlbum: false).then((
      result,
    ) {
      completed = true;
      capture = result;
    });
    await _pumpRoute(tester);

    _popCamera(tester, null);
    await _pumpRoute(tester);
    await pending;

    expect(completed, isTrue);
    expect(capture, isNull);
  });

  testWidgets('keeping the album copy leaves the system camera in charge', (
    tester,
  ) async {
    final context = await _pumpHost(tester);

    unawaited(captureComposerPhoto(context, saveToAlbum: true));
    await _pumpRoute(tester);

    expect(
      find.byType(AppCameraView),
      findsNothing,
      reason: 'the system camera writes the album copy, so it stays in use',
    );
  });

  test('an album write is only a failure once one was attempted', () {
    final shot = XFile('/tmp/shot.jpg');
    expect(CameraCapture(shot).albumWriteFailed, isFalse);
    expect(
      CameraCapture(
        shot,
        albumResult: MediaLibrarySaveResult.saved,
      ).albumWriteFailed,
      isFalse,
    );
    expect(
      CameraCapture(
        shot,
        albumResult: MediaLibrarySaveResult.permissionDenied,
      ).albumWriteFailed,
      isTrue,
    );
    expect(
      CameraCapture(
        shot,
        albumResult: MediaLibrarySaveResult.failed,
      ).albumWriteFailed,
      isTrue,
    );
  });
}

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate],
      theme: ThemeData(extensions: [AppColors.light]),
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return captured;
}

/// The camera's activity indicator never stops animating, so frames are pumped
/// past the route transition instead of settled.
Future<void> _pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void _popCamera(WidgetTester tester, AppCameraResult? result) {
  Navigator.of(tester.element(find.byType(AppCameraView))).pop(result);
}
