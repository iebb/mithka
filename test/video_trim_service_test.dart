import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/video_trim_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mithka/media_editor');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('video trim sends millisecond bounds to native editor', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return '/tmp/trimmed.mp4';
        });
    final result = await VideoTrimService.trim(
      path: '/tmp/source.mov',
      start: const Duration(milliseconds: 1250),
      end: const Duration(milliseconds: 4750),
    );
    expect(result, '/tmp/trimmed.mp4');
    expect(captured?.method, 'trimVideo');
    expect(captured?.arguments, {
      'path': '/tmp/source.mov',
      'startMs': 1250,
      'endMs': 4750,
    });
  });

  test('video trim rejects an empty range before platform work', () {
    expect(
      () => VideoTrimService.trim(
        path: '/tmp/source.mov',
        start: const Duration(seconds: 3),
        end: const Duration(seconds: 3),
      ),
      throwsFormatException,
    );
  });
}
