#!/usr/bin/env bash
# Thin a signed universal Mithka.app to one architecture and re-sign it ad hoc.
#
# Usage: scripts/thin-macos-app.sh <universal.app> <arm64|x86_64> <output.app>
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <universal.app> <arm64|x86_64> <output.app>" >&2
  exit 2
fi

source_app="${1%/}"
arch="$2"
out_app="${3%/}"
entitlements="${ENTITLEMENTS:-macos/Runner/Release.entitlements}"

case "$arch" in
  arm64|x86_64) ;;
  *) echo "error: unsupported architecture: $arch" >&2; exit 2 ;;
esac
[[ -d "$source_app/Contents" ]] || { echo "error: not an app bundle: $source_app" >&2; exit 2; }
[[ -f "$entitlements" ]] || { echo "error: missing entitlements: $entitlements" >&2; exit 2; }
[[ ! -e "$out_app" ]] || { echo "error: output already exists: $out_app" >&2; exit 2; }

mkdir -p "$(dirname "$out_app")"
ditto "$source_app" "$out_app"

# Thin every fat Mach-O in place. A missing slice is a hard error rather than
# a silently larger or broken download.
while IFS= read -r -d '' file; do
  archs="$(lipo -archs "$file" 2>/dev/null || true)"
  [[ "$archs" == *" "* ]] || continue
  if [[ " $archs " != *" $arch "* ]]; then
    echo "error: $file has no $arch slice ($archs)" >&2
    exit 1
  fi
  mode="$(stat -f %Lp "$file")"
  lipo -thin "$arch" "$file" -output "$file.thin"
  chmod "$mode" "$file.thin"
  mv -f "$file.thin" "$file"
done < <(find "$out_app" -type f -print0)

# Re-sign from the inside out: dylibs inside frameworks, the frameworks, loose
# dylibs, and finally the app so its seal covers everything.
frameworks="$out_app/Contents/Frameworks"
while IFS= read -r -d '' framework; do
  while IFS= read -r -d '' dylib; do
    codesign --force --sign - "$dylib"
  done < <(find "$framework/Versions" -mindepth 2 -maxdepth 2 -type f -name '*.dylib' -print0)
  codesign --force --sign - "$framework"
done < <(find "$frameworks" -mindepth 1 -maxdepth 1 -type d -name '*.framework' -print0)
while IFS= read -r -d '' dylib; do
  codesign --force --sign - "$dylib"
done < <(find "$frameworks" -mindepth 1 -maxdepth 1 -type f -name '*.dylib' -print0)
codesign --force --sign - --entitlements "$entitlements" "$out_app"

# Verify: one slice everywhere, and a valid seal.
while IFS= read -r -d '' file; do
  archs="$(lipo -archs "$file" 2>/dev/null || true)"
  [[ -z "$archs" || "$archs" == "$arch" ]] || {
    echo "error: $file still has architectures: $archs" >&2
    exit 1
  }
done < <(find "$out_app" -type f -print0)
codesign --verify --deep --strict "$out_app"
echo "thinned $source_app -> $out_app ($arch)"
