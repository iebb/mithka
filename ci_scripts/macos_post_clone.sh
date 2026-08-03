#!/bin/sh
#
# Xcode Cloud post-clone setup for the native macOS Mithka target.
#
# Required secret workflow environment variables:
#   TELEGRAM_API_ID
#   TELEGRAM_API_HASH
#
# Optional secret workflow environment variables:
#   SENTRY_DSN
#
# Xcode Cloud performs signing and TestFlight distribution. This script only
# recreates deterministic build inputs that aren't committed to Git: Flutter,
# generated configuration, Telegram compile-time configuration, CocoaPods, and
# the pinned universal TDLib dylib.

set -eu

FLUTTER_VERSION="3.44.2"
TDJSON_RELEASE_TAG="tdlib-1.8.66-1b08c83bc078-rebuild-29623073124-1"
TDJSON_UPSTREAM_SHA="1b08c83bc07888e4b0a6150d36c1364ff03cf930"
FVP_DEPS_URL="${FVP_DEPS_URL:-https://github.com/wang-bin/mdk-sdk/releases/download/v0.36.0}"

retry() {
  attempts="$1"
  delay="$2"
  shift 2
  attempt=1
  while :; do
    "$@" && return 0
    status=$?
    if [ "$attempt" -ge "$attempts" ]; then
      echo "error: command failed after $attempts attempts: $*" >&2
      return "$status"
    fi
    echo "warning: retrying command $((attempt + 1))/$attempts in ${delay}s" >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO"

if [ -n "${MITHKA_CI_PLATFORM:-}" ] && [ "$MITHKA_CI_PLATFORM" != "macos" ]; then
  echo "error: macOS setup invoked for platform $MITHKA_CI_PLATFORM" >&2
  exit 1
fi

RAW_VERSION="$(awk '/^version:/ { print $2; exit }' pubspec.yaml)"
APP_VERSION="${RAW_VERSION%%+*}"
case "$APP_VERSION" in
  ''|*[!0-9.]*|.*|*.)
    echo "error: expected a numeric macOS version in pubspec.yaml" >&2
    exit 1
    ;;
esac

# Xcode Cloud replaces distributed products' build number with its own
# monotonically increasing CI build number. Use the same value in the archive
# so diagnostics and generated metadata agree with the TestFlight build. Local
# invocations retain a collision-resistant timestamp fallback.
APP_BUILD_NUMBER="${CI_BUILD_NUMBER:-$(date -u '+%s')}"
GIT_COMMIT="${CI_COMMIT:-$(git rev-parse --short HEAD)}"
GIT_COMMIT="$(printf '%s' "$GIT_COMMIT" | cut -c1-7)"
echo "Preparing Mithka macOS ${APP_VERSION}+${APP_BUILD_NUMBER} (${GIT_COMMIT})"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter $FLUTTER_VERSION"
  retry 3 10 git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi
flutter --version

if ! command -v cmake >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
  retry 3 10 brew install cmake ninja
fi
if ! command -v pod >/dev/null 2>&1; then
  retry 3 10 brew install cocoapods
fi

: "${TELEGRAM_API_ID:?set TELEGRAM_API_ID as a secret Xcode Cloud environment variable}"
: "${TELEGRAM_API_HASH:?set TELEGRAM_API_HASH as a secret Xcode Cloud environment variable}"
python3 - <<'PY'
import json
import os
from pathlib import Path

api_id = os.environ["TELEGRAM_API_ID"]
if not api_id.isdigit() or int(api_id) <= 0:
    raise SystemExit("TELEGRAM_API_ID must be a positive integer")
api_hash = os.environ["TELEGRAM_API_HASH"]
if not api_hash:
    raise SystemExit("TELEGRAM_API_HASH must not be empty")
Path("lib/config").mkdir(parents=True, exist_ok=True)
Path("lib/config/secrets.dart").write_text(
    "class Secrets {\n"
    f"  static const int apiId = {api_id};\n"
    f"  static const String apiHash = {json.dumps(api_hash)};\n"
    "  static bool get isConfigured => apiId != 0 && apiHash.isNotEmpty;\n"
    "}\n"
)
PY

export TDJSON_RELEASE_TAG
export TD_COMMIT="$TDJSON_UPSTREAM_SHA"
export TD_BUILD_JOBS="${TD_BUILD_JOBS:-2}"
export FVP_DEPS_URL
echo "Building pinned universal macOS TDLib"
scripts/build-tdjson-desktop.sh macos native-libs/libtdjson.dylib
test "$(lipo -archs native-libs/libtdjson.dylib | tr ' ' '\n' | sort | tr '\n' ' ')" = "arm64 x86_64 "

flutter config --enable-swift-package-manager
flutter precache --macos
flutter pub get
flutter build macos --release --config-only \
  --build-name="$APP_VERSION" \
  --build-number="$APP_BUILD_NUMBER" \
  --dart-define="GIT_COMMIT=$GIT_COMMIT" \
  --dart-define="CI_BUILD_STAMP=$APP_BUILD_NUMBER" \
  --dart-define="SENTRY_DSN=${SENTRY_DSN:-}"

# A small set of desktop plugins still uses CocoaPods while the remaining
# plugins use Flutter's generated Swift package. Recreate the checked-in lock's
# exact sandbox before Xcode Cloud invokes xcodebuild.
(
  cd macos
  retry 4 8 pod install --deployment
  diff -q Podfile.lock Pods/Manifest.lock
)

test -s macos/Flutter/ephemeral/Flutter-Generated.xcconfig
test -d macos/Runner.xcworkspace
echo "macOS Xcode Cloud post-clone setup complete"
