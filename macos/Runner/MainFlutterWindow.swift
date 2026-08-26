import Cocoa
import FlutterMacOS
import multi_window_manager

class MainFlutterWindow: NSWindow {
  /// Native RunnerTests are application-hosted so they can exercise the real
  /// AppDelegate and primary window. Starting Flutter here would also start
  /// TDLib, whose native worker threads outlive XCTest's abrupt host teardown
  /// and can abort while C++ statics are being destroyed.
  static func isNativeTestHost(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isXCTestLoaded: Bool = NSClassFromString("XCTestCase") != nil
  ) -> Bool {
    environment["XCTestConfigurationFilePath"] != nil || isXCTestLoaded
  }

  /// Closing or minimizing the primary window hides it in the menu bar while
  /// its Flutter engine and background services continue running.
  override func close() {
    orderOut(nil)
  }

  override func miniaturize(_ sender: Any?) {
    orderOut(sender)
  }

  override func awakeFromNib() {
    let windowFrame = self.frame
    if Self.isNativeTestHost() {
      contentViewController = NSViewController()
      setFrame(windowFrame, display: true)
      super.awakeFromNib()
      configurePrimaryWindow()
      return
    }

    let flutterViewController = FlutterViewController()
    // Bind the termination channel before attaching the controller (and before
    // Dart can start TDLib). Child engines created below never register it.
    ApplicationTerminationBridge.shared.registerPrimary(
      viewController: flutterViewController
    )
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    MacOSAppIconPlugin.register(
      with: flutterViewController.registrar(forPlugin: "MacOSAppIconPlugin")
    )
    HandoffBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger
    )
    DesktopClipboardImagesPlugin.register(
      with: flutterViewController.registrar(forPlugin: "DesktopClipboardImagesPlugin")
    )
    MultiWindowManagerPlugin.RegisterGeneratedPlugins = { registry in
      RegisterGeneratedPlugins(registry: registry)
      MacOSAppIconPlugin.register(
        with: registry.registrar(forPlugin: "MacOSAppIconPlugin")
      )
      DesktopClipboardImagesPlugin.register(
        with: registry.registrar(forPlugin: "DesktopClipboardImagesPlugin")
      )
    }

    super.awakeFromNib()

    configurePrimaryWindow()
  }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(frameRect, display: flag)
    // Resizing/zooming re-centres the buttons on the system titlebar strip.
    alignTrafficLightsWithTitleBar()
  }

  private func configurePrimaryWindow() {
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isReleasedWhenClosed = false
    minSize = NSSize(width: 820, height: 560)
    if #available(macOS 11.0, *) {
      titlebarSeparatorStyle = .none
    }
    DispatchQueue.main.async { [weak self] in
      self?.alignTrafficLightsWithTitleBar()
    }
  }

  /// The Flutter title bar (MacosDesktopTitleBar) is 40 pt tall from the
  /// window's top edge, so the identity row sits on the 20 pt midline. The
  /// stock traffic lights centre on the shorter system titlebar strip and
  /// ride a few points above it — nudge them onto the same midline.
  func alignTrafficLightsWithTitleBar() {
    guard let close = standardWindowButton(.closeButton) else { return }
    let centerInWindow = close.superview?.convert(
      NSPoint(x: close.frame.midX, y: close.frame.midY),
      to: nil
    ) ?? NSPoint.zero
    let currentFromTop = frame.height - centerInWindow.y
    let delta = currentFromTop - 20
    guard abs(delta) > 0.1 else { return }
    for kind in [
      NSWindow.ButtonType.closeButton,
      .miniaturizeButton,
      .zoomButton,
    ] {
      if let button = standardWindowButton(kind) {
        button.frame.origin.y += delta
      }
    }
  }
}

private final class DesktopClipboardImagesPlugin: NSObject, FlutterPlugin {
  private static let gif = NSPasteboard.PasteboardType("com.compuserve.gif")
  private static let jpeg = NSPasteboard.PasteboardType("public.jpeg")
  private static let webp = NSPasteboard.PasteboardType("org.webmproject.webp")
  private static let heic = NSPasteboard.PasteboardType("public.heic")
  private static let heif = NSPasteboard.PasteboardType("public.heif")

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "mithka/clipboard",
      binaryMessenger: registrar.messenger
    )
    let instance = DesktopClipboardImagesPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "readImages" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result(Self.readImages())
  }

  private static func readImages() -> [[String: Any]] {
    guard let items = NSPasteboard.general.pasteboardItems else { return [] }
    return items.compactMap(readImage)
  }

  private static func readImage(_ item: NSPasteboardItem) -> [String: Any]? {
    if
      let value = item.string(forType: .fileURL),
      let url = URL(string: value),
      url.isFileURL,
      let payload = readImageFile(url)
    {
      return payload
    }

    let representations: [(NSPasteboard.PasteboardType, String)] = [
      (gif, "image/gif"),
      (.png, "image/png"),
      (jpeg, "image/jpeg"),
      (webp, "image/webp"),
      (heic, "image/heic"),
      (heif, "image/heif"),
    ]
    for (type, mimeType) in representations {
      if let data = item.data(forType: type), !data.isEmpty {
        return payload(data, mimeType: mimeType)
      }
    }
    guard
      let tiff = item.data(forType: .tiff),
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]),
      !png.isEmpty
    else {
      return nil
    }
    return payload(png, mimeType: "image/png")
  }

  private static func readImageFile(_ url: URL) -> [String: Any]? {
    let mimeType: String
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg": mimeType = "image/jpeg"
    case "png": mimeType = "image/png"
    case "gif": mimeType = "image/gif"
    case "webp": mimeType = "image/webp"
    case "heic": mimeType = "image/heic"
    case "heif": mimeType = "image/heif"
    default: return nil
    }
    guard let data = try? Data(contentsOf: url), !data.isEmpty else {
      return nil
    }
    return payload(data, mimeType: mimeType)
  }

  private static func payload(_ data: Data, mimeType: String) -> [String: Any] {
    return [
      "mimeType": mimeType,
      "data": FlutterStandardTypedData(bytes: data),
    ]
  }
}
