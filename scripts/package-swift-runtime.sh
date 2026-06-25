#!/usr/bin/env bash
#
# Ensures an iOS archive contains matching Swift runtime dylibs in both:
#   Products/Applications/*.app/Frameworks
#   SwiftSupport/iphoneos
#
# Xcode 26 can filter these out of the app bundle for modern iOS deployment
# targets, but App Store Connect still validates SwiftSupport against the app's
# Frameworks directory.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 path/to/Runner.xcarchive" >&2
  exit 64
fi

ARCHIVE="$1"
if [[ ! -d "$ARCHIVE" ]]; then
  echo "error: archive not found: $ARCHIVE" >&2
  exit 1
fi

APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' -type d | head -1)"
if [[ -z "$APP" ]]; then
  echo "error: no .app found in $ARCHIVE" >&2
  exit 1
fi

TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
SWIFT_LIB_DIR="$TOOLCHAIN/usr/lib/swift-5.0/iphoneos"
if [[ ! -d "$SWIFT_LIB_DIR" ]]; then
  echo "error: Swift runtime directory not found: $SWIFT_LIB_DIR" >&2
  exit 1
fi

APP_FRAMEWORKS="$APP/Frameworks"
SUPPORT_DIR="$ARCHIVE/SwiftSupport/iphoneos"
mkdir -p "$APP_FRAMEWORKS" "$SUPPORT_DIR"

SWIFT_LIBS=()
while IFS= read -r lib; do
  SWIFT_LIBS+=("$lib")
done < <(
  find "$APP" -type f -print0 |
    while IFS= read -r -d '' bin; do
      /usr/bin/otool -L "$bin" 2>/dev/null || true
    done |
    /usr/bin/awk '/(@rpath|\/usr\/lib\/swift)\/libswift.*\.dylib/ { print $1 }' |
    /usr/bin/sed 's#^@rpath/##; s#^/usr/lib/swift/##' |
    /usr/bin/sort -u
)

if [[ ${#SWIFT_LIBS[@]} -eq 0 ]]; then
  echo "No Swift dylib references found; leaving archive unchanged."
  exit 0
fi

COPIED=0
for lib in "${SWIFT_LIBS[@]}"; do
  src="$SWIFT_LIB_DIR/$lib"
  if [[ ! -f "$src" ]]; then
    echo "warning: Swift runtime not in support directory, skipping $lib" >&2
    continue
  fi
  /bin/cp -f "$src" "$APP_FRAMEWORKS/$lib"
  /bin/cp -f "$src" "$SUPPORT_DIR/$lib"
  COPIED=$((COPIED + 1))
done

if [[ "$COPIED" -eq 0 ]]; then
  echo "error: no Swift runtime dylibs were copied from $SWIFT_LIB_DIR" >&2
  exit 1
fi

echo "Packaged $COPIED Swift runtime dylibs into $ARCHIVE"
