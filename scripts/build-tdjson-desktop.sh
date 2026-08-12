#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <linux|macos|windows> OUTPUT_LIBRARY" >&2
  exit 2
fi

PLATFORM="$1"
OUTPUT_LIBRARY="$2"
case "$PLATFORM" in
  linux)
    ASSET=tdjson-linux-x64.zip
    MEMBER=libtdjson.so
    ;;
  macos)
    ASSET=tdjson-macos-universal.zip
    MEMBER=libtdjson.dylib
    ;;
  windows)
    ASSET=tdjson-windows-x64.zip
    MEMBER=tdjson.dll
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
echo "Installed pinned $PLATFORM tdjson: $OUTPUT_LIBRARY"
