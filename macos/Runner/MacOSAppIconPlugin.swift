import Cocoa
import FlutterMacOS

/// Changes Mithka's running Dock and app-switcher icon.
///
/// macOS doesn't provide an alternate signed bundle-icon API. Consequently,
/// this intentionally leaves Finder's bundle icon untouched and changes only
/// `NSApplication.applicationIconImage`. The selection is persisted and
/// restored for every launch and every Flutter child engine.
final class MacOSAppIconPlugin: NSObject, FlutterPlugin {
  private static let selectedIconKey = "mithka.selectedDockIcon"
  private static let defaultIconName = "default"
  private static let assetNames = [
    "white",
    "blue",
    "purple",
    "pixel",
    "aurora",
    "prism",
    "signal",
  ]

  private let registrar: FlutterPluginRegistrar

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    applyPersistedIcon()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "mithka/app_icon",
      binaryMessenger: registrar.messenger
    )
    let instance = MacOSAppIconPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)
    case "currentIcon":
      result(Self.persistedIconName())
    case "setIcon":
      let arguments = call.arguments as? [String: Any]
      let requested = arguments?["name"] as? String ?? Self.defaultIconName
      guard Self.isValidIconName(requested) else {
        result(
          FlutterError(
            code: "invalid_app_icon",
            message: "Unknown app icon variant",
            details: nil
          )
        )
        return
      }
      guard applyIcon(named: requested) else {
        result(
          FlutterError(
            code: "app_icon_failed",
            message: "The selected Dock icon asset could not be loaded",
            details: nil
          )
        )
        return
      }
      UserDefaults.standard.set(requested, forKey: Self.selectedIconKey)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applyPersistedIcon() {
    let selected = Self.persistedIconName()
    if !applyIcon(named: selected) {
      UserDefaults.standard.removeObject(forKey: Self.selectedIconKey)
      _ = applyIcon(named: Self.defaultIconName)
    }
  }

  @discardableResult
  private func applyIcon(named name: String) -> Bool {
    if name == Self.defaultIconName {
      // nil tells AppKit to reload the signed bundle icon (Pengram.icns).
      // NSImage.applicationIconName can resolve to the current runtime image
      // after it has been changed, so it isn't suitable for resetting.
      NSApplication.shared.applicationIconImage = nil
      NSApplication.shared.dockTile.display()
      return true
    }

    let asset = "assets/app_icons/\(name).png"
    let assetKey = registrar.lookupKey(forAsset: asset)
    guard
      let appBundle = Self.flutterAppBundle(),
      let resourceRoot = appBundle.resourceURL
    else {
      return false
    }
    let assetURL = resourceRoot.appendingPathComponent(assetKey)
    guard
      FileManager.default.fileExists(atPath: assetURL.path),
      let source = NSImage(contentsOf: assetURL)
    else {
      return false
    }

    NSApplication.shared.applicationIconImage = Self.roundedDockIcon(source)
    NSApplication.shared.dockTile.display()
    return true
  }

  private static func flutterAppBundle() -> Bundle? {
    if let loaded = Bundle(identifier: "io.flutter.flutter.app") {
      return loaded
    }
    guard let frameworksPath = Bundle.main.privateFrameworksPath else {
      return nil
    }
    return Bundle(
      path: (frameworksPath as NSString).appendingPathComponent("App.framework")
    )
  }

  /// Flutter's picker artwork is square. AppKit does not mask runtime Dock
  /// icons, so clip it to the same rounded silhouette as the bundled icon.
  private static func roundedDockIcon(_ source: NSImage) -> NSImage {
    let canvasSize = NSSize(width: 1024, height: 1024)
    let target = NSImage(size: canvasSize)
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    let bounds = NSRect(origin: .zero, size: canvasSize)
    NSBezierPath(
      roundedRect: bounds,
      xRadius: canvasSize.width * 0.225,
      yRadius: canvasSize.height * 0.225
    ).addClip()
    source.draw(
      in: bounds,
      from: NSRect(origin: .zero, size: source.size),
      operation: .copy,
      fraction: 1
    )
    target.unlockFocus()
    target.isTemplate = false
    return target
  }

  private static func persistedIconName() -> String {
    let stored = UserDefaults.standard.string(forKey: selectedIconKey)
    return isValidIconName(stored) ? stored! : defaultIconName
  }

  private static func isValidIconName(_ name: String?) -> Bool {
    guard let name else { return false }
    return name == defaultIconName || assetNames.contains(name)
  }
}
