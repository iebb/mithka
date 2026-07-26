import Cocoa
import FlutterMacOS
import multi_window_manager

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !NSApp.windows.contains(where: { $0 is MainFlutterWindow && $0.isVisible })
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
