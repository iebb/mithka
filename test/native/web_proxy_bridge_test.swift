import Foundation
import WebKit

/// Compiles the production rules in WebKit, whose regex subset differs from
/// Foundation's. Run via scripts/tests/web_proxy_apple_test.sh on macOS.
@main
struct WebProxyBridgeTest {
  static func main() {
    let cases = [
      ("https://relay.example", "/"),
      ("https://relay.example:443", "/relay/v2/"),
      ("https://relay.example:8443", "/relay_test-v2/"),
    ]
    var remaining = cases.count
    for (index, item) in cases.enumerated() {
      let rules = WebProxyBridge.contentRules(origin: URL(string: item.0)!, prefix: item.1)
      let data = try! JSONSerialization.data(withJSONObject: rules)
      let identifier = "mithka-web-proxy-test-\(UUID().uuidString)"
      WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: identifier, encodedContentRuleList: String(data: data, encoding: .utf8)!
      ) { list, error in
        guard list != nil, error == nil else {
          print("Web proxy rule compilation failed for test case \(index)")
          exit(1)
        }
        WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in
          remaining -= 1
          if remaining == 0 {
            print("WebKit compiled all three production relay restriction rule sets")
            exit(0)
          }
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
      print("WebKit rule compilation timed out")
      exit(1)
    }
    RunLoop.main.run()
  }
}
