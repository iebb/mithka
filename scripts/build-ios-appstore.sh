#!/usr/bin/env bash
#
# Builds an App Store Connect IPA with the same hybrid native setup expected by
# Xcode Cloud: Swift Package Manager for compatible Flutter plugins and
# CocoaPods for the remaining unsupported/local plugins.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Xcode's /usr/bin/openrsync can spawn "rsync --server" through PATH during IPA
# export. Keep /usr/bin first so it does not pair with Homebrew rsync 3.x, which
# rejects Apple's extended-attributes flags and causes "exportArchive Copy failed".
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

echo "== Xcode =="
xcodebuild -version

echo "== Flutter setup =="
flutter config --enable-swift-package-manager
flutter pub get

echo "== CocoaPods =="
(cd ios && pod install)

echo "== Build IPA =="
flutter build ipa --release --export-options-plist=ios/ExportOptions.app-store-connect.plist

ARCHIVE="$REPO_ROOT/build/ios/archive/Runner.xcarchive"
TDJSON_DSYM="$ARCHIVE/dSYMs/tdjson.framework.dSYM"
TDJSON_BINARY="$ARCHIVE/Products/Applications/Runner.app/Frameworks/tdjson.framework/tdjson"
BINARY_UUID="$(/usr/bin/dwarfdump --uuid "$TDJSON_BINARY" | awk 'NR == 1 { print $2 }')"
DSYM_UUID="$(/usr/bin/dwarfdump --uuid "$TDJSON_DSYM" | awk 'NR == 1 { print $2 }')"

if [[ -z "$BINARY_UUID" || "$DSYM_UUID" != "$BINARY_UUID" ]]; then
  echo "error: tdjson binary and dSYM UUIDs do not match" >&2
  exit 1
fi

echo "== Export IPA =="
rm -rf "$REPO_ROOT/build/ios/ipa-appstore"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$REPO_ROOT/build/ios/ipa-appstore" \
  -exportOptionsPlist ios/ExportOptions.app-store-connect.plist

IPA="$(find "$REPO_ROOT/build/ios/ipa-appstore" -maxdepth 1 -name '*.ipa' -print | sort | tail -1)"
if [[ -z "$IPA" ]]; then
  echo "error: no IPA found under build/ios/ipa-appstore" >&2
  exit 1
fi

IPA_LISTING="$REPO_ROOT/build/ios/ipa-appstore/contents.txt"
unzip -Z1 "$IPA" > "$IPA_LISTING"
if ! grep -Eq '^SwiftSupport/iphoneos/libswift.+\.dylib$' "$IPA_LISTING"; then
  echo "error: exported IPA is missing SwiftSupport/iphoneos (ITMS-90426)" >&2
  exit 1
fi

echo "OK: $IPA"
echo "OK: tdjson binary and dSYM UUIDs match"
echo "OK: SwiftSupport/iphoneos is present"
