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
SOURCE_VERSION="${RAW_VERSION%%+*}"
case "$SOURCE_VERSION" in
  ''|*[!0-9.]*|.*|*.)
    echo "error: expected a numeric macOS version in pubspec.yaml" >&2
    exit 1
    ;;
esac

# Preserve the complete semantic version from pubspec.yaml. The nightly job
# advances the patch so Apple builds move to a new App Store Connect release
# train when the previous train is closed.
#
# Unlike iOS, the macOS project does not hardcode FLUTTER_BUILD_NAME — it
# reads the generated xcconfig — so passing --build-name below is the whole
# fix, with no project file to rewrite.
APP_VERSION="$(
  printf '%s\n' "$SOURCE_VERSION" |
    awk -F. 'NF == 3 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { print $0 }'
)"
if [ -z "$APP_VERSION" ]; then
  echo "error: expected a numeric X.Y.Z version in pubspec.yaml, got $SOURCE_VERSION" >&2
  exit 1
fi

# Xcode Cloud replaces distributed products' build number with its own
# monotonically increasing CI build number. Use the same value in the archive
# so diagnostics and generated metadata agree with the TestFlight build. Local
# invocations retain a collision-resistant timestamp fallback.
APP_BUILD_NUMBER="${CI_BUILD_NUMBER:-$(date -u '+%s')}"
GIT_COMMIT="${CI_COMMIT:-$(git rev-parse --short HEAD)}"
GIT_COMMIT="$(printf '%s' "$GIT_COMMIT" | cut -c1-7)"
echo "Preparing Mithka macOS ${APP_VERSION}+${APP_BUILD_NUMBER} (${GIT_COMMIT}, source: ${SOURCE_VERSION})"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter $FLUTTER_VERSION"
  retry 3 10 git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi
flutter --version

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

echo "Preparing manifest-pinned universal macOS TDLib"
"$REPO/scripts/build-tdjson-desktop.sh" macos native-libs/libtdjson.dylib

flutter config --enable-swift-package-manager
flutter precache --macos
flutter pub get
flutter build macos --release --config-only \
  --build-name="$APP_VERSION" \
  --build-number="$APP_BUILD_NUMBER" \
  --dart-define="GIT_COMMIT=$GIT_COMMIT" \
  --dart-define="CI_BUILD_STAMP=$APP_BUILD_NUMBER" \
  --dart-define="SENTRY_DSN=${SENTRY_DSN:-}"

# Some Flutter plugins declare Resources in Package.swift without creating the
# directory. Xcode treats that as an invalid package manifest, which prevents
# locked dependency resolution in Xcode Cloud. Repair only generated packages
# that explicitly declare the directory.
ensure_declared_plugin_resources() {
  packages_root="macos/Flutter/ephemeral/Packages/.packages"
  declared_count=0

  for package_root in "$packages_root"/*; do
    package_manifest="$package_root/Package.swift"
    [ -f "$package_manifest" ] || continue
    grep -Fq '.process("Resources")' "$package_manifest" || continue
    target_count=0
    for target_root in "$package_root"/Sources/*; do
      [ -d "$target_root" ] || continue
      target_count=$((target_count + 1))
      mkdir -p "$target_root/Resources"
    done
    if [ "$target_count" -eq 0 ]; then
      echo "error: no generated targets found for $package_root" >&2
      exit 1
    fi
    declared_count=$((declared_count + 1))
  done

  if [ "$declared_count" -eq 0 ]; then
    echo "error: no generated plugin package declared Resources" >&2
    exit 1
  fi
}

ensure_declared_plugin_resources

# A small set of desktop plugins still uses CocoaPods while the remaining
# plugins use Flutter's generated Swift package. Recreate the checked-in lock's
# exact sandbox before Xcode Cloud invokes xcodebuild.
(
  cd macos
  retry 4 8 pod install --deployment
  diff -q Podfile.lock Pods/Manifest.lock
)

# The Xcode Cloud workflow deliberately disables automatic package resolution.
# Resolve the committed workspace lock after Flutter has generated its local
# plugin packages so the archive step receives a populated package cache.
echo "Resolving macOS Swift package dependencies"
XCODE_DERIVED_DATA_PATH="${CI_DERIVED_DATA_PATH:-$REPO/build/xcode-cloud-derived-data}"
mkdir -p "$XCODE_DERIVED_DATA_PATH"
retry 3 10 xcodebuild -resolvePackageDependencies \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -onlyUsePackageVersionsFromResolvedFile \
  -derivedDataPath "$XCODE_DERIVED_DATA_PATH"

test -s macos/Flutter/ephemeral/Flutter-Generated.xcconfig
test -d macos/Runner.xcworkspace
test -s macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved
echo "macOS Xcode Cloud post-clone setup complete"
