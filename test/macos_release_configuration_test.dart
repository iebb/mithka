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

  test('macOS TestFlight is owned by Xcode Cloud', () {
    expect(
      File('.github/workflows/macos-testflight.yml').existsSync(),
      isFalse,
    );

    final dispatcher = File('ci_scripts/ci_post_clone.sh').readAsStringSync();
    expect(dispatcher, contains(r'exec "$SCRIPT_DIR/macos_post_clone.sh"'));
    expect(dispatcher, contains('MITHKA_CI_PLATFORM'));
  });

  test('Xcode Cloud downloads and verifies pinned universal macOS TDLib', () {
    final script = File('ci_scripts/macos_post_clone.sh').readAsStringSync();

    expect(script, contains('tdlib-1.8.66-1b08c83bc078-rebuild-29623073124-1'));
    expect(script, contains('tdjson-macos-universal.zip'));
    expect(
      script,
      contains(
        '9520190747fe1f855d8445996cf92f1a57fca303a15cd3ec7c0849d9a49aaabc',
      ),
    );
    expect(
      script,
      contains(
        'd543b42be66306dded64b55b980ec8cf88ae1d43bebf019cc3fa0ca4bb7e5482',
      ),
    );
    expect(script, contains('shasum -a 256 -c -'));
    expect(script, contains('unzip -Z1'));
    expect(script, contains('arm64 x86_64'));
    expect(script, contains('_td_mithka_export_session_string'));
    expect(script, isNot(contains('scripts/build-tdjson-desktop.sh')));
    expect(script, isNot(contains('brew install cmake ninja')));
  });
}
