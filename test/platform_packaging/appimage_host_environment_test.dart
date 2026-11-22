import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/appimage_host_environment.dart';
import 'package:shell_executor/shell_executor.dart';

const _mount = '/tmp/.mount_mithkaAbC123';
const _keys =
    'PATH LD_LIBRARY_PATH GTK_DATA_PREFIX GTK_THEME GDK_BACKEND XDG_DATA_DIRS '
    'GSETTINGS_SCHEMA_DIR GI_TYPELIB_PATH GTK_EXE_PREFIX GTK_PATH '
    'GTK_IM_MODULE_FILE GDK_PIXBUF_MODULE_FILE';

/// The environment of a real 1.12.8 AppImage process. linuxdeploy's GTK hook
/// ran before AppRun.wrapped recorded the originals, so several of them
/// already point into the mount.
Map<String, String> _appImageEnvironment() => {
  'HOME': '/home/user',
  'WAYLAND_DISPLAY': 'wayland-1',
  'APPDIR': _mount,
  'APPIMAGE': '/home/user/Applications/Mithka.AppImage',
  'ARGV0': '/home/user/Applications/Mithka.AppImage',
  'OWD': '/home/user',
  'MITHKA_APPIMAGE_ENV_KEYS': _keys,
  'PATH': '$_mount/usr/bin:/usr/local/bin:/usr/bin',
  'MITHKA_APPIMAGE_ORIGINAL_PATH': '/usr/local/bin:/usr/bin',
  'LD_LIBRARY_PATH': '$_mount/usr/lib',
  'XDG_DATA_DIRS':
      '$_mount/usr/share:/usr/share:$_mount/usr/share:/usr/share:'
      '/usr/local/share:/usr/share',
  'MITHKA_APPIMAGE_ORIGINAL_XDG_DATA_DIRS':
      '$_mount/usr/share:/usr/share:/usr/local/share:/usr/share',
  'GTK_PATH': '$_mount//usr/lib/gtk-3.0',
  'MITHKA_APPIMAGE_ORIGINAL_GTK_PATH': '$_mount//usr/lib/gtk-3.0',
  'GDK_PIXBUF_MODULE_FILE':
      '$_mount//usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache',
  'MITHKA_APPIMAGE_ORIGINAL_GDK_PIXBUF_MODULE_FILE':
      '$_mount//usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache',
  'GTK_DATA_PREFIX': _mount,
  'MITHKA_APPIMAGE_ORIGINAL_GTK_DATA_PREFIX': _mount,
  'GTK_THEME': 'Adwaita:light',
  'MITHKA_APPIMAGE_ORIGINAL_GTK_THEME': 'Adwaita:dark',
  'GDK_BACKEND': 'x11',
  'MITHKA_APPIMAGE_ORIGINAL_GDK_BACKEND': 'x11',
  'GI_TYPELIB_PATH': '$_mount//usr/lib/girepository-1.0',
  'MITHKA_APPIMAGE_ORIGINAL_GI_TYPELIB_PATH':
      '$_mount//usr/lib/girepository-1.0',
};

