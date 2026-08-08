import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media_preview_geometry.dart';

void main() {
  group('Telegram Desktop media preview geometry', () {
    test('caps landscape and portrait previews inside 430 logical pixels', () {
      final landscape = telegramDesktopMediaPreviewGeometry(
        sourceWidth: 1600,
        sourceHeight: 900,
        availableWidth: 1200,
      );
      final portrait = telegramDesktopMediaPreviewGeometry(
        sourceWidth: 900,
        sourceHeight: 1600,
        availableWidth: 1200,
      );

      expect(landscape.contentSize.width, 430);
      expect(landscape.contentSize.height, closeTo(241.875, 0.001));
      expect(landscape.frameSize, landscape.contentSize);
      expect(portrait.contentSize.width, closeTo(241.875, 0.001));
      expect(portrait.contentSize.height, 430);
      expect(portrait.frameSize, portrait.contentSize);
    });

    test('does not enlarge an image beyond its source dimensions', () {
      final geometry = telegramDesktopMediaPreviewGeometry(
        sourceWidth: 320,
        sourceHeight: 180,
        availableWidth: 1000,
      );

      expect(geometry.contentSize.width, 320);
      expect(geometry.contentSize.height, 180);
      expect(geometry.needsBlurredFill, isFalse);
    });

    test('uses a stable 100 pixel frame for tiny media', () {
      final geometry = telegramDesktopMediaPreviewGeometry(
        sourceWidth: 64,
        sourceHeight: 48,
        availableWidth: 1000,
      );

      expect(geometry.contentSize.width, 64);
      expect(geometry.contentSize.height, 48);
      expect(geometry.frameSize.width, 100);
      expect(geometry.frameSize.height, 100);
      expect(geometry.needsBlurredFill, isTrue);
    });

    test('shrinks again when the chat pane is narrower than the media cap', () {
      final geometry = telegramDesktopMediaPreviewGeometry(
        sourceWidth: 1600,
        sourceHeight: 900,
        availableWidth: 240,
      );

      expect(geometry.contentSize.width, 240);
      expect(geometry.contentSize.height, closeTo(135, 0.001));
      expect(geometry.frameSize, geometry.contentSize);
    });

    test('portrait media stays inside the shorter media height', () {
      final portrait = telegramDesktopMediaPreviewGeometry(
        sourceWidth: 1080,
        sourceHeight: 1920,
        availableWidth: 1200,
        maxHeight: telegramChatMediaPreviewMaxHeight,
      );

      expect(portrait.contentSize.height, 320);
      expect(portrait.contentSize.width, closeTo(180, 0.001));
      expect(portrait.frameSize, portrait.contentSize);
    });

    test('landscape media keeps the full width of the media box', () {
      final landscape = telegramDesktopMediaPreviewGeometry(
        sourceWidth: 1920,
        sourceHeight: 1080,
        availableWidth: 1200,
        maxHeight: telegramChatMediaPreviewMaxHeight,
      );

      expect(landscape.contentSize.width, 430);
      expect(landscape.contentSize.height, closeTo(241.875, 0.001));
    });

    test('the height cap also bounds an unknown-size placeholder', () {
      final geometry = telegramDesktopMediaPreviewGeometry(
        sourceWidth: null,
        sourceHeight: null,
        availableWidth: double.infinity,
        maxHeight: telegramChatMediaPreviewMaxHeight,
      );

      expect(geometry.contentSize.width, 430);
      expect(geometry.contentSize.height, 320);
    });

    test('unknown dimensions use one bounded square placeholder', () {
      final geometry = telegramDesktopMediaPreviewGeometry(
        sourceWidth: null,
        sourceHeight: null,
        availableWidth: double.infinity,
      );

      expect(geometry.contentSize.width, 430);
      expect(geometry.contentSize.height, 430);
      expect(geometry.frameSize, geometry.contentSize);
    });
  });
}
