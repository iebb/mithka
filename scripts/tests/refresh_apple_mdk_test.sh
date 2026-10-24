#!/usr/bin/env bash
#
# refresh_apple_mdk_test.sh — behavioural tests for scripts/refresh-apple-mdk.sh.
#
# Runs the real script (copied byte-for-byte into a throwaway tree) against a
# stub python3 that emulates the CLI contract of fvp's
# darwin/fvp/tool/mdk_apple_freshness.py, and asserts exit status plus message
# for each failure path. The stub rejects any flag the real tool does not
# define, so a wrapper that invents --sha256 or drops --source fails here.
#
# Hermetic: temp dirs only, no network, no flutter/git (the script does not call
# them; MDK_FVP_ROOT skips .dart_tool/package_config.json). Quality CI also runs
# the helper against the real resolved tool and its verified upstream archive.
#
# Usage: bash scripts/tests/refresh_apple_mdk_test.sh

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../refresh-apple-mdk.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/refresh-apple-mdk-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

BIN="$WORK/bin"
REPO="$WORK/repo"
FVP="$WORK/fvp"
REAL_PYTHON="$(command -v python3)"
mkdir -p "$BIN" "$REPO/scripts" "$FVP/darwin/fvp/tool"
cp "$SCRIPT" "$REPO/scripts/refresh-apple-mdk.sh"
cmp -s "$SCRIPT" "$REPO/scripts/refresh-apple-mdk.sh" || {
  echo "FAIL setup: could not copy the script under test"
  exit 1
}

# Two distinct 64-hex digests: what the caller expects, and what the tool lies
# about in the mismatch case.
DIGEST_OK=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
DIGEST_OTHER=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
for digest in "$DIGEST_OK" "$DIGEST_OTHER"; do
  if [ "${#digest}" -ne 64 ]; then
    echo "FAIL setup: fixture digest is ${#digest} characters, not 64"
    exit 1
  fi
done

# --- stub python3: the freshness tool's CLI contract -------------------------
cat >"$BIN/python3" <<'STUB'
#!/bin/sh
# Execute the helper's package-config resolver with real Python. SDK invocations
# continue through the stub so the failure-path tests remain offline.
if [ "${1:-}" = "-" ]; then
  exec "$STUB_REAL_PYTHON" "$@"
fi
# Emulates darwin/fvp/tool/mdk_apple_freshness.py. Only the flags the real tool
# defines are accepted, with argparse's layout: --destination is top-level and
# must precede the subcommand; --source/--url/--margin-days follow it. Anything
# else is a wrapper bug and fails loudly, exactly as the real tool would.
# $1 is the path to the tool, as python3 receives it.
[ "$#" -gt 0 ] || { echo "stub-tool: no script path" >&2; exit 2; }
shift
printf '%s\n' "$*" >>"$STUB_CALLS"
: >"$STUB_FACTS"
destination=""
command=""
source=""
url=""
margin=""
# Top-level options, before the subcommand.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --destination) destination="${2:-}"; shift 2 ;;
    refresh|check) command="$1"; shift; break ;;
    *)
      echo "stub-tool: invalid choice/option before the subcommand: $1" >&2
      exit 64
      ;;
  esac
done
[ -n "$command" ] || { echo "stub-tool: a command is required" >&2; exit 2; }
# Subcommand options, after it.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) source="${2:-}"; shift 2 ;;
    --url) url="${2:-}"; shift 2 ;;
    --margin-days) margin="${2:-}"; shift 2 ;;
    *)
      echo "stub-tool: unsupported argument for $command: $1" >&2
      exit 64
      ;;
  esac
done
{
  echo "command=$command"
  echo "destination=$destination"
  echo "source=$source"
  echo "url=$url"
  echo "margin=$margin"
  echo "sha_env=${MDK_APPLE_SDK_SHA256:-}"
} >>"$STUB_FACTS"

[ -n "$destination" ] || { echo "stub-tool: --destination is required" >&2; exit 2; }
if [ "$command" = "refresh" ]; then
  [ -n "$source" ] || { echo "stub-tool: refresh requires --source" >&2; exit 2; }
  case "$source" in
    upstream | sourceforge) ;;
    url) [ -n "$url" ] || { echo "stub-tool: --source url requires --url" >&2; exit 2; } ;;
    *) echo "stub-tool: invalid --source $source" >&2; exit 2 ;;
  esac
fi

