import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mithka/platform/animated_avatar_preparer.dart';
import 'package:video_player/video_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('animated GIF becomes a square playable profile video', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'mithka-avatar-test-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final first = _stripedFrame(
      top: image.ColorRgb8(255, 0, 0),
      bottom: image.ColorRgb8(0, 0, 255),
    );
    final second = _stripedFrame(
      top: image.ColorRgb8(0, 255, 0),
      bottom: image.ColorRgb8(255, 255, 0),
    );
    final encoder = image.GifEncoder()
      ..addFrame(first, duration: 120)
      ..addFrame(second, duration: 120);
    final source = File('${directory.path}/orientation.gif');
    await source.writeAsBytes(encoder.finish()!, flush: true);

    final prepared = await AnimatedAvatarPreparer.prepare(
      XFile(source.path, mimeType: 'image/gif'),
      crop: const AnimatedAvatarCrop(
        left: 0,
        top: 1 / 6,
        width: 1,
        height: 2 / 3,
      ),
    );
    final output = File(prepared.path);
    expect(await output.exists(), isTrue);
    expect(await output.length(), greaterThan(0));

    final controller = VideoPlayerController.file(output);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.seekTo(Duration.zero);
    await controller.pause();
    expect(controller.value.size.width, controller.value.size.height);
    expect(controller.value.duration, greaterThan(Duration.zero));

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: Center(
            child: SizedBox.square(
              dimension: 160,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final screenshot = image.decodePng(
      Uint8List.fromList(
        await binding.takeScreenshot('animated-avatar-orientation'),
      ),
    )!;
    final centerX = screenshot.width ~/ 2;
    final sampleOffset = math.max(8, screenshot.width ~/ 12);
    final topPixel = screenshot.getPixel(
      centerX,
      screenshot.height ~/ 2 - sampleOffset,
    );
    final bottomPixel = screenshot.getPixel(
      centerX,
      screenshot.height ~/ 2 + sampleOffset,
    );
    expect(topPixel.r, greaterThan(topPixel.b));
    expect(bottomPixel.b, greaterThan(bottomPixel.r));

    final croppedVideo = await AnimatedAvatarPreparer.prepare(
      XFile(output.path, mimeType: 'video/mp4'),
      crop: const AnimatedAvatarCrop(
        left: 0.25,
        top: 0.25,
        width: 0.5,
        height: 0.5,
      ),
    );
    final croppedController = VideoPlayerController.file(
      File(croppedVideo.path),
    );
    addTearDown(croppedController.dispose);
    await croppedController.initialize();
    expect(
      croppedController.value.size.width,
      croppedController.value.size.height,
    );
    expect(croppedController.value.duration, greaterThan(Duration.zero));
    // Kept for host-side first-frame extraction during the integration run.
    // ignore: avoid_print
    print('ANIMATED_AVATAR_OUTPUT=${output.path}');
  });
}

image.Image _stripedFrame({
  required image.Color top,
  required image.Color bottom,
}) {
  final frame = image.Image(width: 64, height: 96);
  for (var y = 0; y < frame.height; y++) {
    final color = y < frame.height ~/ 2 ? top : bottom;
    for (var x = 0; x < frame.width; x++) {
      frame.setPixel(x, y, color);
    }
  }
  return frame;
}
