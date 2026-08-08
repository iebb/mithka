import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/inline_video_autoplay.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  group('parsed video size', () {
    ChatMessage? parse(Map<String, dynamic> content) => TDParse.message({
      '@type': 'message',
      'id': 900,
      'date': 1,
      'content': content,
    });

    test('a video message carries the byte size the gate needs', () {
      final parsed = parse({
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': ''},
        'video': {
          '@type': 'video',
          'duration': 4,
          'width': 480,
          'height': 848,
          'video': {'@type': 'file', 'id': 402, 'size': 1234567},
        },
      });

      expect(parsed?.videoFileSize, 1234567);
      expect(
        shouldAutoplayVideoInline(
          contentType: parsed!.contentType,
          fileSizeBytes: parsed.videoFileSize,
          width: parsed.imageWidth,
          height: parsed.imageHeight,
        ),
        isTrue,
      );
    });

    test('an undownloaded video falls back to the expected size', () {
      final parsed = parse({
        '@type': 'messageVideo',
        'caption': {'@type': 'formattedText', 'text': ''},
        'video': {
          '@type': 'video',
          'duration': 4,
          'width': 480,
          'height': 848,
          'video': {'@type': 'file', 'id': 402, 'expected_size': 2048},
        },
      });

      expect(parsed?.videoFileSize, 2048);
    });

    test('a video message note carries its byte size', () {
      final parsed = parse({
        '@type': 'messageVideoNote',
        'video_note': {
          '@type': 'videoNote',
          'duration': 6,
          'length': 384,
          'video': {'@type': 'file', 'id': 405, 'size': 700000},
        },
      });

      expect(parsed?.videoFileSize, 700000);
    });
  });

  group('inline video autoplay', () {
    test('animations always play in place', () {
      expect(
        shouldAutoplayVideoInline(
          contentType: 'messageAnimation',
          fileSizeBytes: 40 * 1024 * 1024,
          width: 480,
          height: 270,
        ),
        isTrue,
      );
    });

    test('a short video within the budget plays in place', () {
      expect(
        shouldAutoplayVideoInline(
          contentType: 'messageVideo',
          fileSizeBytes: 3 * 1024 * 1024,
          width: 1080,
          height: 1920,
        ),
        isTrue,
      );
    });

    test('video messages play in place', () {
      expect(
        shouldAutoplayVideoInline(
          contentType: 'messageVideoNote',
          fileSizeBytes: 900 * 1024,
          width: 384,
          height: 384,
        ),
        isTrue,
      );
    });

    test('a video past the download budget keeps its thumbnail', () {
      expect(
        shouldAutoplayVideoInline(
          contentType: 'messageVideo',
          fileSizeBytes: inlineVideoAutoplayMaxBytes + 1,
          width: 640,
          height: 360,
        ),
        isFalse,
      );
    });

    test('a frame past the inline decode budget keeps its thumbnail', () {
      expect(
        shouldAutoplayVideoInline(
          contentType: 'messageVideo',
          fileSizeBytes: 2 * 1024 * 1024,
          width: 3840,
          height: 2160,
        ),
        isFalse,
      );
    });

    test('an unknown size keeps its thumbnail', () {
      expect(
        shouldAutoplayVideoInline(
          contentType: 'messageVideo',
          fileSizeBytes: null,
          width: 640,
          height: 360,
        ),
        isFalse,
      );
    });

    test('unknown dimensions still autoplay within the size budget', () {
      expect(
        shouldAutoplayVideoInline(
          contentType: 'messageVideo',
          fileSizeBytes: 1024 * 1024,
          width: null,
          height: null,
        ),
        isTrue,
      );
    });

    test('other content never autoplays', () {
      expect(
        shouldAutoplayVideoInline(
          contentType: 'messagePhoto',
          fileSizeBytes: 1024,
          width: 100,
          height: 100,
        ),
        isFalse,
      );
    });
  });
}
