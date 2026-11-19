import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/security/sensitive_clipboard.dart';

void main() {
  test(
    'clears an unchanged sensitive clipboard after the requested delay',
    () async {
      String? clipboard;
      Duration? delay;
      late Future<void> Function() scheduled;
      final sensitiveClipboard = SensitiveClipboard(
        read: () async => clipboard,
        write: (value) async => clipboard = value,
        schedule: (value, callback) {
          delay = value;
          scheduled = callback;
        },
      );

      await sensitiveClipboard.copy('authorization-session');

      expect(clipboard, 'authorization-session');
      expect(delay, const Duration(minutes: 1));
      await scheduled();
      expect(clipboard, isEmpty);
    },
  );

  test('never overwrites clipboard content copied later by the user', () async {
    String? clipboard;
    late Future<void> Function() scheduled;
    final sensitiveClipboard = SensitiveClipboard(
      read: () async => clipboard,
      write: (value) async => clipboard = value,
      schedule: (_, callback) => scheduled = callback,
    );

    await sensitiveClipboard.copy('authorization-session');
    clipboard = 'new clipboard content';
    await scheduled();

    expect(clipboard, 'new clipboard content');
  });

  test(
    'replaces any pending default timer when copying a new secret',
    () async {
      String? clipboard;
      var reads = 0;
      final sensitiveClipboard = SensitiveClipboard(
        read: () async {
          reads++;
          return clipboard;
        },
        write: (value) async => clipboard = value,
      );
      addTearDown(sensitiveClipboard.cancelPendingClear);

      await sensitiveClipboard.copy(
        'first-secret',
        clearAfter: const Duration(milliseconds: 25),
      );
      await sensitiveClipboard.copy(
        'second-secret',
        clearAfter: const Duration(milliseconds: 80),
      );
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(reads, 0);
      expect(clipboard, 'second-secret');

      await Future<void>.delayed(const Duration(milliseconds: 55));
      expect(reads, 1);
      expect(clipboard, isEmpty);
    },
  );
}
