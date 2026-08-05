import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/update/update_checker.dart';

void main() {
  const isGooglePlayBuild = bool.fromEnvironment('GOOGLE_PLAY_BUILD');

  test('compile-time distribution flag controls automatic updates', () {
    expect(UpdateChecker.automaticChecksEnabled(), equals(!isGooglePlayBuild));
  });

  test('automatic updates are disabled for Google Play builds', () {
    expect(
      UpdateChecker.automaticChecksEnabled(isGooglePlayBuild: true),
      isFalse,
    );
  });

  test('a manual check follows the same distribution rule', () {
    // supportsManualCheck reads Platform.isAndroid, which is false under the
    // test VM; the point here is that a Play build disables it regardless.
    expect(
      UpdateChecker.automaticChecksEnabled(isGooglePlayBuild: true),
      isFalse,
      reason: 'About must not offer GitHub APKs to a Play install',
    );
    expect(UpdateChecker.supportsManualCheck, isFalse);
  });
}
