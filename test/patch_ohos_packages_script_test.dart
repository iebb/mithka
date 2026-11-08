// Offline tests for scripts/patch-ohos-packages.py: the HarmonyOS build stages
// a lock-verified flutter_math_fork with `case TargetPlatform.ohos:` added to
// its exhaustive platform switches. Each case runs the real script against a
// scratch repo holding a locally built archive (--archive), never the network.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _switch = '''
    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        break;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        break;
    }
''';

void main() {
  late Directory scratch;
  late File archive;

  /// Builds a fake flutter_math_fork 0.7.4 archive whose patched files hold
  /// [selectableSwitches] switches in selectable.dart and one switch in the
  /// other two, and pins its sha256 (or [lockedSha]) in pubspec.lock.
  void stageRepo({int selectableSwitches = 2, String? lockedSha}) {
    final pkg = Directory('${scratch.path}/pkg')..createSync();
    final files = {
      'lib/src/widgets/selectable.dart': _switch * selectableSwitches,
      'lib/src/render/layout/line_editable.dart': _switch,
      'lib/src/widgets/selection/gesture_detector_builder_selectable.dart':
          _switch,
      'pubspec.yaml': 'name: flutter_math_fork\nversion: 0.7.4\n',
    };
    files.forEach((path, body) {
      File('${pkg.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(body);
    });
    archive = File('${scratch.path}/flutter_math_fork-0.7.4.tar.gz');
    final tar = Process.runSync('tar', [
      'czf',
      archive.path,
      '-C',
      pkg.path,
      '.',
    ]);
    expect(tar.exitCode, 0, reason: tar.stderr.toString());
    final sha =
        lockedSha ?? sha256.convert(archive.readAsBytesSync()).toString();
    File('${scratch.path}/pubspec.lock').writeAsStringSync('''
packages:
  flutter_math_fork:
    dependency: "direct main"
    description:
      name: flutter_math_fork
      sha256: "$sha"
      url: "https://pub.dev"
    source: hosted
    version: "0.7.4"
''');
  }

  ProcessResult run() => Process.runSync('python3', [
    'scripts/patch-ohos-packages.py',
    '--archive',
    archive.path,
  ], workingDirectory: scratch.path);

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('ohos_patch_test');
    Directory('${scratch.path}/scripts').createSync();
    File(
      'scripts/patch-ohos-packages.py',
    ).copySync('${scratch.path}/scripts/patch-ohos-packages.py');
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  test('adds an ohos case to every android-style branch', () {
    stageRepo();
    final r = run();
    expect(r.exitCode, 0, reason: r.stderr.toString());

    final out = '${scratch.path}/.ohos-packages/flutter_math_fork';
    final selectable = File(
      '$out/lib/src/widgets/selectable.dart',
    ).readAsStringSync();
    expect(
      'case TargetPlatform.windows:\n      case TargetPlatform.ohos:\n'
          .allMatches(selectable)
          .length,
      2,
    );
    for (final path in [
      'lib/src/render/layout/line_editable.dart',
      'lib/src/widgets/selection/gesture_detector_builder_selectable.dart',
    ]) {
      expect(
        'case TargetPlatform.ohos:'
            .allMatches(File('$out/$path').readAsStringSync())
            .length,
        1,
      );
    }
    expect(File('$out/pubspec.yaml').existsSync(), isTrue);
  });

  test('refuses an archive that does not match the locked sha256', () {
    stageRepo(lockedSha: '0' * 64);
    final r = run();
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('does not match the locked sha256'));
    expect(Directory('${scratch.path}/.ohos-packages').existsSync(), isFalse);
  });

  test('fails loudly when the upstream switches drift', () {
    stageRepo(selectableSwitches: 3);
    final r = run();
    expect(r.exitCode, isNot(0));
    expect(r.stderr.toString(), contains('expected 2 anchored switch(es)'));
    expect(Directory('${scratch.path}/.ohos-packages').existsSync(), isFalse);
  });
}
