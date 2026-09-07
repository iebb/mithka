//
//  desktop_updater.dart
//
//  One-click in-place update for Windows and Linux packages, including AppImages.
//
//  Both ship as an archive holding a single `Mithka` directory, so an update is
//  a directory swap: download the release asset for this architecture, verify
//  it against the SHA-256 GitHub publishes, unpack it beside the install, then
//  hand a small helper script the job of replacing the directory once this
//  process has exited and relaunching the new build. The app cannot overwrite
//  its own running executable, which is why the last step leaves the process.
//
//  The swap is staged and reversible: the current install is renamed aside
//  first and put back if anything fails, so a failed update leaves the working
//  build in place rather than a half-written directory.
//  AppImages use the same verified download, followed by an atomic file rename
//  over the original APPIMAGE path instead of replacing the mounted directory.
//

import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'release_feed.dart';

/// What the updater is doing, for the progress sheet.
enum DesktopUpdateStage { downloading, verifying, extracting, staging }

class DesktopUpdateProgress {
  const DesktopUpdateProgress(
    this.stage, {
    this.receivedBytes = 0,
    this.totalBytes = 0,
  });

  final DesktopUpdateStage stage;
  final int receivedBytes;
  final int totalBytes;

  /// Completion in 0..1, or null while the total is unknown.
  double? get fraction {
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }
}

/// Why this install cannot replace itself.
enum DesktopUpdateBlock {
  /// Not a platform that ships a portable, self-updating package. macOS builds
  /// update through their own signed channel.
  unsupportedPlatform,

  /// A package manager, Flatpak, or Snap owns this payload, and
  /// swapping the directory underneath it would fight the real updater.
  managedInstall,

  /// The directory holding the install is not writable by this user, so the
  /// swap would fail halfway.
  readOnlyInstall,
}

class DesktopUpdateException implements Exception {
  const DesktopUpdateException(this.message);
  final String message;

  @override
  String toString() => 'DesktopUpdateException: $message';
}

/// Cooperative cancellation for a download the user backed out of.
class DesktopUpdateCancellation {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }

  void _bind(void Function()? onCancel) {
    _onCancel = onCancel;
    if (_cancelled) onCancel?.call();
  }
}

/// Where the running build lives on disk.
class DesktopInstallLayout {
  const DesktopInstallLayout({
    required this.installDirectory,
    required this.launcher,
    this.isAppImage = false,
  });

  /// The unpacked package root — the directory the update replaces.
  final Directory installDirectory;

  /// The executable inside it, which is also what gets relaunched.
  final File launcher;

  /// AppImages replace the outer file, never their read-only mounted bundle.
  final bool isAppImage;

  /// The directory the swap renames within; it is what must be writable.
  Directory get parentDirectory =>
      isAppImage ? launcher.parent : installDirectory.parent;

  static DesktopInstallLayout current() => fromExecutable(
    executablePath: Platform.resolvedExecutable,
    environment: Platform.environment,
    isLinux: Platform.isLinux,
  );

  @visibleForTesting
  static DesktopInstallLayout fromExecutable({
    required String executablePath,
    required Map<String, String> environment,
    required bool isLinux,
  }) {
    final appImage = isLinux ? environment['APPIMAGE'] : null;
    final isAppImage = appImage != null && appImage.isNotEmpty;
    final launcher = File(isAppImage ? appImage : executablePath);
    return DesktopInstallLayout(
      installDirectory: launcher.parent,
      launcher: launcher,
      isAppImage: isAppImage,
    );
  }
}

/// A verified update unpacked and waiting for the process to exit.
class PreparedDesktopUpdate {
  PreparedDesktopUpdate._(
    this.version,
    this._layout,
    this._workDirectory,
    this._stagedDirectory,
  );

  /// The version that will be running after the restart.
  final String version;

  final DesktopInstallLayout _layout;
  final Directory _workDirectory;
  final FileSystemEntity _stagedDirectory;

  /// Throws away the staged build, leaving the current install untouched.
  Future<void> discard() async {
    await _deleteQuietly(_workDirectory);
  }

