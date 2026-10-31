import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

/// Builds the trimmed Leaf engine for the platforms whose app and WebViews it
/// serves. Other platforms get no asset and keep TDLib's native proxy types.
Future<void> main(List<String> arguments) => build(arguments, (
  input,
  output,
) async {
  if (!input.config.buildCodeAssets) return;
  final config = input.config.code;
  final os = config.targetOS;
  final arch = config.targetArchitecture;
  final target = switch ((os, arch)) {
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    (OS.iOS, Architecture.arm64) =>
      config.iOS.targetSdk == IOSSdk.iPhoneSimulator
          ? 'aarch64-apple-ios-sim'
          : 'aarch64-apple-ios',
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios',
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    _ => null,
  };
  if (target == null) return;

  final root = input.packageRoot.resolve('native/');
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  final separator = Platform.isWindows ? ';' : ':';
  final env = <String, String>{
    'PATH': [
      Platform.environment['PATH'] ?? '',
      if (home != null) p.join(home, '.cargo', 'bin'),
    ].join(separator),
    'CARGO_TARGET_DIR': input.outputDirectoryShared
        .resolve('cargo/')
        .toFilePath(),
  };
  Future<ProcessResult> run(String tool, List<String> args) async {
    final result = await Process.run(
      tool,
      args,
      environment: env,
      workingDirectory: root.toFilePath(),
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw StateError(
        '$tool ${args.join(' ')} failed:\n${result.stdout}\n${result.stderr}',
      );
    }
    return result;
  }

  // rustup is optional: a toolchain that already has the target needs no
  // network access, and one that lacks it fails in cargo with its name.
  try {
    await run('rustup', ['target', 'add', target]);
  } on ProcessException {
    // No rustup on PATH.
  }

  final rustflags = <String>[];
  if (os == OS.android) {
    final compiler = config.cCompiler;
    if (compiler == null) {
      throw StateError('The Android NDK compiler is required');
    }
    final bin = p.dirname(compiler.compiler.toFilePath());
    final prefix = switch (arch) {
      Architecture.arm => 'armv7a-linux-androideabi',
      Architecture.arm64 => 'aarch64-linux-android',
      _ => 'x86_64-linux-android',
    };
    final clang = p.join(
      bin,
      '$prefix${config.android.targetNdkApi}-clang${Platform.isWindows ? '.cmd' : ''}',
    );
    final key = target.replaceAll('-', '_');
    env.addAll({
      'CARGO_TARGET_${key.toUpperCase()}_LINKER': clang,
      'CC_$key': clang,
      'AR_$key': compiler.archiver.toFilePath(),
    });
    // Android 15 devices may use 16 KB pages.
    rustflags.add('-Clink-arg=-Wl,-z,max-page-size=16384');
  } else {
    // Flutter rewrites the install name when it wraps the framework.
    rustflags.add('-Clink-arg=-Wl,-headerpad_max_install_names');
    if (os == OS.iOS) {
      env['IPHONEOS_DEPLOYMENT_TARGET'] = '${config.iOS.targetVersion}.0';
    } else {
      env['MACOSX_DEPLOYMENT_TARGET'] = '${config.macOS.targetVersion}.0';
    }
  }
  env['CARGO_ENCODED_RUSTFLAGS'] = rustflags.join('\u001f');

  await run('cargo', [
    'build',
    '--manifest-path',
    'Cargo.toml',
    '--locked',
    '--release',
    '--lib',
    '--target',
    target,
  ]);
  final name = os.dylibFileName('mithka_proxy');
  final built = File(p.join(env['CARGO_TARGET_DIR']!, target, 'release', name));
  // An installed, uncompressed per-architecture budget.
  final size = await built.length();
  if (size > 5000000) {
    throw StateError(
      'Leaf is $size bytes for $target, over the 5,000,000 byte budget',
    );
  }
  final library = await built.copy(
    input.outputDirectory.resolve(name).toFilePath(),
  );
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'mithka_proxy',
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
  output.dependencies.addAll([
    for (final entry in Directory.fromUri(root).listSync(recursive: true))
      if (entry is File && !p.split(entry.path).contains('target')) entry.uri,
  ]);
});
