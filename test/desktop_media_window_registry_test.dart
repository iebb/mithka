import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop_media_window_registry.dart';

void main() {
  group('desktop media window registry', () {
    test('an unopened media has no window', () {
      final registry = DesktopMediaWindowRegistry();

      expect(registry.windowFor(7), isNull);
      expect(registry.isOpening(7), isFalse);
    });

    test('a repeat open finds the window the media already has', () {
      final registry = DesktopMediaWindowRegistry()
        ..beginOpening(7)
        ..finishOpening(7, windowId: 21);

      expect(registry.windowFor(7), 21);
      expect(registry.isOpening(7), isFalse);
    });

    test('a second open while the first window is still coming up waits', () {
      final registry = DesktopMediaWindowRegistry()..beginOpening(7);

      expect(registry.isOpening(7), isTrue);
      expect(registry.windowFor(7), isNull);
      expect(registry.isOpening(8), isFalse);
    });

    test('a failed open leaves nothing to raise', () {
      final registry = DesktopMediaWindowRegistry()
        ..beginOpening(7)
        ..finishOpening(7);

      expect(registry.isOpening(7), isFalse);
      expect(registry.windowFor(7), isNull);
    });

    test('a closed window stops being a reuse candidate', () {
      final registry = DesktopMediaWindowRegistry()
        ..beginOpening(7)
        ..finishOpening(7, windowId: 21)
        ..forget(7);

      expect(registry.windowFor(7), isNull);
    });

    test('separate media keep separate windows', () {
      final registry = DesktopMediaWindowRegistry()
        ..beginOpening(7)
        ..finishOpening(7, windowId: 21)
        ..beginOpening(8)
        ..finishOpening(8, windowId: 22);

      expect(registry.windowFor(7), 21);
      expect(registry.windowFor(8), 22);
    });
  });
}
