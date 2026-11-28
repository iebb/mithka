import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/desktop/desktop_video_window_actions.dart';

void main() {
  test('capabilities round-trip and reject malformed payloads', () {
    const both = DesktopVideoWindowCapabilities(canSave: true, canShare: true);
    final decoded = DesktopVideoWindowCapabilities.fromJson(both.toJson());
    expect(decoded.canSave, isTrue);
    expect(decoded.canShare, isTrue);

    for (final malformed in <Object?>[
      null,
      'save',
      const {'save': 'yes', 'share': 1},
    ]) {
      final parsed = DesktopVideoWindowCapabilities.fromJson(malformed);
      expect(parsed.any, isFalse, reason: '$malformed');
    }
  });

  test('action results keep only non-blank messages', () {
    final saved = DesktopVideoWindowActionResult.fromJson(
      const DesktopVideoWindowActionResult(
        ok: true,
        message: 'Saved to Downloads',
      ).toJson(),
    );
    expect(saved.ok, isTrue);
    expect(saved.message, 'Saved to Downloads');

    final blank = DesktopVideoWindowActionResult.fromJson(const {
      'ok': true,
      'message': '  ',
    });
    expect(blank.message, isNull);

    final missing = DesktopVideoWindowActionResult.fromJson(null);
    expect(missing.ok, isFalse);
    expect(missing.message, isNull);
  });
}
