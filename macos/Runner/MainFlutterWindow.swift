import Cocoa
import FlutterMacOS
import multi_window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    HandoffBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger
    )
    DesktopClipboardImagesPlugin.register(
      with: flutterViewController.registrar(forPlugin: "DesktopClipboardImagesPlugin")
    )
    MultiWindowManagerPlugin.RegisterGeneratedPlugins = { registry in
      RegisterGeneratedPlugins(registry: registry)
      DesktopClipboardImagesPlugin.register(
        with: registry.registrar(forPlugin: "DesktopClipboardImagesPlugin")
      )
    }

    super.awakeFromNib()

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    minSize = NSSize(width: 820, height: 560)
    if #available(macOS 11.0, *) {
      titlebarSeparatorStyle = .none
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
