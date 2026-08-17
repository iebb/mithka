#!/bin/sh
set -eu

XCFRAMEWORK="${1:-ios/tdjson/tdjson.xcframework}"

if [ ! -d "$XCFRAMEWORK" ]; then
  echo "error: tdjson.xcframework not found: $XCFRAMEWORK" >&2
  exit 1
fi

if ! command -v nm >/dev/null 2>&1; then
  echo "error: nm is required to validate tdjson session backup symbols" >&2
  exit 1
fi

found_device=0
found_simulator=0
missing=0
for binary in \
  "$XCFRAMEWORK/ios-arm64/tdjson.framework/tdjson" \
  "$XCFRAMEWORK/ios-arm64-simulator/tdjson.framework/tdjson" \
  "$XCFRAMEWORK/ios-arm64_x86_64-simulator/tdjson.framework/tdjson"
do
  if [ ! -f "$binary" ]; then
    continue
  fi
  case "$binary" in
    */ios-arm64/tdjson.framework/tdjson) found_device=1 ;;
    */*-simulator/tdjson.framework/tdjson) found_simulator=1 ;;
  esac
  symbols="$(/usr/bin/nm -gU "$binary" 2>/dev/null || nm -g "$binary" 2>/dev/null || true)"
  for symbol in \
    _td_create_client_id \
    _td_mithka_export_session_string \
    _td_mithka_import_session_string \
    _td_mithka_last_error \
    _td_mithka_set_transfer_boost
  do
    if ! printf '%s\n' "$symbols" | grep -Fq "$symbol"; then
      echo "error: $binary is missing $symbol" >&2
      missing=1
    fi
  done
done

if [ "$found_device" -eq 0 ]; then
  echo "error: no tdjson iOS device binary found in $XCFRAMEWORK" >&2
  missing=1
fi
if [ "$found_simulator" -eq 0 ]; then
  echo "error: no tdjson iOS simulator binary found in $XCFRAMEWORK" >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  echo "error: tdjson.xcframework is missing required Mithka TDLib exports" >&2
  exit 1
fi

echo "✓ required tdjson symbols available in device and simulator slices"
