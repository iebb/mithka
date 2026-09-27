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
    DesktopMediaDropView.register(
      with: flutterViewController.registrar(forPlugin: "DesktopMediaDropView")
    )
    MultiWindowManagerPlugin.RegisterGeneratedPlugins = { registry in
      RegisterGeneratedPlugins(registry: registry)
      MacOSAppIconPlugin.register(
        with: registry.registrar(forPlugin: "MacOSAppIconPlugin")
      )
      DesktopClipboardImagesPlugin.register(
        with: registry.registrar(forPlugin: "DesktopClipboardImagesPlugin")
      )
      DesktopMediaDropView.register(
        with: registry.registrar(forPlugin: "DesktopMediaDropView")
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
    titlebarSeparatorStyle = .none
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
    let centerInWindow =
      close.superview?.convert(
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

final class DesktopClipboardImagesPlugin: NSObject, FlutterPlugin {
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
    switch call.method {
    case "readImages":
      result(Self.readImages())
    case "writeImage":
      guard let bytes = call.arguments as? FlutterStandardTypedData else {
        result(false)
        return
      }
      result(Self.writeImage(bytes.data))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Write only image data. A file URL would make Copy Image paste a local path.
  static func writeImage(_ data: Data, to pasteboard: NSPasteboard = .general) -> Bool {
    guard !data.isEmpty else { return false }
    let png: Data?
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
      png = data
    } else {
      let bitmap = NSBitmapImageRep(data: data) ?? NSImage(data: data).flatMap { image in
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
      }
      png = bitmap?.representation(using: .png, properties: [:])
    }
    guard let png, !png.isEmpty else { return false }
    let item = NSPasteboardItem()
    guard item.setData(png, forType: .png) else { return false }
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
  }

  static func readImages(from pasteboard: NSPasteboard = .general, limit: Int = Int.max)
    -> [[String: Any]]
  {
    guard let items = pasteboard.pasteboardItems else { return [] }
    return items.prefix(limit).compactMap(readImage)
  }

  private static func readImage(_ item: NSPasteboardItem) -> [String: Any]? {
    if let value = item.string(forType: .fileURL),
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

/// An engine-local AppKit drag destination. NSView forwards ordinary mouse and
/// keyboard events through its responder chain to the Flutter view underneath.
final class DesktopMediaDropView: NSView {
  private let sendEvent: (String, Any?) -> Void

  static func register(with registrar: FlutterPluginRegistrar) {
    guard let view = registrar.view else { return }
    let channel = FlutterMethodChannel(
      name: "mithka/media_drop", binaryMessenger: registrar.messenger
    )
    let dropView = DesktopMediaDropView(frame: view.bounds) { method, arguments in
      channel.invokeMethod(method, arguments: arguments)
    }
    dropView.autoresizingMask = [.width, .height]
    view.addSubview(dropView)
  }

  init(frame: NSRect, sendEvent: @escaping (String, Any?) -> Void) {
    self.sendEvent = sendEvent
    super.init(frame: frame)
    registerForDraggedTypes([.fileURL, .png, .tiff])
  }

  required init?(coder: NSCoder) { nil }

  func flutterPosition(_ windowPoint: NSPoint) -> [String: CGFloat] {
    let point = convert(windowPoint, from: nil)
    return ["x": point.x, "y": isFlipped ? point.y : bounds.height - point.y]
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    sendEvent("dragEnteredAt", flutterPosition(sender.draggingLocation))
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    sendEvent("dragEnteredAt", flutterPosition(sender.draggingLocation))
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    sendEvent("dragExited", nil)
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    sendEvent("dragExited", nil)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let position = flutterPosition(sender.draggingLocation)
    let images = DesktopClipboardImagesPlugin.readImages(from: sender.draggingPasteboard, limit: 10)
    guard !images.isEmpty else {
      sendEvent("dragExited", nil)
      return false
    }
    let dropID = UUID().uuidString
    sendEvent("dropStartedAt", ["id": dropID, "x": position["x"]!, "y": position["y"]!])
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let paths = Self.storeImages(images)
      DispatchQueue.main.async {
        self?.sendEvent(
          "dropImagesAt",
          [
            "id": dropID, "paths": paths,
          ])
      }
    }
    return true
  }

  static func storeImages(_ images: [[String: Any]]) -> [String] {
    images.prefix(10).compactMap { image in
      guard let data = image["data"] as? FlutterStandardTypedData else { return nil }
      let extensions = [
        "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif",
        "image/webp": "webp", "image/heic": "heic", "image/heif": "heif",
      ]
      guard let mime = image["mimeType"] as? String, let ext = extensions[mime] else {
        return nil
      }
      let file = FileManager.default.temporaryDirectory.appendingPathComponent(
        "mithka-drop-\(UUID().uuidString).\(ext)"
      )
      do {
        try data.data.write(to: file, options: .atomic)
        return file.path
      } catch {
        return nil
      }
    }
  }
}
