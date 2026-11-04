#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import WebKit

/// Transport-only views have an isolated data store and no application UI.
/// Never propagate WebKit errors: their descriptions can contain the capability URL.
final class WebProxyBridge {
  private let channel: FlutterMethodChannel
  private var carriers: [String: WebProxyCarrier] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mithka/web_proxy", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  static func contentRules(origin: URL, prefix: String) -> [[String: Any]] {
    let host = NSRegularExpression.escapedPattern(for: origin.host!)
    let path = NSRegularExpression.escapedPattern(for: prefix)
    let port = origin.port.flatMap { $0 == 443 ? nil : ":\($0)" } ?? "(:443)?"
    var rules: [[String: Any]] = [
      ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
    ]
    // WebKit's content-rule regex subset doesn't support alternation.
    for scheme in ["https", "wss"] {
      rules.append([
        "trigger": [
          "url-filter": "^\(scheme)://\(host)\(port)\(path)",
          "url-filter-is-case-sensitive": true,
        ],
        "action": ["type": "ignore-previous-rules"],
      ])
    }
    return rules
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let key = args["key"] as? String else {
      result(FlutterError(code: "invalid_carrier", message: nil, details: nil))
      return
    }
    switch call.method {
    case "open":
      guard carriers[key] == nil,
            let urlString = args["url"] as? String, let url = URL(string: urlString),
            let origin = args["origin"] as? String,
            let prefix = args["pathPrefix"] as? String,
            let script = args["script"] as? String,
            let carrier = WebProxyCarrier(
              key: key, url: url, origin: origin, prefix: prefix, script: script, channel: channel
            ) else {
        result(FlutterError(code: "invalid_carrier", message: nil, details: nil))
        return
      }
      carriers[key] = carrier
      carrier.open { success in
        result(success ? nil : FlutterError(code: "carrier_failed", message: nil, details: nil))
      }
    case "deliver":
      guard let carrier = carriers[key], let script = args["script"] as? String else {
        result(FlutterError(code: "missing_carrier", message: nil, details: nil))
        return
      }
      carrier.evaluate(script, result: result)
    case "close":
      guard let carrier = carriers.removeValue(forKey: key) else { result(nil); return }
      carrier.closing = true
      let script = args["script"] as? String ?? ""
      let notify = carrier.sentMessage || !script.isEmpty
      if notify {
        let closeScript = script.isEmpty
          ? "window.TelegramWebProxy?.onmessage?.({data:'{\"t\":\"close\"}'});"
          : script
        carrier.webView?.evaluateJavaScript(closeScript, completionHandler: nil)
      }
      let delay = notify ? 200 : 0
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
        carrier.destroy()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private final class WebProxyCarrier: NSObject, WKNavigationDelegate, WKUIDelegate,
  WKScriptMessageHandler {
  let key: String
  let url: URL
  let origin: URL
  let prefix: String
  let script: String
  let channel: FlutterMethodChannel
  var webView: WKWebView?
  var closing = false
  var sentMessage = false
  private var failed = false
  private var openingResult: ((Bool) -> Void)?

  init?(key: String, url: URL, origin: String, prefix: String, script: String,
        channel: FlutterMethodChannel) {
    guard let base = URL(string: origin), base.scheme == "https", base.host != nil,
          base.user == nil, base.password == nil,
          (base.path.isEmpty || base.path == "/"),
          base.query == nil, base.fragment == nil,
          prefix.hasPrefix("/"), prefix.hasSuffix("/"),
          !prefix.contains(".."), !prefix.contains("%") else { return nil }
    self.key = key
    self.url = url
    self.origin = base
    self.prefix = prefix
    self.script = script
    self.channel = channel
    super.init()
    guard allows(url) else { return nil }
  }

  private func allows(_ candidate: URL) -> Bool {
    candidate.scheme == "https" && candidate.host == origin.host &&
      (candidate.port ?? 443) == (origin.port ?? 443) &&
      candidate.user == nil && candidate.password == nil &&
      candidate.path.hasPrefix(prefix) &&
      !candidate.absoluteString.lowercased().contains("%2f") &&
      !candidate.absoluteString.lowercased().contains("%5c") &&
      !candidate.path.split(separator: "/").contains("..")
  }

  func open(completion: @escaping (Bool) -> Void) {
    openingResult = completion
    // Resource loads, including fetch, are restricted in WebKit itself. Frames,
    // popups and main-document redirects are additionally checked below.
    let rules = WebProxyBridge.contentRules(origin: origin, prefix: prefix)
    guard let data = try? JSONSerialization.data(withJSONObject: rules),
          let json = String(data: data, encoding: .utf8) else { finishOpening(false); return }
    let identifier = "mithka-web-proxy-\(UUID().uuidString)"
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: identifier, encodedContentRuleList: json
    ) { [weak self] ruleList, _ in
      guard let self else { return }
      guard let ruleList, !self.closing else { self.finishOpening(false); return }
      let config = WKWebViewConfiguration()
      config.websiteDataStore = .nonPersistent()
      config.preferences.javaScriptCanOpenWindowsAutomatically = false
      config.userContentController.add(ruleList)
      WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in }
      config.userContentController.add(self, name: "mithkaWebProxy")
      config.userContentController.addUserScript(WKUserScript(
        source: self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true
      ))
      let view = WKWebView(frame: .zero, configuration: config)
      view.navigationDelegate = self
      view.uiDelegate = self
      self.webView = view
      view.load(URLRequest(url: self.url))
      self.finishOpening(true)
    }
  }

  private func finishOpening(_ success: Bool) {
    let completion = openingResult
    openingResult = nil
    completion?(success)
  }

  func evaluate(_ script: String, result: @escaping FlutterResult) {
    guard let webView, !closing, !failed else {
      result(FlutterError(code: "carrier_closed", message: nil, details: nil))
      return
    }
    webView.evaluateJavaScript(script) { _, error in
      result(error == nil ? nil : FlutterError(code: "carrier_delivery", message: nil, details: nil))
    }
  }

  func destroy() {
    closing = true
    finishOpening(false)
    webView?.stopLoading()
    webView?.configuration.userContentController.removeScriptMessageHandler(forName: "mithkaWebProxy")
    webView?.navigationDelegate = nil
    webView?.uiDelegate = nil
    webView = nil
  }

  private func fail(terminated: Bool = false) {
    guard !closing, !failed else { return }
    failed = true
    channel.invokeMethod("error", arguments: ["key": key, "terminated": terminated])
  }

  func userContentController(_ userContentController: WKUserContentController,
                             didReceive message: WKScriptMessage) {
    guard !closing, !failed, message.frameInfo.isMainFrame,
          let frameURL = message.frameInfo.request.url, allows(frameURL),
          message.frameInfo.securityOrigin.protocol == "https",
          message.frameInfo.securityOrigin.host == origin.host,
          let body = message.body as? String else { return }
    sentMessage = true
    channel.invokeMethod("message", arguments: ["key": key, "message": body])
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard navigationAction.targetFrame?.isMainFrame == true,
          let target = navigationAction.request.url, allows(target) else {
      decisionHandler(.cancel)
      fail()
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    guard let target = navigationResponse.response.url, allows(target),
          (navigationResponse.response as? HTTPURLResponse).map({ (200..<400).contains($0.statusCode) }) ?? false else {
      decisionHandler(.cancel)
      fail()
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
               withError error: Error) { fail() }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
               withError error: Error) { fail() }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail(terminated: true) }

  @available(iOS 15.0, macOS 12.0, *)
  func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
               initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
               decisionHandler: @escaping (WKPermissionDecision) -> Void) {
    decisionHandler(.deny)
  }
}
