import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_media_window_registry.dart';

void main() {
  group('desktop media window registry', () {
    test('a second open while the first window is still coming up waits', () {
      final registry = DesktopMediaWindowRegistry()..beginOpening(7);

      expect(registry.isOpening(7), isTrue);
      expect(registry.windowFor(7), isNull);
      expect(registry.isOpening(8), isFalse);
    });

    test('the same file id in separate accounts keeps separate windows', () {
      const natuVideo = (accountSlot: 1, videoId: 7);
      const otherAccountVideo = (accountSlot: 2, videoId: 7);
      final registry = DesktopMediaWindowRegistry()
        ..beginOpening(natuVideo)
        ..finishOpening(natuVideo, windowId: 21)
        ..beginOpening(otherAccountVideo)
        ..finishOpening(otherAccountVideo, windowId: 22);

      expect(registry.windowFor(natuVideo), 21);
      expect(registry.windowFor(otherAccountVideo), 22);
    });
  });
}