  /// Starts the swap helper and leaves, which is what lets the helper replace
  /// the directory this process is running from.
  ///
  /// [drain] is whatever needs a clean shutdown before the process goes. It runs
  /// only once the helper is started and waiting: draining first would leave a
  /// gutted app still on screen if the helper then failed to launch, whereas the
  /// helper simply times out and leaves the install alone if the drain hangs.
  /// A drain that throws does not strand the user on the old build.
  Future<Never> apply({Future<void> Function()? drain}) async {
    final script = await _writeHelperScript();
    await Process.start(
      Platform.isWindows ? 'cmd.exe' : '/bin/sh',
      Platform.isWindows ? ['/c', script.path] : [script.path],
      mode: ProcessStartMode.detached,
      workingDirectory: script.parent.path,
      environment: _layout.isAppImage
          ? appImageUpdateEnvironment(Platform.environment)
          : null,
      includeParentEnvironment: !_layout.isAppImage,
    );
    if (drain != null) {
      try {
        await drain();
      } catch (_) {
        // The update is staged and verified; a client that refused to close
        // cleanly must not leave the user on the old build.
      }
    }
    // Give the detached helper a moment to be scheduled before the exit removes
    // this process from the wait it is about to start.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    exit(0);
  }

  /// The helper lives in the system temp directory rather than in the work
  /// directory it deletes, so it is never removing the file it is running.
  Future<File> _writeHelperScript() async {
    final directory = await Directory.systemTemp.createTemp('mithka-update-');
    final backup =
        '${_layout.parentDirectory.path}${Platform.pathSeparator}'
        '${DesktopUpdater.backupPrefix}$pid';
    final script = File(
      '${directory.path}${Platform.pathSeparator}'
      '${Platform.isWindows ? 'apply.cmd' : 'apply.sh'}',
    );
    final build = Platform.isWindows
        ? buildWindowsUpdateScript
        : buildPosixUpdateScript;
    await script.writeAsString(
      _layout.isAppImage
          ? buildAppImageUpdateScript(
              processId: pid,
              appImagePath: _layout.launcher.path,
              stagedPath: _stagedDirectory.path,
              workDirectory: _workDirectory.path,
            )
          : build(
              processId: pid,
              installDirectory: _layout.installDirectory.path,
              stagedDirectory: _stagedDirectory.path,
              backupDirectory: backup,
              workDirectory: _workDirectory.path,
              launcherName: DesktopUpdater.launcherFileName,
            ),
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', ['0755', script.path]);
    }
    return script;
  }
}

/// The POSIX swap helper.
///
/// Every path is baked in as a single-quoted literal rather than passed as an
/// argument, so a directory containing spaces or shell metacharacters cannot
/// change what the script does.
@visibleForTesting
String buildPosixUpdateScript({
  required int processId,
  required String installDirectory,
  required String stagedDirectory,
  required String backupDirectory,
  required String workDirectory,
  required String launcherName,
}) {
  String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
  return '''
#!/bin/sh
# Replaces a Mithka install with a staged update once the app has exited.
set -u

pid=${quote('$processId')}
install_dir=${quote(installDirectory)}
staged_dir=${quote(stagedDirectory)}
backup_dir=${quote(backupDirectory)}
work_dir=${quote(workDirectory)}
launcher_name=${quote(launcherName)}

relaunch() {
  if [ -x "\$install_dir/\$launcher_name" ]; then
    (cd "\$install_dir" && "./\$launcher_name" >/dev/null 2>&1 &)
  fi
}

waited=0
while [ "\$waited" -lt 60 ] && kill -0 "\$pid" 2>/dev/null; do
  sleep 1
  waited=\$((waited + 1))
done

if kill -0 "\$pid" 2>/dev/null; then
  rm -rf "\$work_dir"
  exit 1
fi

rm -rf "\$backup_dir"
if ! mv "\$install_dir" "\$backup_dir"; then
  rm -rf "\$work_dir"
  relaunch
  exit 1
fi

if ! mv "\$staged_dir" "\$install_dir"; then
  mv "\$backup_dir" "\$install_dir"
  rm -rf "\$work_dir"
  relaunch
  exit 1
fi

rm -rf "\$backup_dir" "\$work_dir"
relaunch
exit 0
''';
}

