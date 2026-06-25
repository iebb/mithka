#!/usr/bin/env bash
#
# build-tdjson-ios.sh
#
# Fetches TDLib's `tdjson` XCFramework for iOS (device arm64 + simulator) and
# installs it into the Runner app checkout, so the Dart FFI layer can resolve the
# symbols at runtime.
#
# The prebuilt artifact lives in the sibling mithka-tdjson repo. Set
# TDJSON_XCFRAMEWORK_URL to override the default download.
#
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/ios/tdjson"
TDJSON_URL="${TDJSON_XCFRAMEWORK_URL:-https://github.com/iebb/mithka-tdjson/releases/download/tdjson-1.8.65/tdjson-ios.xcframework.zip}"

echo "→ Expected: $DEST/tdjson.xcframework"
if [[ -d "$DEST/tdjson.xcframework" ]]; then
  echo "  ✓ tdjson.xcframework present"
else
  echo "  → downloading tdjson.xcframework"
  mkdir -p "$DEST"
  tmp="$(mktemp "${TMPDIR:-/tmp}/tdjson-ios.XXXXXX.zip")"
  curl -fL "$TDJSON_URL" -o "$tmp"
  unzip -q -o "$tmp" -d "$DEST"
  rm -f "$tmp"
fi
"$REPO_ROOT/scripts/wrap-tdjson-xcframework.sh" "$DEST/tdjson.xcframework"
echo "→ Now run: cd ios && pod install   (then: flutter run)"
