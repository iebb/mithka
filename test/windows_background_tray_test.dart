import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  test(
    'primary Windows window owns a persistent background tray lifecycle',
    () {
      final main = _read('windows/runner/main.cpp');
      final header = _read('windows/runner/win32_window.h');
      final runner = _read('windows/runner/win32_window.cpp');
      final flutterWindow = _read('windows/runner/flutter_window.cpp');

      expect(main, contains('EnableBackgroundTray();'));
      expect(main, contains('CreateMutexW'));
      expect(main, contains('ERROR_ALREADY_EXISTS'));
      expect(main, contains('FindWindowW'));
      expect(main, contains('AllowSetForegroundWindow'));
      expect(main, contains('kActivatePrimaryWindowMessage'));
      expect(
        main.indexOf('window.Destroy();'),
        lessThan(
          main.indexOf(
            '::CoUninitialize();',
            main.indexOf('window.Destroy();'),
          ),
        ),
      );

      expect(header, contains('HandleBackgroundTrayMessage'));
      expect(runner, contains('Shell_NotifyIconW(NIM_ADD'));
      expect(runner, contains('Shell_NotifyIconW(NIM_DELETE'));
      expect(runner, contains('RegisterWindowMessageW(L"TaskbarCreated")'));
      expect(runner, contains('command == SC_CLOSE || command == SC_MINIMIZE'));
      expect(runner, contains('ShowWindow(window_handle_, SW_HIDE)'));
      expect(runner, contains('message == WM_QUERYENDSESSION'));
      expect(runner, contains('message == WM_ENDSESSION'));
      expect(runner, contains('L"Show Mithka"'));
      expect(runner, contains('L"Quit Mithka"'));

      final trayBeforePlugins = flutterWindow.indexOf(
        'HandleBackgroundTrayMessage(hwnd, message, wparam, lparam)',
      );
      final pluginDispatch = flutterWindow.indexOf(
        'flutter_controller_->HandleTopLevelWindowProc',
      );
      expect(trayBeforePlugins, greaterThanOrEqualTo(0));
      expect(pluginDispatch, greaterThan(trayBeforePlugins));
    },
  );

  test('Quit finalizes exactly once while ordinary close stays alive', () {
    final header = _read('windows/runner/win32_window.h');
    final runner = _read('windows/runner/win32_window.cpp');
    final flutterWindow = _read('windows/runner/flutter_window.cpp');

    expect(header, contains('bool destruction_finalized_ = false;'));
    expect(runner, contains('if (destruction_finalized_)'));
    expect(runner, contains('FinalizeDestruction();'));
    expect(
      runner,
      isNot(
        contains(
          'case WM_DESTROY:\n      window_handle_ = nullptr;\n      Destroy();',
        ),
      ),
    );
    expect(runner, contains('quit_requested_ = true;'));
    expect(runner, contains('SetTimer(window_handle_, kQuitFallbackTimer'));
    expect(runner, contains('KillTimer(hwnd, kQuitFallbackTimer)'));
    expect(runner, contains('PostMessageW(window_handle_, WM_CLOSE'));
    expect(
      flutterWindow.replaceAll('\r\n', '\n'),
      contains('FlutterWindow::~FlutterWindow() {\n  //'),
    );
  });

  test('notification icon is an owned runner resource with Shell linkage', () {
    final resources = _read('windows/runner/Runner.rc');
    final resourceHeader = _read('windows/runner/resource.h');
    final cmake = _read('windows/runner/CMakeLists.txt');

    expect(resources, contains('IDI_TRAY_ICON'));
    expect(resourceHeader, contains('#define IDI_TRAY_ICON'));
    expect(cmake, contains('"shell32.lib"'));
  });

  test('local notifications have a stable Windows identity', () {
    final notifications = _read(
      'lib/notifications/notification_controller.dart',
    );

    expect(notifications, contains('windows: WindowsInitializationSettings('));
    expect(notifications, contains("appName: 'Mithka'"));
    expect(notifications, contains("appUserModelId: 'Iebb.Mithka.Desktop'"));
    expect(
      notifications,
      contains("guid: '19a46b98-1781-4d9e-92ed-bd0576e48e2d'"),
    );
  });
}
