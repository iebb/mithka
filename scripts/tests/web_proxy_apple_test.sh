#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
flutter_bin="${FLUTTER_ROOT:-$(cd "$(dirname "$(command -v flutter)")/.." && pwd)}"
if [[ ! -d "$flutter_bin/bin/cache" ]]; then
  flutter_bin="$(python3 -c 'import os,sys; print(os.path.dirname(os.path.dirname(os.path.realpath(sys.argv[1]))))' "$(command -v flutter)")"
fi
framework_dir="$flutter_bin/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc \
  -F "$framework_dir" -framework FlutterMacOS \
  -Xlinker -rpath -Xlinker "$framework_dir" \
  "$repo_root/apple/WebProxyBridge.swift" \
  "$repo_root/test/native/web_proxy_bridge_test.swift" \
  -o "$test_dir/web_proxy_bridge_test"
"$test_dir/web_proxy_bridge_test"
