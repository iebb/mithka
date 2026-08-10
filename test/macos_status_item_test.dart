import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS menu-bar and Dock reopen the retained main window', () {
    final delegate = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    final window = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final info = File('macos/Runner/Info.plist').readAsStringSync();
    final reopenHandler = delegate.substring(
      delegate.indexOf('override func applicationShouldHandleReopen('),
      delegate.indexOf('private static func mirrorRightControlFlag'),
    );

    expect(delegate, contains('NSStatusBar.system.statusItem'));
    expect(
      delegate,
      isNot(contains('super.applicationDidFinishLaunching(notification)')),
      reason:
          'FlutterAppDelegate does not implement this optional delegate method',
    );
    expect(delegate, contains('image.isTemplate = true'));
    expect(delegate, contains('private static func makeStatusItemImage()'));
    expect(delegate, contains('private var retainedMainWindow'));
    expect(delegate, contains('applicationShouldHandleReopen('));
    expect(reopenHandler, contains('bringMainWindowToFront(using: sender)'));
    expect(reopenHandler, contains('return false'));
    expect(
      reopenHandler,
      isNot(contains('return bringMainWindowToFront(using: sender)')),
    );
    expect(delegate, contains('primaryWindow.makeKeyAndOrderFront(nil)'));
    expect(delegate, contains('application.unhide(nil)'));
    expect(delegate, contains('application.activate(ignoringOtherApps: true)'));
    expect(delegate, contains('action: #selector(quitApplication)'));
    expect(delegate, contains('mithka/application_lifecycle'));
    expect(delegate, contains('channel.invokeMethod("requestExit"'));
    expect(delegate, contains('call.method == "ready"'));
    expect(delegate, contains('timeoutSeconds: TimeInterval = 25'));
    expect(delegate, contains('override func applicationShouldTerminate('));
    expect(delegate, contains('return .terminateLater'));
    expect(
      delegate,
      contains('guard isReady, let requestExit else { return .terminateNow }'),
    );
    expect(delegate, contains('reply(toApplicationShouldTerminate: allowed)'));
    expect(delegate, contains('if MainFlutterWindow.isNativeTestHost()'));
    expect(delegate, contains('return .terminateNow'));
    expect(
      delegate,
      isNot(contains('super.applicationShouldTerminate(')),
      reason: 'Only the primary-engine bridge may approve AppKit termination',
    );
    expect(
      delegate,
      contains(
        'applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {\n    // The menu-bar item remains available',
      ),
    );
    expect(delegate, contains('return false'));
    expect(delegate, isNot(contains('NSImage(systemSymbolName:')));

    expect(window, contains('override func close()'));
    expect(window, contains('override func miniaturize(_ sender: Any?)'));
    expect(window, contains('orderOut(nil)'));
    expect(window, contains('orderOut(sender)'));
    expect(window, contains('isReleasedWhenClosed = false'));
    expect(window, contains('XCTestConfigurationFilePath'));
    expect(window, contains('NSClassFromString("XCTestCase")'));
    expect(window, contains('contentViewController = NSViewController()'));
    expect(
      RegExp(
        r'ApplicationTerminationBridge\.shared\.registerPrimary',
      ).allMatches(window).length,
      1,
    );
    final childEngineRegistration = window.substring(
      window.indexOf('MultiWindowManagerPlugin.RegisterGeneratedPlugins'),
    );
    expect(
      childEngineRegistration,
      isNot(contains('ApplicationTerminationBridge')),
      reason: 'Child-window engines must never replace the primary bridge',
    );

    expect(info, contains('<key>LSMultipleInstancesProhibited</key>'));
    expect(info, contains('<true/>'));
  });
}
