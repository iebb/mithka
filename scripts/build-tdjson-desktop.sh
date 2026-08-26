#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  echo "usage: $0 <linux|macos|windows> OUTPUT_LIBRARY [ARCHITECTURE]" >&2
  exit 2
fi

PLATFORM="$1"
OUTPUT_LIBRARY="$2"
ARCHITECTURE="${3:-}"
# Linux and Windows publish one asset per architecture; macOS ships a single
# fat arm64+x86_64 library.
case "$PLATFORM" in
  linux|windows)
    ARCHITECTURE="${ARCHITECTURE:-x64}"
    case "$ARCHITECTURE" in
      x64|arm64) ;;
      *)
        echo "error: unsupported $PLATFORM architecture: $ARCHITECTURE" >&2
        exit 2
        ;;
    esac
    ASSET="tdjson-$PLATFORM-$ARCHITECTURE.zip"
    if [[ "$PLATFORM" == linux ]]; then
      MEMBER=libtdjson.so
    else
      MEMBER=tdjson.dll
    fi
    ;;
  macos)
    ARCHITECTURE="${ARCHITECTURE:-universal}"
    if [[ "$ARCHITECTURE" != universal ]]; then
      echo "error: macOS tdjson is always universal, got: $ARCHITECTURE" >&2
      exit 2
    fi
    ASSET=tdjson-macos-universal.zip
    MEMBER=libtdjson.dylib
    ;;
  *)
    echo "error: unsupported desktop platform: $PLATFORM" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "error: Python 3 is required to install tdjson artifacts" >&2
  exit 1
fi

"$PYTHON" "$SCRIPT_DIR/install-tdjson-artifact.py" \
  "$ASSET" "$OUTPUT_LIBRARY" --member "$MEMBER" --mode 0755

verify_library() {
  local library="$1"
  local symbols
  test -s "$library"
  case "$PLATFORM" in
    linux)
      symbols="$(nm -D "$library")"
      for symbol in \
        td_create_client_id \
        td_mithka_export_session_string \
        td_mithka_import_session_string \
        td_mithka_last_error \
        td_mithka_set_transfer_boost; do
        grep " $symbol$" <<<"$symbols" >/dev/null
      done
      if ldd "$library" | grep -q 'not found'; then
        ldd "$library" >&2
        return 1
      fi
      local machine expected_machine
      machine="$(
        readelf -h "$library" \
          | awk -F: '/^[[:space:]]*Machine:/ { sub(/^[[:space:]]+/, "", $2); print $2 }'
      )"
      case "$ARCHITECTURE" in
        x64) expected_machine='Advanced Micro Devices X86-64' ;;
        arm64) expected_machine='AArch64' ;;
      esac
      if [[ "$machine" != "$expected_machine" ]]; then
        echo "error: expected an $expected_machine ELF, got: $machine" >&2
        return 1
      fi
      ;;
    macos)
      symbols="$(nm -gU "$library")"
      for symbol in \
        _td_create_client_id \
        _td_mithka_export_session_string \
        _td_mithka_import_session_string \
        _td_mithka_last_error \
        _td_mithka_set_transfer_boost; do
        grep " $symbol$" <<<"$symbols" >/dev/null
      done
      test "$(lipo -archs "$library" | tr ' ' '\n' | sort | tr '\n' ' ')" = \
        "arm64 x86_64 "
      for architecture in arm64 x86_64; do
        otool -D -arch "$architecture" "$library" | \
          grep -Fx '@rpath/libtdjson.dylib' >/dev/null
      done
      if otool -L "$library" | grep -Eq '/opt/homebrew|/usr/local'; then
        otool -L "$library" >&2
        return 1
      fi
      ;;
    windows)
      # The release workflow verifies exports after Visual Studio initializes
      # the Windows developer environment.
      ;;
  esac
}

verify_library "$OUTPUT_LIBRARY"
echo "Installed pinned $PLATFORM $ARCHITECTURE tdjson: $OUTPUT_LIBRARY"