void main() {
  group('appImageHostEnvironment', () {
    test('unsets variables the AppImage introduced', () {
      final host = appImageHostEnvironment(_appImageEnvironment());

      expect(host, isNot(contains('LD_LIBRARY_PATH')));
      expect(host['PATH'], '/usr/local/bin:/usr/bin');
    });

    test('drops mount entries from recorded originals', () {
      final host = appImageHostEnvironment(_appImageEnvironment());

      expect(host['XDG_DATA_DIRS'], '/usr/share:/usr/local/share:/usr/share');
      for (final key in [
        'GTK_PATH',
        'GDK_PIXBUF_MODULE_FILE',
        'GTK_DATA_PREFIX',
        'GI_TYPELIB_PATH',
      ]) {
        expect(host, isNot(contains(key)), reason: key);
      }
      expect(host.values.where((value) => value.contains(_mount)), isEmpty);
    });

    test('keeps recorded values that are not bundle paths', () {
      final host = appImageHostEnvironment(_appImageEnvironment());

      expect(host['GTK_THEME'], 'Adwaita:dark');
      expect(host['GDK_BACKEND'], 'x11');
      expect(host['HOME'], '/home/user');
      expect(host['WAYLAND_DISPLAY'], 'wayland-1');
    });

    test('keeps empty entries and an originally empty value', () {
      final host = appImageHostEnvironment({
        'APPDIR': '$_mount/',
        'MITHKA_APPIMAGE_ENV_KEYS': 'PATH GTK_THEME',
        'PATH': '$_mount/usr/bin::/usr/bin',
        'MITHKA_APPIMAGE_ORIGINAL_PATH': '$_mount/usr/bin::/usr/bin',
        'GTK_THEME': 'Adwaita',
        'MITHKA_APPIMAGE_ORIGINAL_GTK_THEME': '',
      });

      expect(host['PATH'], ':/usr/bin');
      expect(host['GTK_THEME'], '');
    });

    test('does not treat a sibling directory as part of the mount', () {
      final host = appImageHostEnvironment({
        'APPDIR': _mount,
        'MITHKA_APPIMAGE_ENV_KEYS': 'PATH',
        'MITHKA_APPIMAGE_ORIGINAL_PATH': '${_mount}2/bin:/usr/bin',
      });

      expect(host['PATH'], '${_mount}2/bin:/usr/bin');
    });

    test('removes AppImage bookkeeping', () {
      final host = appImageHostEnvironment(_appImageEnvironment());

      expect(
        host.keys.where(
          (key) =>
              key.startsWith('MITHKA_APPIMAGE_') ||
              const ['APPDIR', 'APPIMAGE', 'ARGV0', 'OWD'].contains(key),
        ),
        isEmpty,
      );
    });

    test('restores the recorded values when APPDIR is unusable', () {
      final host = appImageHostEnvironment({
        'MITHKA_APPIMAGE_ENV_KEYS': 'PATH LD_LIBRARY_PATH',
        'PATH': '/bundle/usr/bin:/usr/bin',
        'MITHKA_APPIMAGE_ORIGINAL_PATH': '/usr/bin',
        'LD_LIBRARY_PATH': '/bundle/usr/lib',
      });

      expect(host['PATH'], '/usr/bin');
      expect(host, isNot(contains('LD_LIBRARY_PATH')));
    });
  });

  group('useAppImageHostEnvironmentForShellCommands', () {
    late ShellExecutor previous;
    setUp(() => previous = ShellExecutor.global);
    tearDown(() => ShellExecutor.global = previous);

    test('leaves the executor alone outside the AppImage', () {
      useAppImageHostEnvironmentForShellCommands(
        environment: const {'PATH': '/usr/bin', 'HOME': '/home/user'},
      );

      expect(ShellExecutor.global, same(previous));
    });

    test(
      'installs the host environment executor once for the AppImage',
      () {
        useAppImageHostEnvironmentForShellCommands(
          environment: _appImageEnvironment(),
        );
        final installed = ShellExecutor.global;
        useAppImageHostEnvironmentForShellCommands(
          environment: _appImageEnvironment(),
        );

        expect(installed, isA<AppImageHostShellExecutor>());
        expect(ShellExecutor.global, same(installed));
        expect(
          (installed as AppImageHostShellExecutor).hostEnvironment,
          appImageHostEnvironment(_appImageEnvironment()),
        );
      },
      skip: Platform.isLinux ? false : 'AppImages only run on Linux',
    );
  });

  group(
    'AppImageHostShellExecutor',
    () {
      final executor = AppImageHostShellExecutor(const {
        'PATH': '/usr/bin:/bin',
        'MITHKA_HOST': 'host',
      });
      List<String> lines(Object? output) =>
          (output as String).trim().split('\n');

      test('runs programs with only the host environment', () async {
        final result = await executor.exec(
          'env',
          const [],
          environment: {'MITHKA_CALL': 'call'},
        );

        expect(result.exitCode, 0);
        expect(
          lines(result.stdout),
          unorderedEquals([
            'PATH=/usr/bin:/bin',
            'MITHKA_HOST=host',
            'MITHKA_CALL=call',
          ]),
        );
      });

      test('runs synchronous programs with only the host environment', () {
        final result = executor.execSync('env', const []);

        expect(result.exitCode, 0);
        expect(
          lines(result.stdout),
          unorderedEquals(['PATH=/usr/bin:/bin', 'MITHKA_HOST=host']),
        );
      });
    },
    skip: Platform.isLinux ? false : 'AppImages only run on Linux',
  );
}
