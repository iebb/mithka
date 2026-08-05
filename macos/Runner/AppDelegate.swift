import Cocoa
import FlutterMacOS
import multi_window_manager

@main
class AppDelegate: FlutterAppDelegate {
  private var rightControlMonitor: Any?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Flutter's macOS engine tracks right-Control with device bit 0x200, but
    // AppKit reports NX_DEVICERCTLKEYMASK = 0x2000, so the engine never sees
    // the key go down and right-Ctrl shortcuts (e.g. Ctrl+Enter to send) only
    // work with the left key (flutter/flutter#148936). Mirror the real bit
    // onto the one the engine checks for every keyboard event; each keyDown
    // re-syncs modifier state, so the fix covers shortcuts in all windows.
    rightControlMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .keyUp, .flagsChanged]
    ) { event in
      Self.mirrorRightControlFlag(event)
    }
    super.applicationDidFinishLaunching(notification)
  }

  private static func mirrorRightControlFlag(_ event: NSEvent) -> NSEvent {
    let deviceRightControl: UInt = 0x2000  // NX_DEVICERCTLKEYMASK
    let engineRightControl: UInt = 0x200  // bit Flutter's engine matches against
    let raw = event.modifierFlags.rawValue
    guard raw & deviceRightControl != 0, raw & engineRightControl == 0 else {
      return event
    }
    let isFlagsChanged = event.type == .flagsChanged
    let patched = NSEvent.keyEvent(
      with: event.type,
      location: event.locationInWindow,
      modifierFlags: NSEvent.ModifierFlags(rawValue: raw | engineRightControl),
      timestamp: event.timestamp,
      windowNumber: event.windowNumber,
      context: nil,
      characters: isFlagsChanged ? "" : (event.characters ?? ""),
      charactersIgnoringModifiers: isFlagsChanged
        ? "" : (event.charactersIgnoringModifiers ?? ""),
      isARepeat: isFlagsChanged ? false : event.isARepeat,
      keyCode: event.keyCode
    )
    return patched ?? event
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !NSApp.windows.contains(where: { $0 is MainFlutterWindow && $0.isVisible })
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
