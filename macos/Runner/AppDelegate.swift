import Cocoa
import FlutterMacOS
import multi_window_manager

/// Owns the cancelable AppKit termination handshake for the primary engine.
///
/// Method channels are scoped to a Flutter engine. Pinning this bridge to the
/// first primary view controller prevents a later child-window engine from
/// acknowledging readiness or replacing the shutdown handler.
final class ApplicationTerminationBridge {
  static let shared = ApplicationTerminationBridge()
  static let channelName = "mithka/application_lifecycle"
  // Dart may spend up to 3s joining startup, 16s closing an existing client,
  // and 3s joining the receive isolate. Keep the native deadline outside that
  // bounded window so AppKit never cancels an otherwise healthy shutdown.
  static let timeoutSeconds: TimeInterval = 25

  typealias ExitRequest = (@escaping FlutterResult) -> Void

  private let timeoutSeconds: TimeInterval
  private let timeoutQueue: DispatchQueue
  private var primaryOwnerIdentifier: ObjectIdentifier?
  private var channel: FlutterMethodChannel?
  private var requestExit: ExitRequest?
  private var isReady = false
  private var nextAttemptID: UInt64 = 0
  private var pendingAttemptID: UInt64?
  private var pendingReply: ((Bool) -> Void)?
  private var timeoutWorkItem: DispatchWorkItem?
  private var terminationApproved = false

  init(
    timeoutSeconds: TimeInterval = ApplicationTerminationBridge.timeoutSeconds,
    timeoutQueue: DispatchQueue = .main
  ) {
    self.timeoutSeconds = timeoutSeconds
    self.timeoutQueue = timeoutQueue
  }

