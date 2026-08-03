#!/bin/bash

set -euo pipefail

if [[ "${PLATFORM_NAME:-macosx}" != "macosx" ]]; then
  exit 0
fi

frameworks_directory="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${FRAMEWORKS_FOLDER_PATH:?FRAMEWORKS_FOLDER_PATH is required}"
mdk_framework="$frameworks_directory/mdk.framework"
mdk_binary="$mdk_framework/Versions/A/mdk"

if [[ ! -f "$mdk_binary" ]]; then
  echo "error: Embedded MDK binary not found at $mdk_binary" >&2
  exit 1
fi

has_rpath() {
  local load_commands
  load_commands="$(/usr/bin/otool -l "$mdk_binary")"
  [[ "$load_commands" == *"path $1 (offset"* ]]
}

for development_rpath in /opt/homebrew/lib /usr/local/lib; do
  if has_rpath "$development_rpath"; then
    /usr/bin/xcrun install_name_tool \
      -delete_rpath "$development_rpath" \
      "$mdk_binary"
  fi
done

for development_rpath in /opt/homebrew/lib /usr/local/lib; do
  if has_rpath "$development_rpath"; then
    echo "error: Failed to remove MDK development rpath: $development_rpath" >&2
    exit 1
  fi
done

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" ]]; then
  signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
  fi

  # mdk.framework ships executable codec dylibs inside the framework bundle.
  # A framework-level signature does not replace those nested signatures, so
  # sign them inner-first with the same identity as the archive. Otherwise a
  # distribution archive can retain the SDK's ad-hoc nested signatures and be
  # rejected during App Store validation.
  while IFS= read -r -d '' nested_dylib; do
    /usr/bin/codesign \
      --force \
      --sign "$signing_identity" \
      --preserve-metadata=identifier,entitlements,requirements,flags,runtime \
      "$nested_dylib"
  done < <(
    /usr/bin/find "$mdk_framework/Versions/A" \
      -maxdepth 1 -type f -name '*.dylib' -print0
  )

  /usr/bin/codesign \
    --force \
    --sign "$signing_identity" \
    --preserve-metadata=identifier,entitlements,requirements,flags,runtime \
    "$mdk_framework"
fi

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" ]]; then
  while IFS= read -r -d '' nested_dylib; do
    /usr/bin/codesign --verify --strict "$nested_dylib"
  done < <(
    /usr/bin/find "$mdk_framework/Versions/A" \
      -maxdepth 1 -type f -name '*.dylib' -print0
  )
  /usr/bin/codesign --verify --deep --strict "$mdk_framework"
fi

echo "Sanitized embedded MDK development rpaths"
