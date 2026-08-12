#!/usr/bin/env bash
#
# Downloads the checksum-pinned TDLib XCFramework consumed by the iOS Runner.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESTINATION="$REPO_ROOT/ios/tdjson/tdjson.xcframework"

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "error: Python 3 is required to install tdjson artifacts" >&2
  exit 1
fi

"$PYTHON" "$SCRIPT_DIR/install-tdjson-artifact.py" \
  tdjson-ios.xcframework.zip \
  "$DESTINATION"
"$SCRIPT_DIR/check-tdjson-session-symbols.sh" "$DESTINATION"

echo "Installed pinned iOS tdjson XCFramework."
echo "Now run: cd ios && pod install   (then: flutter run)"
