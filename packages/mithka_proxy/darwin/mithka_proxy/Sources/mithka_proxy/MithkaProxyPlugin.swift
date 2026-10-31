#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Network
import WebKit

/// Routes the app's default WebKit data store through the in-process proxy.
/// Every WebView and window in this process shares that store.
public final class MithkaProxyPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
    let messenger = registrar.messenger
    #else
    let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(name: "ad.neko.mithka/proxy", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(MithkaProxyPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "isSupported" {
      if #available(iOS 17.0, macOS 14.0, *) {
        result(true)
      } else {
        result(false)
      }
      return
    }
    guard call.method == "configure" else {
      result(FlutterMethodNotImplemented)
      return
    }
    // Per-app WebKit proxies need iOS 17 / macOS 14; older systems get the
    // caller's visible direct fallback.
    guard #available(iOS 17.0, macOS 14.0, *) else {
      result(false)
      return
    }
    let arguments = call.arguments as? [String: Any]
    if let number = arguments?["port"] as? NSNumber {
      guard (1...65535).contains(number.intValue),
        let port = NWEndpoint.Port(rawValue: number.uint16Value)
      else {
        result(FlutterError(code: "invalid_port", message: "Invalid proxy port", details: nil))
        return
      }
      WKWebsiteDataStore.default().proxyConfigurations = [
        ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: port))
      ]
    } else {
      WKWebsiteDataStore.default().proxyConfigurations = []
    }
    result(true)
  }
}
