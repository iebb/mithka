import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple CI pins CocoaPods to the lockfile generator', () {
    final iosScript = File(
      'ios/ci_scripts/ci_post_clone.sh',
    ).readAsStringSync();
    final macosScript = File(
      'ci_scripts/macos_post_clone.sh',
    ).readAsStringSync();
    final iosLock = File('ios/Podfile.lock').readAsStringSync();
    final macosLock = File('macos/Podfile.lock').readAsStringSync();

    for (final script in [iosScript, macosScript]) {
      expect(script, contains('COCOAPODS_VERSION="1.17.0"'));
      expect(script, contains('ensure_cocoapods'));
      expect(script, contains('pod --version'));
    }
    for (final lock in [iosLock, macosLock]) {
      expect(lock, endsWith('COCOAPODS: 1.17.0\n'));
    }
  });

  test('Xcode Cloud prefetches the pinned sqlite3 iOS binary safely', () {
    final script = File('ios/ci_scripts/ci_post_clone.sh').readAsStringSync();
    final lock = File('pubspec.lock').readAsStringSync();
    final sqlite3Version = RegExp(
      r'^  sqlite3:\n(?:    .*\n)*?    version: "([^"]+)"$',
      multiLine: true,
    ).firstMatch(lock)?.group(1);

    expect(sqlite3Version, '3.5.2');
    expect(script, contains('SQLITE3_VERSION="3.5.2"'));
    expect(
      script,
      contains(
        r'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${SQLITE3_VERSION}/${SQLITE3_IOS_ARM64_ASSET}',
      ),
    );
    expect(
      script,
      contains(
        'f1bc69a4304a21e472c15f849c34ae46539483cfa7ce901f54175c6d6cc17991',
      ),
    );
    expect(script, contains('libsqlite3.arm64.ios.dylib'));
    expect(
      script,
      contains(
        r'.dart_tool/hooks_runner/shared/sqlite3/build/download-${cache_key}',
      ),
    );
    expect(script, contains('retry 3 5 curl'));
    expect(script, contains('--max-time 120'));
    expect(script, contains('shasum -a 256 -c -'));
    expect(script, contains(r'tmp="${output}.tmp.$$"'));
    expect(script, contains(r'mv "$tmp" "$output"'));
    expect(script, contains('locked_version'));
    expect(script, contains('does not match pinned iOS binary'));
    expect(script, isNot(contains('source: system')));

    final helperStart = script.indexOf('prefetch_sqlite3_ios_arm64()');
    final helperEnd = script.indexOf('\ndecode_base64_to_file()', helperStart);
    final helper = script.substring(helperStart, helperEnd);
    final temporaryChecksum = helper.indexOf(
      r'"$SQLITE3_IOS_ARM64_SHA256" "$tmp"',
    );
    final atomicInstall = helper.indexOf(r'mv "$tmp" "$output"');
    expect(temporaryChecksum, greaterThanOrEqualTo(0));
    expect(atomicInstall, greaterThan(temporaryChecksum));

    final pubGet = script.indexOf('flutter pub get');
    final prefetch = script.lastIndexOf('prefetch_sqlite3_ios_arm64');
    final configure = script.lastIndexOf('flutter_build_ios_config_with_retry');
    expect(pubGet, greaterThanOrEqualTo(0));
    expect(prefetch, greaterThan(pubGet));
    expect(configure, greaterThan(prefetch));
  });

  test('iOS builds install a fresh MDK before linking it', () {
    final script = File('ios/ci_scripts/ci_post_clone.sh').readAsStringSync();
    final workflow = File(
      '.github/workflows/ios-testflight.yml',
    ).readAsStringSync();
    final helper = File('scripts/refresh-apple-mdk.sh').readAsStringSync();

    // libmdk stops playing 44 days after its own build stamp, so the Apple SDK
    // is resolved per build. The refresh must follow pub get (which materialises
    // third_party/fvp) and precede anything that links or packages it.
    final pubGet = script.indexOf('flutter pub get');
    final refresh = script.indexOf('scripts/refresh-apple-mdk.sh');
    expect(refresh, greaterThan(pubGet));
    expect(refresh, greaterThanOrEqualTo(0));

    // The archive step re-reads the installed copy, so a checkout prepared
    // earlier in the day cannot be archived after the window closed.
    expect(workflow, contains('scripts/refresh-apple-mdk.sh check'));
    expect(
      workflow.indexOf('refresh-apple-mdk.sh check'),
      lessThan(workflow.indexOf('- name: Archive iOS app')),
    );

    // The helper refuses the manifest shape outside build-time resolution and
    // names the dependency bump, but it must fail rather than return success:
    // a silent exit 0 leaves the expired pinned SDK in the build (#192).
    expect(helper, contains('mdk.xcframework'));
    expect(helper, contains('binary target as a local path'));
    expect(helper, contains('predates build-time resolution'));
    expect(helper, contains('mdk_apple_freshness.py'));
    expect(
      helper,
      isNot(contains('MDK_ALLOW_STALE')),
      reason: 'An unusable SDK must not be shippable behind an opt-in.',
    );
    expect(
      helper,
      isNot(contains('this build links the pin as before')),
      reason: 'The helper must never fall back to the expired pin.',
    );

    // Behaviour lives in scripts/tests/refresh_apple_mdk_test.sh, which runs
    // the real helper against a stub tool; these are only wiring assertions.
    final shellTest = File('scripts/tests/refresh_apple_mdk_test.sh');
    expect(
      shellTest.existsSync(),
      isTrue,
      reason: 'The MDK failure paths are covered by the shell test.',
    );
    final shellTestSource = shellTest.readAsStringSync();
    expect(shellTestSource, contains('missing freshness tool fails'));
    expect(shellTestSource, contains('digest mismatch fails'));
    expect(shellTestSource, contains('below the API floor fails'));
    expect(
      shellTestSource,
      contains('explicit URL with an empty digest fails'),
    );

    // The honest limit: this fixes builds, not already installed apps.
    expect(helper, contains('WHAT THIS DOES NOT FIX'));
    expect(helper, contains('already installed app keeps the stamp'));
  });

  test('macOS builds install a fresh MDK before linking it', () {
    final script = File('ci_scripts/macos_post_clone.sh').readAsStringSync();
    final workflow = File('.github/workflows/release.yml').readAsStringSync();
    final appStore = File('scripts/build-ios-appstore.sh').readAsStringSync();

    final pubGet = script.indexOf('flutter pub get');
    final refresh = script.indexOf('scripts/refresh-apple-mdk.sh');
    final configOnly = script.indexOf(
      'flutter build macos --release --config-only',
    );
    expect(refresh, greaterThan(pubGet));
    expect(configOnly, greaterThan(refresh));

    // The GitHub release build runs its own macOS matrix leg.
    final releaseLeg = workflow.indexOf("- name: Refresh the MDK Apple SDK");
    expect(releaseLeg, greaterThanOrEqualTo(0));
    expect(
      workflow.indexOf("if: matrix.platform == 'macos'", releaseLeg),
      greaterThan(releaseLeg),
    );

    expect(
      appStore.indexOf('scripts/refresh-apple-mdk.sh'),
      lessThan(appStore.indexOf('flutter build ipa --release')),
    );
  });
}
