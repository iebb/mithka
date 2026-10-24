#!/bin/sh
#
# refresh-apple-mdk.sh — install an MDK Apple SDK that is still inside libmdk's
# 44-day key-free window before an Apple build links it.
#
# libmdk refuses to play video without a key once the library is 44 days old:
# App::checkLicense (wang-bin/appkey app.cpp) compares the build stamp compiled
# into the binary with the clock and then draws an "MDK SDK is outdated" QR
# frame over the last frame. The stamp is the binary's own build time, so no
# pinned archive URL stays valid — the SDK has to be resolved per build.
#
# The fvp package (third_party/fvp in iebb/f-videoplayer) declares its Apple
# binary target as a local path when it supports this; the refresh installs a
# verified SDK there. Any other manifest shape is refused loudly: an old fvp
# that still pins one archive would link an expired SDK and bring the QR frame
# back, and failing here is the only way that cannot ship silently.
#
# WHAT THIS DOES NOT FIX: refreshing at build time only guarantees that THIS
# BUILD compiles and links an SDK whose stamp is inside the window. That SDK is
# then copied into the app, and an already installed app keeps the stamp of the
# build it shipped with; it can still cross the 44-day boundary after release
# and draw the "MDK SDK is outdated" frame. Nothing at build time can re-stamp
# a shipped binary, so the honest consequence is that this policy fixes new
# builds, not installed ones: an affected user needs an app update (or a keyed
# build) to keep playing. It does not make playback indefinite.
#
# Usage: scripts/refresh-apple-mdk.sh [refresh|check]
#   refresh (default) resolve, verify and install a fresh SDK
#   check   re-verify the installed SDK without downloading anything
#
# Environment (refresh unless noted):
#   MDK_APPLE_SDK_SOURCE     upstream | url. Defaults to url when
#                            MDK_APPLE_SDK_URL is set, upstream otherwise.
#                            Passed to the tool as --source. Automatic
#                            SourceForge downloads are refused without a
#                            verified digest; use url mode for a vetted nightly.
#   MDK_APPLE_SDK_URL        explicit https:// archive; only valid in url mode,
#                            and setting it on its own selects url mode.
#                            Passed as --url.
#   MDK_APPLE_SDK_SHA256     64-hex digest, required in url mode. The tool has
#                            no --sha256 flag: it reads this variable from the
#                            environment, and this script additionally checks
#                            the digest the tool recorded in mdk-version.json.
#   MDK_FRESHNESS_MARGIN_DAYS  days of window to leave in reserve (default 7),
#                            passed as --margin-days; also honoured by check.
#   MDK_FVP_ROOT             use this fvp checkout instead of the resolved one
#                            (for a patched dependency before its release);
#                            also skips .dart_tool/package_config.json.
#
# There is no stale-SDK escape hatch: a build that cannot verify its SDK must
# fail rather than ship the expired pin (see scripts/tests/refresh_apple_mdk_test.sh).
#
# Exit status: 0 only when a fresh, digest-checked, API-floor-checked SDK was
# installed (refresh) or is still valid (check). Every other outcome — no
# resolution tool, refresh failure, digest mismatch, API floor violation,
# missing or unreadable provenance — exits non-zero and fails the build. There
# is deliberately no override: a build that cannot verify the SDK must fail
# rather than ship the expired pin from issue #192.

set -eu

# The API the fvp Swift/Dart bridge is compiled against (MDK_MINOR in
# include/mdk/c/global.h). The tool enforces this too; it is repeated here so a
# provenance record that claims a too-old SDK is never accepted as success.
MIN_API_MAJOR=0
MIN_API_MINOR=39

say() { printf '%s\n' "$*" >&2; }
die() { say "error: $*"; exit 1; }
usage_error() { say "error: $*"; exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

MODE="${1:-refresh}"
if [ "$#" -gt 1 ]; then
  usage_error "too many arguments (usage: scripts/refresh-apple-mdk.sh [refresh|check])"
fi
case "$MODE" in
  refresh|check) ;;
  *) usage_error "unknown mode $MODE (expected refresh or check)" ;;
esac

PACKAGE_CONFIG=".dart_tool/package_config.json"
FVP_ROOT="${MDK_FVP_ROOT:-}"
if [ -z "$FVP_ROOT" ]; then
  if [ ! -f "$PACKAGE_CONFIG" ]; then
    die "$PACKAGE_CONFIG is missing; run flutter pub get first (or set MDK_FVP_ROOT)"
  fi
  FVP_ROOT="$(
    python3 - "$PACKAGE_CONFIG" <<'PY'