mode="${STUB_TOOL_MODE:-ok}"
write_record() {
  digest="$1"
  version="$2"
  mkdir -p "$(dirname "$destination")"
  cat >"$(dirname "$destination")/mdk-version.json" <<JSON
{
  "build_stamp": "2026-10-20T00:00:00",
  "free_window_days": 44,
  "margin_days": "${margin:-7}",
  "sdk_version": "$version",
  "source": {
    "kind": "stub",
    "sha256": "$digest",
    "url": "$url"
  },
  "updater": 1,
  "verified_at": "2026-10-22T00:00:00"
}
JSON
}

case "$mode" in
  ok)
    if [ "$command" = "check" ]; then
      echo "stub-tool: installed MDK 0.39 is still fresh"
      exit 0
    fi
    mkdir -p "$destination"
    write_record "${MDK_APPLE_SDK_SHA256:-$STUB_DEFAULT_DIGEST}" 0.39
    echo "stub-tool: installed MDK 0.39"
    ;;
  unavailable)
    echo "stub-tool: error: cannot list wang-bin/mdk-sdk releases: offline" >&2
    exit 1
    ;;
  digest-mismatch)
    mkdir -p "$destination"
    write_record "$STUB_OTHER_DIGEST" 0.39
    exit 0
    ;;
  api-floor)
    mkdir -p "$destination"
    write_record "${MDK_APPLE_SDK_SHA256:-$STUB_DEFAULT_DIGEST}" 0.37
    exit 0
    ;;
  no-provenance)
    mkdir -p "$destination"
    exit 0
    ;;
  no-framework)
    write_record "${MDK_APPLE_SDK_SHA256:-$STUB_DEFAULT_DIGEST}" 0.39
    exit 0
    ;;
  check-stale)
    echo "stub-tool: error: the SDK was built 50 days ago" >&2
    exit 1
    ;;
  *)
    echo "stub-tool: unknown STUB_TOOL_MODE $mode" >&2
    exit 70
    ;;
esac
STUB
chmod +x "$BIN/python3"

# --- fixtures ----------------------------------------------------------------
write_manifest() {
  cat >"$FVP/darwin/fvp/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "fvp",
    targets: [
        .binaryTarget(
            name: "mdk",
            path: "mdk.xcframework"
        ),
    ]
)
SWIFT
}

reset_tree() {
  rm -rf "$FVP/darwin/fvp/tool" "$FVP/darwin/fvp/mdk.xcframework" \
    "$FVP/darwin/fvp/mdk-version.json"
  mkdir -p "$FVP/darwin/fvp/tool"
  : >"$FVP/darwin/fvp/tool/mdk_apple_freshness.py"
  write_manifest
  rm -f "$WORK/calls" "$WORK/facts" "$WORK/output"
}

# --- runner ------------------------------------------------------------------
status=0
output=""
fresh_env() {
  unset MDK_APPLE_SDK_SOURCE MDK_APPLE_SDK_URL MDK_APPLE_SDK_SHA256 \
    MDK_FRESHNESS_MARGIN_DAYS STUB_TOOL_MODE
}

run() {
  # run <mode> [VAR=value ...]
  local mode="$1"
  shift
  rm -f "$WORK/calls" "$WORK/facts" "$WORK/output"
  env -u MDK_APPLE_SDK_SOURCE -u MDK_APPLE_SDK_URL -u MDK_APPLE_SDK_SHA256 \
    -u MDK_FRESHNESS_MARGIN_DAYS -u STUB_TOOL_MODE \
    PATH="$BIN:$PATH" \
    MDK_FVP_ROOT="$FVP" \
    STUB_CALLS="$WORK/calls" \
    STUB_FACTS="$WORK/facts" \
    STUB_DEFAULT_DIGEST="$DIGEST_OK" \
    STUB_OTHER_DIGEST="$DIGEST_OTHER" \
    STUB_REAL_PYTHON="$REAL_PYTHON" \
    "$@" sh "$REPO/scripts/refresh-apple-mdk.sh" "$mode" \
    >"$WORK/output" 2>&1
  status=$?
  output="$(cat "$WORK/output")"
}

