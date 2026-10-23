#!/usr/bin/env bash
#
# Installs the pinned TDLib HarmonyOS library into the ohos host project,
# where hvigor bundles entry/libs/<abi>/ natively-linked .so files into the
# HAP. Run this before `flutter build hap`. The script never signs: CI builds
# unsigned HAPs with hvigorw and signs in a later controlled step.
#
# Usage:
#   ./scripts/build-hap.sh          # install tdjson (required once per checkout)
#   flutter build hap --target-platform ohos-arm64 --release
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIBS_DIR="$REPO_ROOT/ohos/entry/libs/arm64-v8a"

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "error: Python 3 is required to install tdjson artifacts" >&2
  exit 1
fi

mkdir -p "$LIBS_DIR"

"$PYTHON" "$SCRIPT_DIR/install-tdjson-artifact.py" \
  "tdjson-ohos-arm64.zip" \
  "$LIBS_DIR/libtdjson.so" \
  --member "arm64-v8a/libtdjson.so" \
  --mode 0755

echo "Installed pinned HarmonyOS tdjson library. Run: flutter build hap --target-platform ohos-arm64 --release"