import json
import os
import sys
import urllib.parse

with open(sys.argv[1], encoding="utf-8") as stream:
    config = json.load(stream)
roots = {
    package["name"]: package["rootUri"]
    for package in config["packages"]
    if package["name"] == "fvp"
}
root = roots.get("fvp")
if root is None:
    raise SystemExit("fvp is not resolved in .dart_tool/package_config.json")
parsed = urllib.parse.urlparse(root)
if parsed.scheme == "file":
    print(urllib.parse.unquote(parsed.path))
elif parsed.scheme == "":
    print(os.path.abspath(os.path.join(
        os.path.dirname(sys.argv[1]), urllib.parse.unquote(root)
    )))
else:
    raise SystemExit(f"fvp resolves to an unsupported URI: {root}")
PY
  )" || die "cannot resolve the fvp package root from $PACKAGE_CONFIG"
fi
[ -n "$FVP_ROOT" ] || die "the fvp package root resolved to an empty path"

TOOL="$FVP_ROOT/darwin/fvp/tool/mdk_apple_freshness.py"
MANIFEST="$FVP_ROOT/darwin/fvp/Package.swift"
FRAMEWORK="$FVP_ROOT/darwin/fvp/mdk.xcframework"
PROVENANCE="$FVP_ROOT/darwin/fvp/mdk-version.json"

# A resolved fvp that predates build-time resolution pins one archive. There is
# nothing this script can install into it, and that pin expires 44 days after
# its own build stamp: the build would ship the QR frame from issue #192. Fail
# instead, and name the dependency change that fixes it.
if [ ! -f "$TOOL" ]; then
  say "error: the resolved fvp has no build-time MDK resolution tool:"
  say "error:   $TOOL"
  say "error: this fvp pins one Apple MDK archive, which libmdk treats as"
  say "error: outdated 44 days after that binary's build stamp (issue #192)."
  say "error: bump the fvp dependency in pubspec.yaml to a release containing"
  say "error: darwin/fvp/tool/mdk_apple_freshness.py, or point MDK_FVP_ROOT at"
  say "error: a checkout that has it."
  exit 1
fi

if [ ! -f "$MANIFEST" ] || ! grep -Eq 'path:[[:space:]]*"mdk\.xcframework"' "$MANIFEST"; then
  say "error: $MANIFEST does not declare the mdk binary target as a local path"
  say "error: (path: mdk.xcframework), so a refreshed SDK could not be"
  say "error: linked; this build would use whatever the manifest pins instead."
  exit 1
fi

# Digest recorded by the tool beside the installed framework.
recorded_digest() {
  sed -n 's/.*"sha256":[[:space:]]*"\([0-9a-fA-F]\{64\}\)".*/\1/p' "$PROVENANCE" \
    | head -n 1
}

recorded_sdk_version() {
  sed -n 's/.*"sdk_version":[[:space:]]*"\([0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' "$PROVENANCE" \
    | head -n 1
}

