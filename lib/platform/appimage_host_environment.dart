import 'dart:io';

import 'package:shell_executor/shell_executor.dart';

/// Variables that only describe the running AppImage and mean nothing (or the
/// wrong thing) to a host program.
const _appImageOnlyKeys = ['APPDIR', 'APPIMAGE', 'ARGV0', 'OWD'];

/// The environment a host program should get when Mithka runs as an AppImage.
///
/// `linux/appimage/AppRun` records every variable it changes in
/// `MITHKA_APPIMAGE_ORIGINAL_*` and lists them in `MITHKA_APPIMAGE_ENV_KEYS`.
/// Those records are restored, and a variable recorded as unset is removed.
///
/// linuxdeploy's generated AppRun sources the GTK hook before it executes ours
/// as `AppRun.wrapped`, so several recorded values already point into the
/// mount. Entries inside `APPDIR` are therefore dropped from every restored
/// value, and a value with nothing left is unset. A host program must never
/// load the bundle's libraries, GTK modules or typelibs, and the mount
/// disappears as soon as Mithka exits.
Map<String, String> appImageHostEnvironment(Map<String, String> current) {
  final result = Map<String, String>.of(current);
  final bundleRoot = _bundleRoot(current['APPDIR']);
  const prefix = 'MITHKA_APPIMAGE_ORIGINAL_';
  for (final key in (result.remove('MITHKA_APPIMAGE_ENV_KEYS') ?? '').split(
    ' ',
  )) {
    if (key.isEmpty) continue;
    final original = result.remove('$prefix$key');
    final restored = original == null
        ? null
        : _withoutBundleEntries(original, bundleRoot);
    if (restored == null) {
      result.remove(key);
    } else {
      result[key] = restored;
    }
  }
  for (final key in _appImageOnlyKeys) {
    result.remove(key);
  }
  return result;
}

/// Whether [environment] belongs to a process started by Mithka's AppRun.
bool isMithkaAppImageEnvironment(Map<String, String> environment) =>
    (environment['MITHKA_APPIMAGE_ENV_KEYS'] ?? '').isNotEmpty;

/// Makes `shell_executor` start host programs with [appImageHostEnvironment].
///
/// On Linux, `screen_capturer` runs spectacle, gnome-screenshot or
/// deepin-screen-recorder through `ShellExecutor.global`. Inheriting the
/// AppImage's `LD_LIBRARY_PATH` makes them load bundled libraries instead of
/// the host's and fail before they capture anything. Each Flutter engine has
/// its own isolate and therefore its own `ShellExecutor.global`, so callers
/// install this in the window that launches the program. Outside the AppImage
/// this does nothing.
void useAppImageHostEnvironmentForShellCommands({
  Map<String, String>? environment,
}) {
  if (!Platform.isLinux || ShellExecutor.global is AppImageHostShellExecutor) {
    return;
  }
  final current = environment ?? Platform.environment;
  if (!isMithkaAppImageEnvironment(current)) return;
  ShellExecutor.global = AppImageHostShellExecutor(
    appImageHostEnvironment(current),
  );
}

/// A [ShellExecutor] whose programs see only [hostEnvironment] plus the
/// per-call overrides, never the AppImage's own variables.
class AppImageHostShellExecutor extends ShellExecutor {
  AppImageHostShellExecutor(Map<String, String> hostEnvironment)
    : hostEnvironment = Map.unmodifiable(hostEnvironment);

  final Map<String, String> hostEnvironment;

  Map<String, String> _environmentWith(Map<String, String>? overrides) => {
    ...hostEnvironment,
    ...?overrides,
  };

  @override
  Future<ProcessResult> exec(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: _environmentWith(environment),
      includeParentEnvironment: false,
    );
  }

  @override
  ProcessResult execSync(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) {
    return Process.runSync(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: _environmentWith(environment),
      includeParentEnvironment: false,
      runInShell: runInShell,
    );
  }
}

/// [appDir] without a trailing slash, or `null` when it cannot be a mount.
String? _bundleRoot(String? appDir) {
  if (appDir == null || !appDir.startsWith('/')) return null;
  var root = appDir;
  while (root.endsWith('/')) {
    root = root.substring(0, root.length - 1);
  }
  return root.isEmpty ? null : root;
}

/// [value] with every colon-separated entry inside [bundleRoot] removed.
///
/// Other entries, including empty ones and non-path values such as
/// `Adwaita:dark`, are kept in order. Returns `null` when only bundle entries
/// were present.
String? _withoutBundleEntries(String value, String? bundleRoot) {
  if (bundleRoot == null) return value;
  final entries = value.split(':');
  final kept = [
    for (final entry in entries)
      if (entry != bundleRoot && !entry.startsWith('$bundleRoot/')) entry,
  ];
  if (kept.length == entries.length) return value;
  return kept.isEmpty ? null : kept.join(':');
}
