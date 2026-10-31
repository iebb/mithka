# Mithka app proxy

The Rust library embeds Leaf inside Mithka. It binds TCP listeners on IPv4
loopback: TDLib uses SOCKS5, and Dart HTTP and supported WebViews use HTTP.
It does not configure a system proxy, TUN, VPN, NetworkExtension or VpnService.

## Supported profiles

| Protocol | Settings | Transports |
| --- | --- | --- |
| Shadowsocks | AEAD: AES-128-GCM, AES-256-GCM, ChaCha20-IETF-Poly1305 | TCP |
| Trojan | Password, verified TLS, optional SNI | TLS, WebSocket over TLS |
| VLESS | UUID, optional verified TLS and SNI | TCP, TLS, WebSocket, WebSocket over TLS |
| VLESS Vision | UUID, `xtls-rprx-vision`, verified TLS | TCP over TLS |
| VMess | AEAD headers; AES-128-GCM or ChaCha20-Poly1305 body encryption | TCP, TLS, WebSocket, WebSocket over TLS |

Vision supports the server's raw downlink transition. Uplink padding ends after
the first block and uplink data continues inside TLS; it does not implement the
uplink raw-copy optimization or TLS fingerprint impersonation.

The editor and confirmed share-link import support `ss://` (SIP002 and legacy),
`trojan://`, `vless://` and VMess v2 base64 JSON. Unsupported transports, REALITY,
SS plugins/2022 ciphers, insecure TLS and legacy VMess alter IDs are rejected.
Credentials and the encrypted-profile catalog use Flutter secure storage.

The library is bundled for Android (arm64, armv7, x86_64), iOS (arm64 device and
arm64/x86_64 simulator), and macOS (arm64 and x86_64). The encrypted-proxy editor
is hidden on Windows and Linux. Desktop child engines follow the primary
engine's process-wide route; encrypted proxies are managed in the main window.

## Routing and fallbacks

Each TDLib account keeps its own tunnel reference. The foreground account's
tunnel supplies the shared Dart HTTP and WebView route. The service rechecks
listeners on resume, restarts failed tunnels and updates the managed TDLib rows.
Native SOCKS5, HTTP and MTProto proxies keep their existing TDLib behavior.

Per-app WebView routing requires iOS 17+, macOS 14+, or an Android WebView
provider with `PROXY_OVERRIDE`. Older browsers load directly and show a notice.
Initial page loads wait up to 10 seconds for a route being applied, then proceed
with a "may not use proxy" notice. A failed configured tunnel does not add a
DIRECT fallback to the proxy rules. Existing WebView connections may retain
their earlier route after a setting changes.

Only connections using TDLib, Dart `HttpClient`, and the app's WebViews use this
route. Native media engines, other networking libraries and external browsers
are not intercepted. Dart HTTP can connect directly before the saved proxy has
finished restoring at startup. Loopback requests bypass the Dart HTTP proxy.
The listeners are process-owned but unauthenticated, so another local process
can connect while they run. macOS sandbox release builds need the ordinary
`com.apple.security.network.server` entitlement for these listeners.

## Build and verify

Install Rust using rustup, then run the usual Flutter build. `hook/build.dart`
builds only the selected Leaf features, with `opt-level=z`, fat LTO, one codegen
unit and stripped symbols. It enforces a **5,000,000-byte installed library limit
per architecture** and Android's 16 KiB page alignment. The budget excludes
Flutter, TDLib and other app assets. Cargo versions are pinned by `Cargo.lock`.
No Rust compilation is performed on the user's device.

From this package directory:

```sh
cargo test --release --locked --manifest-path native/Cargo.toml
cargo build --release --locked --manifest-path native/Cargo.toml --lib
python3 -I tool/interop.py --xray /absolute/path/to/xray
```

The optional reference-server test uses a supplied Xray binary, curl and
openssl. It creates only loopback listeners and temporary test credentials.
It tests 18 protocol/transport/cipher combinations with HTTP and TLS 1.3 HTTPS,
2 MiB downloads and 2 MiB uploads. Its self-signed server is allowed only by the
test fixture's native configuration; the app always generates verified TLS.

Upstream provenance, local modifications and licensing are in
`native/vendor/UPSTREAM` and `native/vendor/LEAF-LICENSE`. The package `LICENSE`
also collects resolved Cargo dependency notices for Flutter's license screen.
After changing Cargo dependencies, run `python3 tool/update_licenses.py`.