if [ "$MODE" = "refresh" ]; then
  SOURCE="${MDK_APPLE_SDK_SOURCE:-}"
  URL="${MDK_APPLE_SDK_URL:-}"
  SHA="${MDK_APPLE_SDK_SHA256:-}"

  if [ -z "$SOURCE" ]; then
    if [ -n "$URL" ]; then SOURCE=url; else SOURCE=upstream; fi
  fi
  case "$SOURCE" in
    upstream|url) ;;
    sourceforge) die "automatic SourceForge resolution has no verified digest; use url mode with MDK_APPLE_SDK_SHA256" ;;
    *) usage_error "MDK_APPLE_SDK_SOURCE=$SOURCE is not upstream or url" ;;
  esac

  if [ "$SOURCE" = "url" ]; then
    [ -n "$URL" ] || die "MDK_APPLE_SDK_SOURCE=url requires MDK_APPLE_SDK_URL"
    case "$URL" in
      https://?*) ;;
      *) die "MDK_APPLE_SDK_URL must be an https:// archive" ;;
    esac
    [ -n "$SHA" ] || die "MDK_APPLE_SDK_SOURCE=url requires MDK_APPLE_SDK_SHA256 (64 hex characters); refusing to install an archive with no expected digest"
    case "$SHA" in
      *[!0-9a-fA-F]*) die "MDK_APPLE_SDK_SHA256 must be 64 hex characters" ;;
    esac
    [ "${#SHA}" -eq 64 ] || die "MDK_APPLE_SDK_SHA256 must be 64 hex characters, got ${#SHA}"
    SHA="$(printf '%s' "$SHA" | tr 'A-F' 'a-f')"
    export MDK_APPLE_SDK_SHA256="$SHA"
  else
    # The tool ignores both of these outside url mode; refuse to let a caller
    # believe a digest was enforced or an archive was used when neither was.
    [ -z "$URL" ] || usage_error "MDK_APPLE_SDK_URL is set but MDK_APPLE_SDK_SOURCE=$SOURCE ignores it; set MDK_APPLE_SDK_SOURCE=url or unset MDK_APPLE_SDK_URL"
    [ -z "$SHA" ] || usage_error "MDK_APPLE_SDK_SHA256 only applies to MDK_APPLE_SDK_SOURCE=url; $SOURCE fetches its own digest"
  fi

  echo "Refreshing the MDK Apple SDK for this build (source: $SOURCE)"
  # --destination is a top-level option; the rest belong to the refresh
  # subcommand, so they follow it (argparse rejects them before it).
  set -- --destination "$FRAMEWORK" refresh --source "$SOURCE"
  if [ "$SOURCE" = "url" ]; then
    set -- "$@" --url "$URL"
  fi
  if [ -n "${MDK_FRESHNESS_MARGIN_DAYS:-}" ]; then
    set -- "$@" --margin-days "$MDK_FRESHNESS_MARGIN_DAYS"
  fi

  set +e
  python3 "$TOOL" "$@"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    say "error: the MDK Apple SDK could not be refreshed (tool exit $status)."
    say "error: this build would link an SDK outside libmdk's 44-day key-free"
    say "error: window and show the outdated-SDK frame (issue #192)."
    if [ "$SOURCE" = "url" ]; then
      say "error: check MDK_APPLE_SDK_URL and MDK_APPLE_SDK_SHA256."
    fi
    exit "$status"
  fi

  # A zero exit is not enough: the tool's contract is that a verified SDK sits
  # at --destination with a provenance record beside it. Treat anything less as
  # an unusable SDK rather than a successful freshness check.
  [ -d "$FRAMEWORK" ] || die "the refresh reported success but $FRAMEWORK does not exist"
  [ -f "$PROVENANCE" ] || die "the refresh reported success but wrote no provenance at $PROVENANCE; an unverifiable SDK is not usable"
  [ -r "$PROVENANCE" ] || die "the provenance record $PROVENANCE is not readable"

  if [ "$SOURCE" = "url" ]; then
    installed_digest="$(recorded_digest)"
    [ -n "$installed_digest" ] || die "$PROVENANCE records no sha256 for the installed SDK"
    installed_digest="$(printf '%s' "$installed_digest" | tr 'A-F' 'a-f')"
    [ "$installed_digest" = "$SHA" ] || die "digest mismatch: MDK_APPLE_SDK_SHA256 is $SHA but $PROVENANCE records $installed_digest"
  fi

  sdk_version="$(recorded_sdk_version)"
  [ -n "$sdk_version" ] || die "$PROVENANCE records no sdk_version; cannot verify the API floor"
  sdk_major="${sdk_version%%.*}"
  sdk_minor="${sdk_version#*.}"
  case "$sdk_major" in '' | *[!0-9]*) die "$PROVENANCE records a malformed sdk_version: $sdk_version" ;; esac
  case "$sdk_minor" in '' | *[!0-9]*) die "$PROVENANCE records a malformed sdk_version: $sdk_version" ;; esac
  if [ "$sdk_major" -lt "$MIN_API_MAJOR" ] ||
     { [ "$sdk_major" -eq "$MIN_API_MAJOR" ] && [ "$sdk_minor" -lt "$MIN_API_MINOR" ]; }; then
    die "the installed SDK is MDK $sdk_version, below the $MIN_API_MAJOR.$MIN_API_MINOR API the fvp bridge compiles against"
  fi

  echo "Installed MDK $sdk_version ($(basename "$FVP_ROOT")), digest and API floor verified"
else
  echo "Verifying the installed MDK Apple SDK"
  set -- --destination "$FRAMEWORK" check
  if [ -n "${MDK_FRESHNESS_MARGIN_DAYS:-}" ]; then
    set -- "$@" --margin-days "$MDK_FRESHNESS_MARGIN_DAYS"
  fi
  set +e
  python3 "$TOOL" "$@"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    say "error: the installed MDK Apple SDK is not usable for this build"
    say "error: (tool exit $status); re-run the refresh or update the SDK"
    say "error: source. It would show the outdated-SDK frame (issue #192)."
    exit "$status"
  fi
  echo "The installed MDK Apple SDK is still inside the 44-day window"
fi
