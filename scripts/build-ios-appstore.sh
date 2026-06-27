#!/usr/bin/env bash
#
# Builds an App Store Connect IPA with the same native setup expected by Xcode
# Cloud: CocoaPods only, no Flutter Swift Package Manager integration.
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
flutter config --no-enable-swift-package-manager
flutter pub get

echo "== CocoaPods =="
(cd ios && pod install)

echo "== Build IPA =="
flutter build ipa --release --export-options-plist=ios/ExportOptions.app-store-connect.plist

ARCHIVE="$REPO_ROOT/build/ios/archive/Runner.xcarchive"
TDJSON_DSYM="$ARCHIVE/dSYMs/libtdjson.1.8.65.dylib.dSYM"
EXPECTED_UUID="CE86A2AF-6906-3CDF-B0F1-5494F3271F7D"

if ! /usr/bin/dwarfdump --uuid "$TDJSON_DSYM" | grep -q "$EXPECTED_UUID"; then
  echo "error: $TDJSON_DSYM does not contain expected UUID $EXPECTED_UUID" >&2
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

echo "OK: $IPA"
echo "OK: tdjson dSYM UUID $EXPECTED_UUID"
echo "OK: Swift runtime packaging left to xcodebuild -exportArchive"
