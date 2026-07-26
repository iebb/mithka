#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_LIBRARY="$REPO_ROOT/native-libs/libtdjson.dylib"

if [[ ! -s "$SOURCE_LIBRARY" ]]; then
  "$SCRIPT_DIR/build-tdjson-desktop.sh" macos "$SOURCE_LIBRARY"
fi

: "${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}"
: "${FRAMEWORKS_FOLDER_PATH:?FRAMEWORKS_FOLDER_PATH is required}"

FRAMEWORKS_DIR="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
DESTINATION_LIBRARY="$FRAMEWORKS_DIR/libtdjson.dylib"
mkdir -p "$FRAMEWORKS_DIR"
install -m 0755 "$SOURCE_LIBRARY" "$DESTINATION_LIBRARY"

if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
    --preserve-metadata=identifier,entitlements,flags \
    "$DESTINATION_LIBRARY"
else
  codesign --force --sign - "$DESTINATION_LIBRARY"
fi