/// Restores the environment saved by linux/appimage/AppRun before it loads
/// bundled GTK libraries. Otherwise even the helper's shell utilities can try
/// to load shared objects from a mount that disappears when Mithka exits.
@visibleForTesting
Map<String, String> appImageUpdateEnvironment(Map<String, String> current) {
  final result = Map<String, String>.of(current);
  const prefix = 'MITHKA_APPIMAGE_ORIGINAL_';
  for (final key in (result.remove('MITHKA_APPIMAGE_ENV_KEYS') ?? '').split(
    ' ',
  )) {
    if (key.isEmpty) continue;
    final original = result.remove('$prefix$key');
    if (original == null) {
      result.remove(key);
    } else {
      result[key] = original;
    }
  }
  for (final key in ['APPDIR', 'APPIMAGE', 'ARGV0', 'OWD']) {
    result.remove(key);
  }
  return result;
}

/// Replaces only the AppImage file, keeping its filename (including portable
/// .home/.config siblings and desktop shortcuts) unchanged. Staging beside the
/// original permits one atomic rename over the old file on the same filesystem.
@visibleForTesting
String buildAppImageUpdateScript({
  required int processId,
  required String appImagePath,
  required String stagedPath,
  required String workDirectory,
}) {
  String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
  return '''
#!/bin/sh
set -u
pid=${quote('$processId')}
app_image=${quote(appImagePath)}
staged=${quote(stagedPath)}
work_dir=${quote(workDirectory)}

relaunch() {
  (cd "\$(dirname "\$app_image")" && "\$app_image" >/dev/null 2>&1 &)
}

waited=0
while [ "\$waited" -lt 60 ] && kill -0 "\$pid" 2>/dev/null; do
  sleep 1
  waited=\$((waited + 1))
done
if kill -0 "\$pid" 2>/dev/null; then
  rm -rf "\$work_dir"
  exit 1
fi

if [ ! -f "\$app_image" ] || [ -L "\$app_image" ] ||
   [ ! -f "\$staged" ] || [ ! -x "\$staged" ]; then
  rm -rf "\$work_dir"
  relaunch
  exit 1
fi
if ! mv -f "\$staged" "\$app_image"; then
  # The atomic rename failed: the original file is still in place.
  rm -rf "\$work_dir"
  relaunch
  exit 1
fi
rm -rf "\$work_dir"
relaunch
exit 0
''';
}

/// The Windows swap helper.
///
/// Windows refuses to rename a directory that still holds a mapped executable
/// image, so retrying the move is both the swap and the wait for the old
/// process to finish leaving.
@visibleForTesting
String buildWindowsUpdateScript({
  required int processId,
  required String installDirectory,
  required String stagedDirectory,
  required String backupDirectory,
  required String workDirectory,
  required String launcherName,
}) {
  // Inside `set "NAME=value"` every character is literal except `%`, which
  // still starts an expansion and has to be doubled.
  String assign(String name, String value) =>
      'set "$name=${value.replaceAll('%', '%%')}"';
  return [
    '@echo off',
    'setlocal',
    'rem Replaces a Mithka install with a staged update once the app exited.',
    assign('PID', '$processId'),
    assign('INSTALL_DIR', installDirectory),
    assign('STAGED_DIR', stagedDirectory),
    assign('BACKUP_DIR', backupDirectory),
    assign('WORK_DIR', workDirectory),
    assign('LAUNCHER', launcherName),
    '',
    'set /a waited=0',
    ':wait',
    // Matching the image name keeps this independent of the locale-specific
    // "no tasks are running" line tasklist prints when the PID is gone.
    'tasklist /FI "PID eq %PID%" /NH /FO CSV 2>nul '
        '| findstr /I /C:"%LAUNCHER%" >nul',
    'if errorlevel 1 goto exited',
    'set /a waited+=1',
    'if %waited% GEQ 60 goto exited',
    'ping -n 2 127.0.0.1 >nul',
    'goto wait',
    '',
    ':exited',
    'if exist "%BACKUP_DIR%" rmdir /s /q "%BACKUP_DIR%"',
    'set /a attempts=0',
    ':swap',
    'move "%INSTALL_DIR%" "%BACKUP_DIR%" >nul 2>&1',
    'if not errorlevel 1 goto swapped',
    'set /a attempts+=1',
    'if %attempts% GEQ 30 goto failed',
    'ping -n 2 127.0.0.1 >nul',
    'goto swap',
    '',
    ':swapped',
    'move "%STAGED_DIR%" "%INSTALL_DIR%" >nul 2>&1',
    'if errorlevel 1 (',
    '  move "%BACKUP_DIR%" "%INSTALL_DIR%" >nul 2>&1',
    '  goto failed',
    ')',
    'rmdir /s /q "%BACKUP_DIR%" >nul 2>&1',
    'rmdir /s /q "%WORK_DIR%" >nul 2>&1',
    'start "" /D "%INSTALL_DIR%" "%INSTALL_DIR%\\%LAUNCHER%"',
    'exit /b 0',
    '',
    ':failed',
    'if not exist "%INSTALL_DIR%" if exist "%BACKUP_DIR%" '
        'move "%BACKUP_DIR%" "%INSTALL_DIR%" >nul 2>&1',
    'rmdir /s /q "%WORK_DIR%" >nul 2>&1',
    'if exist "%INSTALL_DIR%\\%LAUNCHER%" '
        'start "" /D "%INSTALL_DIR%" "%INSTALL_DIR%\\%LAUNCHER%"',
    'exit /b 1',
    '',
  ].join('\r\n');
}