calls() { [ -f "$WORK/calls" ] && cat "$WORK/calls" || true; }
fact() {
  [ -f "$WORK/facts" ] || return 1
  sed -n "s/^$1=//p" "$WORK/facts" | head -n 1
}

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  printf 'PASS %s\n' "$1"
}
bad() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1"
  printf '     exit=%s\n' "$status"
  printf '%s\n' "$output" | sed 's/^/     | /'
}
expect_status() {
  # expect_status <case> <expected> [<message substring>]
  if [ "$status" -eq "$2" ]; then
    if [ -z "${3:-}" ] || printf '%s' "$output" | grep -Fq -- "$3"; then
      ok "$1"
    else
      bad "$1"
      printf '     missing message: %s\n' "$3"
    fi
  else
    bad "$1"
    [ -z "${3:-}" ] || printf '     expected message: %s\n' "$3"
  fi
}

# --- 1. a fresh SDK succeeds, with the source wired through -------------------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=ok
expect_status "fresh SDK from upstream succeeds" 0 "digest and API floor verified"
if [ "$(fact source)" = "upstream" ] && [ "$(fact command)" = "refresh" ]; then
  ok "upstream is passed explicitly as --source"
else
  bad "upstream is passed explicitly as --source"
fi
if [ -z "$(fact url)" ]; then
  ok "upstream mode passes no --url"
else
  bad "upstream mode passes no --url"
fi

# --- 2. margin passthrough ---------------------------------------------------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=ok MDK_FRESHNESS_MARGIN_DAYS=3
expect_status "MDK_FRESHNESS_MARGIN_DAYS is forwarded" 0
if [ "$(fact margin)" = "3" ]; then
  ok "--margin-days carries the configured margin"
else
  bad "--margin-days carries the configured margin (got '$(fact margin)')"
fi

# --- 3. the resolved fvp has no freshness tool -------------------------------
fresh_env
reset_tree
rm -f "$FVP/darwin/fvp/tool/mdk_apple_freshness.py"
run refresh STUB_TOOL_MODE=ok
expect_status "missing freshness tool fails the build" 1 \
  "no build-time MDK resolution tool"
if [ -z "$(calls)" ]; then
  ok "missing tool never invokes the tool"
else
  bad "missing tool never invokes the tool"
fi

# --- 4. the tool reports it cannot refresh -----------------------------------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=unavailable
expect_status "refresh failure fails the build" 1 "could not be refreshed"

# --- 5. digest mismatch is caught even when the tool exits 0 -----------------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=digest-mismatch \
  MDK_APPLE_SDK_SOURCE=url \
  MDK_APPLE_SDK_URL=https://example.invalid/mdk.xcframework.zip \
  MDK_APPLE_SDK_SHA256="$DIGEST_OK"
expect_status "digest mismatch fails the build" 1 "digest mismatch"
if [ "$(fact source)" = "url" ] && \
   [ "$(fact url)" = "https://example.invalid/mdk.xcframework.zip" ]; then
  ok "url mode passes --source url --url <archive>"
else
  bad "url mode passes --source url --url <archive>"
fi

# --- 6. explicit URL with no expected digest fails before any work -----------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=ok \
  MDK_APPLE_SDK_SOURCE=url \
  MDK_APPLE_SDK_URL=https://example.invalid/mdk.xcframework.zip
expect_status "explicit URL with an empty digest fails" 1 \
  "requires MDK_APPLE_SDK_SHA256"
if [ -z "$(calls)" ]; then
  ok "explicit URL with an empty digest fails before invoking the tool"
else
  bad "explicit URL with an empty digest fails before invoking the tool"
fi

# --- 7. a malformed digest is refused ---------------------------------------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=ok \
  MDK_APPLE_SDK_SOURCE=url \
  MDK_APPLE_SDK_URL=https://example.invalid/mdk.xcframework.zip \
  MDK_APPLE_SDK_SHA256=deadbeef
expect_status "short digest fails" 1 "64 hex characters"

# --- 8. a non-https URL is refused ------------------------------------------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=ok \
  MDK_APPLE_SDK_SOURCE=url \
  MDK_APPLE_SDK_URL=http://example.invalid/mdk.xcframework.zip \
  MDK_APPLE_SDK_SHA256="$DIGEST_OK"
expect_status "non-https URL fails" 1 "must be an https:// archive"

# --- 9. URL set while the source is not url: refuse the no-op ---------------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=ok \
  MDK_APPLE_SDK_URL=https://example.invalid/mdk.xcframework.zip
expect_status "MDK_APPLE_SDK_URL alone selects url mode" 1 \
  "requires MDK_APPLE_SDK_SHA256"

fresh_env
reset_tree
run refresh STUB_TOOL_MODE=ok \
  MDK_APPLE_SDK_SOURCE=upstream \
  MDK_APPLE_SDK_URL=https://example.invalid/mdk.xcframework.zip \
  MDK_APPLE_SDK_SHA256="$DIGEST_OK"
