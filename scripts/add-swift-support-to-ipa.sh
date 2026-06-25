#!/usr/bin/env bash
#
# Adds SwiftSupport/iphoneos to an App Store IPA when Xcode's export step omits
# it. This folder lives outside Payload and does not affect the app signature.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 path/to/App.ipa" >&2
  exit 64
fi

IPA="$1"
if [[ ! -f "$IPA" ]]; then
  echo "error: IPA not found: $IPA" >&2
  exit 1
fi

TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
SWIFT_LIB_DIR="$TOOLCHAIN/usr/lib/swift-5.0/iphoneos"
if [[ ! -d "$SWIFT_LIB_DIR" ]]; then
  echo "error: Swift runtime directory not found: $SWIFT_LIB_DIR" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

/usr/bin/unzip -q "$IPA" -d "$WORK"
APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -type d | head -1)"
if [[ -z "$APP" ]]; then
  echo "error: no .app found in $IPA" >&2
  exit 1
fi

SUPPORT_DIR="$WORK/SwiftSupport/iphoneos"
mkdir -p "$SUPPORT_DIR"

mapfile -t SWIFT_LIBS < <(
  find "$APP" -type f -print0 |
    while IFS= read -r -d '' bin; do
      /usr/bin/otool -L "$bin" 2>/dev/null || true
    done |
    /usr/bin/awk '/(@rpath|\/usr\/lib\/swift)\/libswift.*\.dylib/ { print $1 }' |
    /usr/bin/sed 's#^@rpath/##; s#^/usr/lib/swift/##' |
    /usr/bin/sort -u
)

if [[ ${#SWIFT_LIBS[@]} -eq 0 ]]; then
  echo "No Swift dylib references found; leaving IPA unchanged."
  exit 0
fi

COPIED=0
for lib in "${SWIFT_LIBS[@]}"; do
  src="$SWIFT_LIB_DIR/$lib"
  if [[ ! -f "$src" ]]; then
    echo "warning: Swift runtime not in support directory, skipping $lib" >&2
    continue
  fi
  /bin/cp -f "$src" "$SUPPORT_DIR/$lib"
  COPIED=$((COPIED + 1))
done

if ! find "$SUPPORT_DIR" -type f -name 'libswift*.dylib' | grep -q .; then
  echo "error: no SwiftSupport dylibs were copied from $SWIFT_LIB_DIR" >&2
  exit 1
fi

TMP_IPA="$IPA.tmp"
rm -f "$TMP_IPA"
(
  cd "$WORK"
  /usr/bin/zip -qry "$TMP_IPA" .
)
/bin/mv "$TMP_IPA" "$IPA"

echo "Added $COPIED SwiftSupport dylibs to $IPA"
