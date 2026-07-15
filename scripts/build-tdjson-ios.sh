#!/usr/bin/env bash
#
# build-tdjson-ios.sh
#
# Fetches TDLib's `tdjson` XCFramework for iOS (device arm64 + simulator) and
# installs it into the Runner app checkout, so the Dart FFI layer can resolve the
# symbols at runtime.
#
# The prebuilt artifact lives in the sibling mithka-tdjson repo. By default this
# downloads the pinned artifact with Mithka session string backup symbols; set
# TDJSON_XCFRAMEWORK_URL to override the source.
#
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/ios/tdjson"
TDJSON_RELEASE_TAG="tdlib-1.8.66-07d3a0973f51"
TDJSON_URL="${TDJSON_XCFRAMEWORK_URL:-https://github.com/iebb/mithka-tdjson/releases/download/${TDJSON_RELEASE_TAG}/tdjson-ios.xcframework.zip}"

download_tdjson() {
  echo "  → downloading tdjson.xcframework"
  mkdir -p "$DEST"
  rm -rf "$DEST/tdjson.xcframework"
  tmp="$(mktemp "${TMPDIR:-/tmp}/tdjson-ios.XXXXXX.zip")"
  curl -fL "$TDJSON_URL" -o "$tmp"
  unzip -q -o "$tmp" -d "$DEST"
  rm -f "$tmp"
}

echo "→ Expected: $DEST/tdjson.xcframework"
if [[ -d "$DEST/tdjson.xcframework" ]]; then
  echo "  ✓ tdjson.xcframework present"
  if ! "$REPO_ROOT/scripts/check-tdjson-session-symbols.sh" "$DEST/tdjson.xcframework"; then
    echo "  → existing tdjson.xcframework is stale; replacing it"
    download_tdjson
  fi
else
  download_tdjson
fi
"$REPO_ROOT/scripts/wrap-tdjson-xcframework.sh" "$DEST/tdjson.xcframework"
"$REPO_ROOT/scripts/check-tdjson-session-symbols.sh" "$DEST/tdjson.xcframework"
echo "→ Now run: cd ios && pod install   (then: flutter run)"
