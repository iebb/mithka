import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google Play builds remove the restricted install permission', () {
    final workflow = File(
      '.github/workflows/google-play.yml',
    ).readAsStringSync();
    final preparationScript = File(
      'scripts/prepare-google-play-manifest.sh',
    ).readAsStringSync();

    expect(workflow, contains('bash scripts/prepare-google-play-manifest.sh'));
    expect(
      preparationScript,
      contains('android.permission.REQUEST_INSTALL_PACKAGES'),
    );
    expect(preparationScript, contains('sed -i.bak'));
  });
}
