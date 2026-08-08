import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct Android packages request the APK install permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    expect(
      manifest.readAsStringSync(),
      contains(
        '<uses-permission '
        'android:name="android.permission.REQUEST_INSTALL_PACKAGES" />',
      ),
    );
  });

  test('Google Play builds remove the restricted install permission', () {
    final workflow = File(
      '.github/workflows/google-play.yml',
    ).readAsStringSync();
    final preparationScript = File(
      'scripts/prepare-google-play-manifest.sh',
    ).readAsStringSync();

    expect(
      workflow,
      contains('bash scripts/prepare-google-play-manifest.sh'),
    );
    expect(
      preparationScript,
      contains('android.permission.REQUEST_INSTALL_PACKAGES'),
    );
    expect(preparationScript, contains('sed -i.bak'));
  });
}
