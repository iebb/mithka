import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all Android variants inherit the APK install permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    expect(
      manifest.readAsStringSync(),
      contains(
        '<uses-permission '
        'android:name="android.permission.REQUEST_INSTALL_PACKAGES" />',
      ),
    );
  });
}