abstract final class DesktopUpdater {
  static const workPrefix = '.mithka-update-';
  static const backupPrefix = '.mithka-backup-';

  /// Environment variables the sandboxed runtimes set for their own payload.
  static const _managedEnvironmentKeys = ['FLATPAK_ID', 'SNAP'];

  /// Path prefixes that mean the install belongs to the system rather than to
  /// the user who is running it.
  static const _managedPrefixes = [
    '/app/',
    '/nix/store/',
    '/opt/',
    '/snap/',
    '/usr/',
  ];

  static String get launcherFileName =>
      Platform.isWindows ? 'mithka.exe' : 'mithka';

  /// Why an in-place update is unavailable here, or null when one can run.
  static DesktopUpdateBlock? inspectInstall() {
    final layout = DesktopInstallLayout.current();
    return describeInstallBlock(
      platformSupported: desktopPackageSuffix() != null,
      environment: Platform.environment,
      executablePath: Platform.resolvedExecutable,
      parentWritable: _isWritable(layout.parentDirectory),
    );
  }

  /// The policy behind [inspectInstall], separated from the machine it runs on
  /// so the distribution rules can be tested directly.
  static DesktopUpdateBlock? describeInstallBlock({
    required bool platformSupported,
    required Map<String, String> environment,
    required String executablePath,
    required bool parentWritable,
  }) {
    if (!platformSupported) return DesktopUpdateBlock.unsupportedPlatform;
    for (final key in _managedEnvironmentKeys) {
      if ((environment[key] ?? '').isNotEmpty) {
        return DesktopUpdateBlock.managedInstall;
      }
    }
    final appImage = environment['APPIMAGE'];
    if (appImage != null && appImage.isNotEmpty) {
      final appDirectory = environment['APPDIR'] ?? '';
      // A process launched by another AppImage can inherit its environment.
      // Only our AppRun and its mounted executable may replace that outer file.
      if (appDirectory.isEmpty ||
          !appDirectory.startsWith('/') ||
          executablePath != '$appDirectory/usr/bin/mithka' ||
          (environment['MITHKA_APPIMAGE_ENV_KEYS'] ?? '').isEmpty) {
        return DesktopUpdateBlock.managedInstall;
      }
    }
    final target = appImage != null && appImage.isNotEmpty
        ? appImage
        : executablePath;
    // Never resolve a relative APPIMAGE against an arbitrary working directory.
    if (appImage != null && appImage.isNotEmpty && !appImage.startsWith('/')) {
      return DesktopUpdateBlock.managedInstall;
    }
    final normalized = target.replaceAll(r'\', '/');
    for (final prefix in _managedPrefixes) {
      if (normalized.startsWith(prefix) ||
          normalized == prefix.substring(0, prefix.length - 1)) {
        return DesktopUpdateBlock.managedInstall;
      }
    }
    if (!parentWritable) return DesktopUpdateBlock.readOnlyInstall;
    return null;
  }

  /// Whether About should offer a one-click update on this install.
  static bool get supportsOneClickUpdate => inspectInstall() == null;

  /// Downloads [asset], verifies it, and unpacks it beside the install.
  ///
  /// Nothing about the running build changes until [PreparedDesktopUpdate.apply]
  /// is called, so a failure here is always recoverable.
  static Future<PreparedDesktopUpdate> prepare(
    ReleaseAsset asset, {
    required String version,
    void Function(DesktopUpdateProgress)? onProgress,
    DesktopUpdateCancellation? cancellation,
    @visibleForTesting DesktopInstallLayout? installLayout,
  }) async {
    final layout = installLayout ?? DesktopInstallLayout.current();
    final block = installLayout == null
        ? inspectInstall()
        : describeInstallBlock(
            platformSupported: true,
            environment: const {},
            executablePath: layout.launcher.path,
            parentWritable: _isWritable(layout.parentDirectory),
          );
    if (block != null) {
      throw DesktopUpdateException(
        'In-place update unavailable: ${block.name}',
      );
    }
    final expectedDigest = asset.sha256;
    if (expectedDigest == null) {
      throw const DesktopUpdateException(
        'Release asset has no SHA-256 digest to verify against',
      );
    }

    final suffix = desktopPackageSuffix(null, layout.isAppImage);
    if (installLayout == null &&
        (suffix == null || !asset.name.endsWith(suffix))) {
      throw const DesktopUpdateException(
        'Release asset does not match this install',
      );
    }
    await _removeStaleArtifacts(layout.parentDirectory);
    final workDirectory = Directory(
      '${layout.parentDirectory.path}${Platform.pathSeparator}$workPrefix$pid',
    );
    await _deleteQuietly(workDirectory);
    await workDirectory.create(recursive: true);

    try {
      // A fixed local name: the archive is identified by the extension the
      // extractor needs, never by the name the release feed supplied.
      final package = File(
        '${workDirectory.path}${Platform.pathSeparator}'
        'package.${layout.isAppImage ? 'AppImage' : (Platform.isWindows ? 'zip' : 'tar.gz')}',
      );
      await _download(
        asset,
        package,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      _throwIfCancelled(cancellation);

      onProgress?.call(
        const DesktopUpdateProgress(DesktopUpdateStage.verifying),
      );
      await _verify(package, expectedDigest, asset.size);
      _throwIfCancelled(cancellation);

      if (layout.isAppImage) {
        await validateAppImage(package);
        final result = await Process.run('chmod', ['0755', package.path]);
        if (result.exitCode != 0) {
          throw const DesktopUpdateException(
            'Could not make the AppImage executable',
          );
        }
        _throwIfCancelled(cancellation);
        onProgress?.call(
          const DesktopUpdateProgress(DesktopUpdateStage.staging),
        );
        return PreparedDesktopUpdate._(version, layout, workDirectory, package);
      }

      onProgress?.call(
        const DesktopUpdateProgress(DesktopUpdateStage.extracting),
      );
      final unpacked = Directory(
        '${workDirectory.path}${Platform.pathSeparator}unpacked',
      );
      await unpacked.create(recursive: true);
      await _extract(package, unpacked);
      _throwIfCancelled(cancellation);

      onProgress?.call(const DesktopUpdateProgress(DesktopUpdateStage.staging));
      final staged = packageRoot(unpacked);
      await package.delete();
      return PreparedDesktopUpdate._(version, layout, workDirectory, staged);
    } catch (_) {
      await _deleteQuietly(workDirectory);
      rethrow;
    }
  }

  static Future<void> _download(
    ReleaseAsset asset,
    File destination, {
    void Function(DesktopUpdateProgress)? onProgress,
    DesktopUpdateCancellation? cancellation,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    cancellation?._bind(() => client.close(force: true));
    try {
      final request = await client.getUrl(Uri.parse(asset.url));
      request.headers.set(HttpHeaders.userAgentHeader, releaseFeedUserAgent);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw DesktopUpdateException(
          'Download failed with HTTP ${response.statusCode}',
        );
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : asset.size;
      var received = 0;
      final sink = destination.openWrite();
      try {
        // Piping preserves backpressure, so a slow disk cannot make the whole
        // package pile up in memory.
        await response
            .map((chunk) {
              received += chunk.length;
              onProgress?.call(
                DesktopUpdateProgress(
                  DesktopUpdateStage.downloading,
                  receivedBytes: received,
                  totalBytes: total,
                ),
              );
              return chunk;
            })
            .pipe(sink);
      } finally {
        await sink.close();
      }
    } on DesktopUpdateException {
      rethrow;
    } catch (error) {
      _throwIfCancelled(cancellation);
      throw DesktopUpdateException('Download failed: $error');
    } finally {
      cancellation?._bind(null);
      client.close(force: true);
    }
  }

  static Future<void> _verify(
    File package,
    String expectedDigest,
    int expectedSize,
  ) async {
    final size = await package.length();
    if (expectedSize > 0 && size != expectedSize) {
      throw DesktopUpdateException(
        'Downloaded $size bytes but the release lists $expectedSize',
      );
    }
    final digest = await sha256.bind(package.openRead()).first;
    if (digest.toString() != expectedDigest) {
      throw const DesktopUpdateException(
        'Downloaded package does not match the published SHA-256',
      );
    }
  }

  /// A type-2 AppImage must be a 64-bit ELF for this machine. The digest check
  /// runs first; no downloaded code is executed while preparing an update.
  @visibleForTesting
  static Future<void> validateAppImage(File package, {Abi? abi}) async {
    final file = await package.open();
    late List<int> header;
    try {
      header = await file.read(20);
    } finally {
      await file.close();
    }
    final machine = switch (abi ?? Abi.current()) {
      Abi.linuxX64 => 62,
      Abi.linuxArm64 => 183,
      _ => -1,
    };
    if (header.length != 20 ||
        header[0] != 0x7f ||
        header[1] != 0x45 ||
        header[2] != 0x4c ||
        header[3] != 0x46 ||
        header[4] != 2 ||
        header[5] != 1 ||
        header[8] != 0x41 ||
        header[9] != 0x49 ||
        header[10] != 2 ||
        (header[18] | (header[19] << 8)) != machine) {
      throw const DesktopUpdateException(
        'Update is not a type-2 AppImage for this architecture',
      );
    }
  }

  static Future<void> _extract(File package, Directory destination) async {
    if (Platform.isWindows) {
      await extractFileToDisk(package.path, destination.path);
      return;
    }
    // tar restores the executable bit on the launcher and libtdjson.so, which
    // a mode-less extraction would drop and leave an install that cannot start.
    final result = await Process.run('tar', [
      '-xzf',
      package.path,
      '-C',
      destination.path,
    ]);
    if (result.exitCode != 0) {
      throw DesktopUpdateException(
        'Could not unpack the update: ${result.stderr}',
      );
    }
  }

  /// The single package directory the archive unpacked to, checked to be a real
  /// Mithka build before anything is allowed to replace the current one.
  @visibleForTesting
  static Directory packageRoot(Directory unpacked) {
    final entries = unpacked.listSync();
    final directories = entries.whereType<Directory>().toList();
    if (directories.length != 1) {
      throw DesktopUpdateException(
        'Expected one directory in the update package, '
        'found ${directories.length}',
      );
    }
    final root = directories.single;
    final launcher = File(
      '${root.path}${Platform.pathSeparator}$launcherFileName',
    );
    if (!launcher.existsSync()) {
      throw const DesktopUpdateException(
        'Update package does not contain a Mithka executable',
      );
    }
    return root;
  }

  /// Clears work and backup directories an interrupted update left behind.
  static Future<void> _removeStaleArtifacts(Directory parent) async {
    if (!parent.existsSync()) return;
    for (final entry in parent.listSync()) {
      if (entry is! Directory) continue;
      final name = entry.path.split(Platform.pathSeparator).last;
      if (name.startsWith(workPrefix) || name.startsWith(backupPrefix)) {
        await _deleteQuietly(entry);
      }
    }
  }

  static bool _isWritable(Directory directory) {
    try {
      final probe = File(
        '${directory.path}${Platform.pathSeparator}.mithka-write-probe.$pid',
      );
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _throwIfCancelled(DesktopUpdateCancellation? cancellation) {
    if (cancellation?.isCancelled ?? false) {
      throw const DesktopUpdateException('Update cancelled');
    }
  }
}

Future<void> _deleteQuietly(Directory directory) async {
  try {
    if (directory.existsSync()) await directory.delete(recursive: true);
  } catch (_) {
    // A leftover directory is cleaned on the next attempt; it is not worth
    // failing an otherwise working update over.
  }
}
