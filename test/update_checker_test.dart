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
}
