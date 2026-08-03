import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS app bundle identifier is visible to Xcode Cloud', () {
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    const bundleSetting = 'PRODUCT_BUNDLE_IDENTIFIER = ad.neko.mithka';
    expect(appInfo, contains(bundleSetting));
    expect(
      RegExp('${RegExp.escape(bundleSetting)};').allMatches(project),
      hasLength(3),
      reason:
          'Runner Debug, Profile, and Release must expose the bundle ID '
          'directly for Xcode Cloud discovery.',
    );
  });

  test('macOS TestFlight uploads master pushes as internal builds', () {
    final workflow = File(
      '.github/workflows/macos-testflight.yml',
    ).readAsStringSync();

    expect(
      workflow,
      contains('on:\n  push:\n    branches: [master]\n  workflow_dispatch:'),
    );
    expect(
      workflow,
      contains(r'if [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]; then'),
    );
    expect(workflow, contains('internal_only=true'));
    expect(
      RegExp(
        r'INTERNAL_ONLY: \$\{\{ steps\.release\.outputs\.internal_only \}\}',
      ).allMatches(workflow),
      hasLength(2),
    );
    expect(
      RegExp(
        r'\$\{\{ inputs\.internal_testflight_only \}\}',
      ).allMatches(workflow),
      hasLength(1),
      reason: 'the dispatch-only input must only seed the normalized output',
    );
  });
}
