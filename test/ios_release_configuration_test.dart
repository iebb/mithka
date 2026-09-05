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
}