  @discardableResult
  func registerPrimary(viewController: FlutterViewController) -> Bool {
    let ownerIdentifier = ObjectIdentifier(viewController)
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: viewController.engine.binaryMessenger
    )
    guard bindPrimary(owner: viewController, requestExit: { [weak channel] result in
      guard let channel else {
        result(FlutterMethodNotImplemented)
        return
      }
      channel.invokeMethod("requestExit", arguments: nil, result: result)
    }) else {
      return false
    }
    guard self.channel == nil else { return true }

    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      let handle = {
        guard call.method == "ready" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard self?.acknowledgeReady(from: ownerIdentifier) == true else {
          result(
            FlutterError(
              code: "PRIMARY_ENGINE_MISMATCH",
              message: "Only Mithka's primary engine can own app termination",
              details: nil
            )
          )
          return
        }
        result(true)
      }
      if Thread.isMainThread {
        handle()
      } else {
        DispatchQueue.main.async(execute: handle)
      }
    }
    return true
  }

  /// Binds the first engine permanently. Re-registering that same owner is
  /// idempotent; a different (child-window) owner can never replace it.
  @discardableResult
  func bindPrimary(
    owner: AnyObject,
    requestExit: @escaping ExitRequest
  ) -> Bool {
    let identifier = ObjectIdentifier(owner)
    if let primaryOwnerIdentifier {
      return primaryOwnerIdentifier == identifier
    }
    primaryOwnerIdentifier = identifier
    self.requestExit = requestExit
    return true
  }

  @discardableResult
  func acknowledgeReady(from owner: AnyObject) -> Bool {
    acknowledgeReady(from: ObjectIdentifier(owner))
  }

  /// Returns `.terminateLater` exactly once per active attempt. Duplicate Quit
  /// requests share that attempt and cannot invoke Dart shutdown twice.
  func requestTermination(
    reply: @escaping (Bool) -> Void
  ) -> NSApplication.TerminateReply {
    if terminationApproved { return .terminateNow }
    if pendingAttemptID != nil { return .terminateLater }
    // Dart awaits the ready acknowledgement before it starts TDLib. If startup
    // has not reached that point, there is no native Telegram runtime to drain
    // and an immediate Cmd-Q remains both safe and responsive.
    guard isReady, let requestExit else { return .terminateNow }

    nextAttemptID &+= 1
    let attemptID = nextAttemptID
    pendingAttemptID = attemptID
    pendingReply = reply

    let timeout = DispatchWorkItem { [weak self] in
      self?.complete(attemptID: attemptID, allowTermination: false)
    }
    timeoutWorkItem = timeout
    timeoutQueue.asyncAfter(
      deadline: .now() + timeoutSeconds,
      execute: timeout
    )

    requestExit { [weak self] result in
      let finish: () -> Void = { [weak self] in
        guard let self else { return }
        self.complete(
          attemptID: attemptID,
          allowTermination: (result as? Bool) == true
        )
      }
      if Thread.isMainThread {
        finish()
      } else {
        DispatchQueue.main.async(execute: finish)
      }
    }
    return .terminateLater
  }

  private func acknowledgeReady(from ownerIdentifier: ObjectIdentifier) -> Bool {
    guard
      primaryOwnerIdentifier == ownerIdentifier,
      requestExit != nil
    else {
      return false
    }
    isReady = true
    return true
  }

  private func complete(attemptID: UInt64, allowTermination: Bool) {
    guard pendingAttemptID == attemptID else { return }
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    pendingAttemptID = nil
    let reply = pendingReply
    pendingReply = nil
    terminationApproved = allowTermination
    reply?(allowTermination)
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  private var rightControlMonitor: Any?
  private var statusItem: NSStatusItem?
  /// Keep the original Flutter engine/window alive while the app is hidden in
  /// the menu bar. Recreating it on every Dock launch can race the still-live
  /// TDLib process and its database locks.
  private var retainedMainWindow: MainFlutterWindow?

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
    _ = resolveMainWindow()
    installStatusItem()
  }

  private func resolveMainWindow() -> MainFlutterWindow? {
    if let retainedMainWindow {
      return retainedMainWindow
    }
    guard
      let window = mainFlutterWindow as? MainFlutterWindow
        ?? NSApp.windows.first(where: { $0 is MainFlutterWindow })
          as? MainFlutterWindow
    else {
      return nil
    }
    window.isReleasedWhenClosed = false
    retainedMainWindow = window
    return window
  }

  private func installStatusItem() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(
      withLength: NSStatusItem.squareLength
    )
    if let button = item.button {
      button.image = Self.makeStatusItemImage()
      button.image?.accessibilityDescription = "Mithka"
      button.toolTip = "Mithka"
    }

    let menu = NSMenu()
    let showItem = NSMenuItem(
      title: NSLocalizedString(
        "Show Mithka",
        comment: "Menu bar action that reopens Mithka's main window"
      ),
      action: #selector(showMainWindow),
      keyEquivalent: ""
    )
    showItem.target = self
    menu.addItem(showItem)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: NSLocalizedString(
        "Quit Mithka",
        comment: "Menu bar action that terminates Mithka"
      ),
      action: #selector(quitApplication),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)
    item.menu = menu
    statusItem = item
  }

  /// An owned monochrome speech-mark keeps the status item legible in both
  /// menu-bar appearances without depending on a platform icon catalogue.
  private static func makeStatusItemImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    NSColor.black.setStroke()
    NSColor.black.setFill()

    let bubble = NSBezierPath(
      roundedRect: NSRect(x: 1.75, y: 3.75, width: 14.5, height: 10.5),
      xRadius: 4,
      yRadius: 4
    )
    bubble.lineWidth = 1.55
    bubble.stroke()

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 5.25, y: 4.15))
    tail.line(to: NSPoint(x: 3.45, y: 1.9))
    tail.line(to: NSPoint(x: 7.1, y: 4.05))
    tail.lineWidth = 1.55
    tail.lineJoinStyle = .round
    tail.lineCapStyle = .round
    tail.stroke()

    for x in [6.0, 9.0, 12.0] {
      NSBezierPath(
        ovalIn: NSRect(x: x - 0.8, y: 8.2, width: 1.6, height: 1.6)
      ).fill()
    }
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  @discardableResult
  private func bringMainWindowToFront(
    using application: NSApplication = NSApp
  ) -> Bool {
    guard let primaryWindow = resolveMainWindow() else { return false }
    application.unhide(nil)
    if primaryWindow.isMiniaturized {
      primaryWindow.deminiaturize(nil)
    }
    primaryWindow.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)
    return true
  }

  @objc private func showMainWindow() {
    bringMainWindowToFront()
  }

  @objc private func quitApplication() {
    NSApp.terminate(nil)
  }

  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    // Application-hosted native tests deliberately never start Flutter/TDLib.
    // Let XCTest tear down its inert host without waiting on a missing channel.
    if MainFlutterWindow.isNativeTestHost() {
      return .terminateNow
    }
    return ApplicationTerminationBridge.shared.requestTermination { allowed in
      sender.reply(toApplicationShouldTerminate: allowed)
    }
  }

  override func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
  ) -> Bool {
    guard HandoffBridge.shared.accept(userActivity) else { return false }
    bringMainWindowToFront(using: application)
    return true
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    // A Dock click always restores the retained engine/window. Never create a
    // replacement window or a second TDLib client just because it was hidden.
    bringMainWindowToFront(using: sender)
    // The reopen AppleEvent is fully handled above. Returning false prevents
    // AppKit from following up with its default untitled-window creation.
    return false
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
    // The menu-bar item remains available to reopen the retained main window.
    // Explicit Quit in either native menu still terminates normally.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
