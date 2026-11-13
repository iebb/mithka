import Cocoa
import FlutterMacOS

/// Hands a link Mithka could not open in-app to another app, never back to
/// Mithka.
///
/// Mithka registers the tg:// scheme (Info.plist CFBundleURLSchemes), so a
/// plain `NSWorkspace.open(_:)` of a tg:// link Mithka could not route may
/// resolve straight back to Mithka. `openExternally` asks Launch Services for
/// every handler of the URL, drops Mithka's own bundle, and opens the URL with
/// the system default handler when that is another app, otherwise with the
/// first other handler. It answers false when no other app can open the URL,
/// so Dart shows a notice instead.
///
/// Uses only public NSWorkspace APIs (macOS 12+, the deployment target), which
/// need no extra entitlement under the App Sandbox.
final class ExternalLinksPlugin: NSObject, FlutterPlugin {
  static let channelName = "mithka/external_links"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger
    )
    let instance = ExternalLinksPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openExternally":
      let arguments = call.arguments as? [String: Any]
      guard
        let raw = arguments?["url"] as? String,
        let url = URL(string: raw),
        let scheme = url.scheme, !scheme.isEmpty
      else {
        result(false)
        return
      }
      Self.openExternally(url) { opened in result(opened) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The handler to use for [url], or nil when only Mithka can open it.
  static func otherHandler(
    for url: URL,
    workspace: NSWorkspace = .shared,
    ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
    ownBundleURL: URL = Bundle.main.bundleURL
  ) -> URL? {
    func isOwn(_ application: URL) -> Bool {
      if application.standardizedFileURL == ownBundleURL.standardizedFileURL {
        return true
      }
      guard let own = ownBundleIdentifier,
        let identifier = Bundle(url: application)?.bundleIdentifier
      else { return false }
      return identifier.caseInsensitiveCompare(own) == .orderedSame
    }

    if let preferred = workspace.urlForApplication(toOpen: url), !isOwn(preferred) {
      return preferred
    }
    return workspace.urlsForApplications(toOpen: url).first { !isOwn($0) }
  }

  static func openExternally(
    _ url: URL,
    workspace: NSWorkspace = .shared,
    completion: @escaping (Bool) -> Void
  ) {
    guard let application = otherHandler(for: url, workspace: workspace) else {
      completion(false)
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    workspace.open(
      [url],
      withApplicationAt: application,
      configuration: configuration
    ) { _, error in
      if let error {
        NSLog("Mithka: unable to open link outside Mithka: \(error)")
      }
      DispatchQueue.main.async { completion(error == nil) }
    }
  }
}
