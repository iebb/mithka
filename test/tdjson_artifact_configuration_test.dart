import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedMembers = <String, Set<String>>{
    'tdjson-android-arm64-v8a.zip': {'arm64-v8a/libtdjson.so'},
    'tdjson-android-armeabi-v7a.zip': {'armeabi-v7a/libtdjson.so'},
    'tdjson-android-x86_64.zip': {'x86_64/libtdjson.so'},
    'tdjson-ios.xcframework.zip': {
      'tdjson.xcframework/Info.plist',
      'tdjson.xcframework/ios-arm64/tdjson.framework/Headers/tdjson.h',
      'tdjson.xcframework/ios-arm64/tdjson.framework/Info.plist',
      'tdjson.xcframework/ios-arm64/tdjson.framework/Modules/module.modulemap',
      'tdjson.xcframework/ios-arm64/tdjson.framework/tdjson',
      'tdjson.xcframework/ios-arm64-simulator/tdjson.framework/Headers/tdjson.h',
      'tdjson.xcframework/ios-arm64-simulator/tdjson.framework/Info.plist',
      'tdjson.xcframework/ios-arm64-simulator/tdjson.framework/Modules/module.modulemap',
      'tdjson.xcframework/ios-arm64-simulator/tdjson.framework/tdjson',
    },
    'tdjson-linux-arm64.zip': {'libtdjson.so'},
    'tdjson-linux-x64.zip': {'libtdjson.so'},
    'tdjson-macos-universal.zip': {'libtdjson.dylib'},
    'tdjson-windows-arm64.zip': {'tdjson.dll'},
    'tdjson-windows-x64.zip': {'tdjson.dll'},
  };

  test('TDJSON schema-v2 manifest pins every supported release artifact', () {
    final manifestFile = File('scripts/tdjson-manifest.json');
    expect(
      manifestFile.existsSync(),
      isTrue,
      reason: 'The checked-in manifest is the only TDJSON release pin.',
    );

    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    expect(
      manifest.keys,
      unorderedEquals([
        'schema_version',
        'release_tag',
        'tdlib_version',
        'upstream_repository',
        'upstream_sha',
        'mithka_tdjson_sha',
        'patchset_sha256',
        'build_definition_sha256',
        'assets',
      ]),
    );
    expect(manifest['schema_version'], 2);
    expect(manifest['release_tag'], isNot(anyOf(isEmpty, contains('latest'))));
    expect(manifest['tdlib_version'], isNotEmpty);
    expect(manifest['upstream_repository'], 'tdlib/td');
    expect(manifest['upstream_sha'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(manifest['mithka_tdjson_sha'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(manifest['patchset_sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      manifest['build_definition_sha256'],
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );

    final assets = manifest['assets'] as Map<String, dynamic>;
    expect(assets.keys, unorderedEquals(expectedMembers.keys));
    for (final entry in expectedMembers.entries) {
      final asset = assets[entry.key] as Map<String, dynamic>;
      expect(asset.keys, unorderedEquals(['sha256', 'size', 'members']));
      expect(asset['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(asset['size'], isA<int>());
      expect(asset['size'] as int, greaterThan(0));

      final members = asset['members'] as Map<String, dynamic>;
      expect(members.keys, unorderedEquals(entry.value));
      for (final member in members.values.cast<Map<String, dynamic>>()) {
        expect(member.keys, unorderedEquals(['sha256', 'size']));
        expect(member['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(member['size'], isA<int>());
        expect(member['size'] as int, greaterThan(0));
      }
    }
  });

  test('platform entry points share the manifest installer', () {
    for (final path in [
      'scripts/build-tdjson-android.sh',
      'scripts/build-tdjson-ios.sh',
      'scripts/build-tdjson-desktop.sh',
    ]) {
      final script = File(path).readAsStringSync();
      expect(script, contains('install-tdjson-artifact.py'));
      expect(script, isNot(contains('TDJSON_RELEASE_TAG=')));
      expect(script, isNot(contains('.tdlib-build')));
      expect(script, isNot(contains('git clone')));
      expect(script, isNot(contains('cmake --build')));
    }

    final iosHook = File('ios/ci_scripts/ci_post_clone.sh').readAsStringSync();
    expect(iosHook, contains(r'"$REPO/scripts/build-tdjson-ios.sh"'));
    expect(iosHook, isNot(contains('TDJSON_RELEASE_TAG=')));
    expect(iosHook, isNot(contains('TDJSON_XCFRAMEWORK_URL')));
    expect(iosHook, isNot(contains('wrap-tdjson-xcframework.sh')));

    final macosHook = File('ci_scripts/macos_post_clone.sh').readAsStringSync();
    expect(
      macosHook,
      contains(
        r'"$REPO/scripts/build-tdjson-desktop.sh" macos '
        'native-libs/libtdjson.dylib',
      ),
    );
    expect(macosHook, isNot(contains('TDJSON_RELEASE_TAG=')));
    expect(macosHook, isNot(contains('TDJSON_ARCHIVE_SHA256=')));
    expect(macosHook, isNot(contains('TDJSON_BINARY_SHA256=')));
    expect(macosHook, isNot(contains('tdjson-macos-universal.zip')));
  });

  test('Windows builds require and bundle the pinned tdjson library', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    final runnerCmake = File(
      'windows/runner/CMakeLists.txt',
    ).readAsStringSync();
    expect(cmake, contains('../native-libs/tdjson.dll'));
    expect(cmake, contains('Missing native-libs/tdjson.dll'));
    expect(cmake, contains(r'install(FILES "${TDJSON_LIBRARY}"'));
    expect(runnerCmake, contains('copy_if_different'));
    expect(runnerCmake, contains(r'$<TARGET_FILE_DIR:${BINARY_NAME}>'));
  });
}