expect_status "URL plus a non-url source is refused" 2 "ignores it"

fresh_env
reset_tree
run refresh STUB_TOOL_MODE=ok MDK_APPLE_SDK_SOURCE=sourceforge
expect_status "unverified SourceForge resolution is refused" 1 "no verified digest"
if [ -z "$(calls)" ]; then
  ok "unverified SourceForge never invokes the tool"
else
  bad "unverified SourceForge never invokes the tool"
fi

# --- 10. API floor violation is caught from the provenance -------------------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=api-floor
expect_status "SDK below the API floor fails the build" 1 "below the 0.39 API"

# --- 11. a zero exit without a usable install is a failure -------------------
fresh_env
reset_tree
run refresh STUB_TOOL_MODE=no-provenance
expect_status "success without provenance fails" 1 "wrote no provenance"

fresh_env
reset_tree
run refresh STUB_TOOL_MODE=no-framework
expect_status "success without an installed framework fails" 1 \
  "does not exist"

# --- 12. a manifest that still pins a remote binary is refused ---------------
fresh_env
reset_tree
cat >"$FVP/darwin/fvp/Package.swift" <<'SWIFT'
import PackageDescription
let package = Package(
    name: "fvp",
    targets: [
        .binaryTarget(
            name: "mdk",
            url: "https://example.invalid/mdk.xcframework.zip",
            checksum: "615b9e8ddd6d31a35c109b8dcb2493e896a3b532aed0b6b498d1c62686fbe3b7"
        ),
    ]
)
SWIFT
run refresh STUB_TOOL_MODE=ok
expect_status "a manifest that pins a remote binary fails" 1 \
  "does not declare the mdk binary target as a local path"

# --- 13. check mode ----------------------------------------------------------
fresh_env
reset_tree
run check STUB_TOOL_MODE=ok
expect_status "check passes on a fresh installed SDK" 0 "still inside the 44-day window"
if [ "$(fact command)" = "check" ] && [ -z "$(fact source)" ]; then
  ok "check passes no refresh-only flags"
else
  bad "check passes no refresh-only flags"
fi

fresh_env
reset_tree
run check STUB_TOOL_MODE=check-stale
expect_status "check fails on a stale installed SDK" 1 "not usable for this build"

fresh_env
reset_tree
run check STUB_TOOL_MODE=ok MDK_FRESHNESS_MARGIN_DAYS=8
expect_status "check accepts a configured safety margin after the subcommand" 0 \
  "still inside the 44-day window"
if [ "$(fact command)" = "check" ] && [ "$(fact margin)" = "8" ]; then
  ok "check forwards the configured margin"
else
  bad "check forwards the configured margin"
fi

# A relative rootUri is relative to package_config.json, not the repo root.
fresh_env
reset_tree
mkdir -p "$REPO/.dart_tool"
printf '%s\n' '{"packages":[{"name":"fvp","rootUri":"../../fvp"}]}' \
  >"$REPO/.dart_tool/package_config.json"
run refresh STUB_TOOL_MODE=ok MDK_FVP_ROOT=
expect_status "relative package root resolves from the package-config directory" 0 \
  "digest and API floor verified"
if [ "$(fact destination)" = "$FVP/darwin/fvp/mdk.xcframework" ]; then
  ok "relative package root installs into the resolved dependency"
else
  bad "relative package root installs into the resolved dependency"
fi
rm -rf "$REPO/.dart_tool"

# --- 14. no resolved fvp and no MDK_FVP_ROOT --------------------------------
fresh_env
reset_tree
rm -f "$WORK/calls" "$WORK/facts" "$WORK/output"
env -u MDK_APPLE_SDK_SOURCE -u MDK_APPLE_SDK_URL -u MDK_APPLE_SDK_SHA256 \
  -u MDK_FVP_ROOT PATH="$BIN:$PATH" \
  sh "$REPO/scripts/refresh-apple-mdk.sh" refresh >"$WORK/output" 2>&1
status=$?
output="$(cat "$WORK/output")"
expect_status "an unresolved fvp without MDK_FVP_ROOT fails" 1 \
  "run flutter pub get first"

# --- 15. an unknown mode is a usage error ------------------------------------
fresh_env
reset_tree
run verify STUB_TOOL_MODE=ok
expect_status "an unknown mode is rejected" 2 "unknown mode verify"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
