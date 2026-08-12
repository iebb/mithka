import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS uses the app-ID Keychain group without a custom group', () {
    for (final path in [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final entitlements = File(path).readAsStringSync();
      expect(
        entitlements,
        isNot(contains('<key>keychain-access-groups</key>')),
        reason:
            '$path should use the signed app identifier as the common iOS and '
            'macOS Keychain group, while remaining compatible with local '
            'ad-hoc builds.',
      );
    }
  });

  test('Apple targets share one app identifier for iCloud Keychain', () {
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final macProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    const bundleSetting = 'PRODUCT_BUNDLE_IDENTIFIER = ad.neko.mithka';
    expect(appInfo, contains(bundleSetting));
    expect(
      RegExp('${RegExp.escape(bundleSetting)};').allMatches(macProject),
      hasLength(3),
      reason:
          'Runner Debug, Profile, and Release must expose the bundle ID '
          'directly for Xcode Cloud discovery.',
    );
    expect(
      RegExp('${RegExp.escape(bundleSetting)};').allMatches(iosProject),
      hasLength(3),
      reason:
          'The iOS and macOS Runner targets must resolve to the same signed '
          'application identifier so their synchronizable items can meet in '
          'one default Keychain access group.',
    );
  });

  test('macOS TestFlight is owned by GitHub Actions', () {
    final workflow = File(
      '.github/workflows/macos-testflight.yml',
    ).readAsStringSync();
    expect(workflow, contains('sh ci_scripts/macos_post_clone.sh'));

    // Keep the old hook valid for a reversible Xcode Cloud rollback.
    final workspaceHook = File(
      'macos/ci_scripts/ci_post_clone.sh',
    ).readAsStringSync();
    expect(
      workspaceHook,
      contains(r'exec "$SCRIPT_DIR/../../ci_scripts/macos_post_clone.sh"'),
    );
  });

  test('Apple setup delegates macOS TDJSON to the shared wrapper', () {
    final script = File('ci_scripts/macos_post_clone.sh').readAsStringSync();

    expect(
      script,
      contains(
        r'"$REPO/scripts/build-tdjson-desktop.sh" macos '
        'native-libs/libtdjson.dylib',
      ),
    );
    expect(script, isNot(contains('TDJSON_RELEASE_TAG=')));
    expect(script, isNot(contains('TDJSON_ARCHIVE_SHA256=')));
    expect(script, isNot(contains('TDJSON_BINARY_SHA256=')));
    expect(script, isNot(contains('TDJSON_ASSET_URL=')));
    expect(script, isNot(contains('tdjson-macos-universal.zip')));
    expect(script, isNot(contains('shasum -a 256 -c -')));
    expect(script, isNot(contains('unzip -Z1')));
    expect(script, contains('ensure_declared_plugin_resources'));
    expect(script, contains(r'for package_root in "$packages_root"/*'));
    expect(script, contains('grep -Fq \'.process("Resources")\''));
    expect(script, contains(r'for target_root in "$package_root"/Sources/*'));
    expect(script, contains(r'mkdir -p "$target_root/Resources"'));
    expect(script, contains('xcodebuild -resolvePackageDependencies'));
    expect(script, contains('-onlyUsePackageVersionsFromResolvedFile'));
    expect(script, contains('CI_DERIVED_DATA_PATH'));
    expect(script, contains(r'-derivedDataPath "$XCODE_DERIVED_DATA_PATH"'));
    expect(
      script,
      contains(
        'macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
      ),
    );
    expect(script, isNot(contains('brew install cmake ninja')));
  });

  test('macOS workspace pins packages used by Xcode Cloud', () {
    final lock = File(
      'macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
    );
    expect(lock.existsSync(), isTrue);

    final resolved =
        jsonDecode(lock.readAsStringSync()) as Map<String, Object?>;
    final pins = resolved['pins']! as List<Object?>;
    final versions = <String, String>{
      for (final pin in pins.cast<Map<String, Object?>>())
        pin['identity']! as String:
            (pin['state']! as Map<String, Object?>)['version']! as String,
    };

    expect(versions['firebase-ios-sdk'], '12.17.0');
    expect(versions['sentry-cocoa'], '8.58.4');
  });
}
