#!/usr/bin/env bash

# Read the Android release sequence shared by the direct-APK and Play
# workflows. The nightly sync and stable version-bump scripts allocate it.

set -euo pipefail

version_file="${1:-android/version-code.txt}"
if [ ! -f "$version_file" ]; then
  echo "Android version-code file not found: $version_file" >&2
  exit 1
fi

version_code="$(tr -d '\r\n' < "$version_file")"

case "$version_code" in
  ''|*[!0-9]*)
    echo "Invalid Android version code in $version_file" >&2
    exit 1
    ;;
esac

if [ "$version_code" -lt 1 ] || [ "$version_code" -gt 2100000000 ]; then
  echo "Android version code $version_code is outside Play's accepted range" >&2
  exit 1
fi

printf '%s\n' "$version_code"
