#!/usr/bin/env bash
#
# Downloads checksum-pinned TDLib Android libraries into jniLibs, where the
# Android Gradle plugin bundles them automatically.
#
# Usage:
#   ./scripts/build-tdjson-android.sh [abi ...]
#   (default ABIs: arm64-v8a armeabi-v7a x86_64)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JNI_DIR="$REPO_ROOT/android/app/src/main/jniLibs"

if [[ "$#" -gt 0 ]]; then
  ABIS=("$@")
else
  ABIS=(arm64-v8a armeabi-v7a x86_64)
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "error: Python 3 is required to install tdjson artifacts" >&2
  exit 1
fi

for ABI in "${ABIS[@]}"; do
  case "$ABI" in
    arm64-v8a|armeabi-v7a|x86_64) ;;
    *)
      echo "error: unsupported Android ABI: $ABI" >&2
      exit 2
      ;;
  esac
  "$PYTHON" "$SCRIPT_DIR/install-tdjson-artifact.py" \
    "tdjson-android-$ABI.zip" \
    "$JNI_DIR/$ABI/libtdjson.so" \
    --member "$ABI/libtdjson.so" \
    --mode 0644
done

echo "Installed pinned Android tdjson libraries. Run: flutter run"
