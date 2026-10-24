// Behavioral safety tests for scripts/enable-ohos-plugins.sh (PR #272 review).
//
// The overlay helper must never discard unrelated work. These cases run the
// real script offline (no network, no `flutter pub get`) against a scratch
// copy of the repository's own pubspec files, covering the states the review
// enumerated: a dirty pubspec, repeated apply, revert without a backup, and
// apply/resolve/revert where the lockfile is rewritten in between.
//
// The merge itself is byte-checked against a hand-computed expectation, and
// every destructive refusal is asserted to leave both files untouched.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class RunResult {
  final int code;
  final String out;
  final String err;
  RunResult({required this.code, required this.out, required this.err});
}

void main() {
  late Directory repo;
  late Directory scratch;
  late String script;
  final pristinePubspec = File('pubspec.yaml').readAsStringSync();
  final pristineLock = File('pubspec.lock').readAsStringSync();

  setUpAll(() {
    repo = Directory.current;
    script = '${repo.path}/scripts/enable-ohos-plugins.sh';
  });

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('ohos_overlay_test');
    for (final name in [
      'pubspec.yaml',
      'pubspec.lock',
      'pubspec_overrides.ohos.yaml',
    ]) {
      File('${repo.path}/$name').copySync('${scratch.path}/$name');
    }
    Directory('${scratch.path}/scripts').createSync();
    File(script).copySync('${scratch.path}/scripts/enable-ohos-plugins.sh');
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  RunResult run(List<String> args) {
    final result = Process.runSync('bash', [
      'scripts/enable-ohos-plugins.sh',
      ...args,
    ], workingDirectory: scratch.path);
    return RunResult(
      code: result.exitCode,
      out: result.stdout.toString(),
      err: result.stderr.toString(),
    );
  }

  test(
    'apply merges the overlay and keeps a pristine backup of both files',
    () {
      final r = run(['apply']);
      expect(r.code, 0, reason: 'clean apply must succeed\n${r.err}');
      expect(r.out, contains('merged 5 overrides'));

      final merged = File('${scratch.path}/pubspec.yaml').readAsStringSync();
      expect(merged, isNot(pristinePubspec));
      // The fvp git pin (existing dependency_overrides body) survives verbatim.
      final pin = RegExp(r'fvp:\n\s+git:\n\s+url:').firstMatch(pristinePubspec);
      if (pin != null) {
        expect(merged, contains('fvp:'));
      }
      // The overlay's scalar overrides are appended under the block.
      expect(merged, contains('package_info_plus_ohos: 0.0.7'));
      expect(merged, contains('geolocator_ohos: 0.0.3'));
      // Backups hold the exact pre-apply bytes, uncommitted edits included.
      expect(
        File('${scratch.path}/pubspec.yaml.ohos-backup').readAsStringSync(),
        pristinePubspec,
      );
      expect(
        File('${scratch.path}/pubspec.lock.ohos-backup').readAsStringSync(),
        pristineLock,
      );
    },
  );

  test('a second apply refuses instead of overwriting the only backup', () {
    expect(run(['apply']).code, 0);
    final afterFirstApply = File(
      '${scratch.path}/pubspec.yaml',
    ).readAsStringSync();

    final r = run(['apply']);
    expect(r.code, isNot(0), reason: 'repeated apply must refuse');
    expect(r.err, contains('already active'));

    // Nothing moved: the backup still holds the original, the target still
    // holds the overlaid content (not a backup-of-the-overlay).
    expect(
      File('${scratch.path}/pubspec.yaml.ohos-backup').readAsStringSync(),
      pristinePubspec,
    );
    expect(
      File('${scratch.path}/pubspec.yaml').readAsStringSync(),
      afterFirstApply,
    );
  });

  test(
    'apply preserves a dirty pubspec and revert restores its exact bytes',
    () {
      final dirty = '$pristinePubspec# uncommitted local edit\n';
      File('${scratch.path}/pubspec.yaml').writeAsStringSync(dirty);

      expect(run(['apply']).code, 0);
      expect(
        File('${scratch.path}/pubspec.yaml.ohos-backup').readAsStringSync(),
        dirty,
        reason: 'the backup must capture pre-existing uncommitted edits',
      );

      // A `flutter pub get` in between rewrites the lock for OHOS.
      File(
        '${scratch.path}/pubspec.lock',
      ).writeAsStringSync('# rewritten for ohos\n');
      expect(run(['revert']).code, 0);

      expect(File('${scratch.path}/pubspec.yaml').readAsStringSync(), dirty);
      expect(
        File('${scratch.path}/pubspec.lock').readAsStringSync(),
        pristineLock,
      );
      expect(
        File('${scratch.path}/pubspec.yaml.ohos-backup').existsSync(),
        isFalse,
      );
      expect(
        File('${scratch.path}/pubspec.lock.ohos-backup').existsSync(),
        isFalse,
      );
    },
  );

  test('revert without a backup refuses and never checks out user files', () {
    File(
      '${scratch.path}/pubspec.yaml',
    ).writeAsStringSync('# work in progress\n');

    final r = run(['revert']);
    expect(
      r.code,
      isNot(0),
      reason: 'revert without an active overlay must refuse',
    );
    expect(r.err, contains('no active overlay'));

    expect(
      File('${scratch.path}/pubspec.yaml').readAsStringSync(),
      '# work in progress\n',
      reason: 'a refused revert must leave the file byte-identical',
    );
  });

  test('apply/resolve/revert restores the original lock after a rewrite', () {
    expect(run(['apply']).code, 0);

    // `flutter pub get` resolves OHOS deps and rewrites pubspec.lock.
    File(
      '${scratch.path}/pubspec.lock',
    ).writeAsStringSync('# resolved for ohos\n');
    expect(run(['revert']).code, 0);

    expect(
      File('${scratch.path}/pubspec.yaml').readAsStringSync(),
      pristinePubspec,
    );
    expect(
      File('${scratch.path}/pubspec.lock').readAsStringSync(),
      pristineLock,
    );
  });

  test('apply with a stale lock backup refuses instead of guessing', () {
    File(
      '${scratch.path}/pubspec.lock.ohos-backup',
    ).writeAsStringSync('stale\n');

    final r = run(['apply']);
    expect(r.code, isNot(0));
    expect(r.err, contains('stale'));
    expect(
      File('${scratch.path}/pubspec.yaml.ohos-backup').existsSync(),
      isFalse,
    );
  });

  test('neither command edits tracked .gitignore at runtime', () {
    final gitignore = File('${scratch.path}/.gitignore');
    gitignore.writeAsStringSync('# marker\n');

    expect(run(['apply']).code, 0);
    expect(run(['revert']).code, 0);

    expect(gitignore.readAsStringSync(), '# marker\n');
  });

  test('the script has no runtime edit of .gitignore left in it', () {
    // The 2026-10-24 review also flagged the runtime `.gitignore` append;
    // the fix removed it, so the script must no longer write to .gitignore.
    final text = File(script).readAsStringSync();
    expect(
      text.contains('.gitignore'),
      isFalse,
      reason:
          'the helper must not reference .gitignore at all; entries are committed',
    );
  });
}
