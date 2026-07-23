#!/usr/bin/env bash
#
# Uploads iOS dSYMs to Sentry from Xcode/Xcode Cloud archives. The phase is
# intentionally guarded so local unsigned/dev builds and CI jobs without Sentry
# upload credentials keep working.
set -euo pipefail

if [[ "${EFFECTIVE_PLATFORM_NAME:-}" != "-iphoneos" ]]; then
  exit 0
fi

if [[ "${CONFIGURATION:-}" != "Release" ]]; then
  exit 0
fi

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "warning: SENTRY_AUTH_TOKEN is not set; skipping Sentry dSYM upload" >&2
  exit 0
fi

SENTRY_ORG="${SENTRY_ORG:-nekoko}"
# `debug-files upload` addresses projects by slug. Xcode Cloud previously used
# this project's numeric ID (10), so preserve that environment configuration by
# normalizing it before invoking sentry-cli.
SENTRY_PROJECT="${SENTRY_PROJECT:-mithka}"
if [[ "$SENTRY_PROJECT" == "10" ]]; then
  SENTRY_PROJECT="mithka"
fi
SENTRY_URL="${SENTRY_URL:-https://sentry.nekoko.it}"

if [[ -z "$SENTRY_PROJECT" ]]; then
  echo "warning: SENTRY_PROJECT is required for Sentry dSYM upload; skipping" >&2
  exit 0
fi

DSYM_DIR="${DWARF_DSYM_FOLDER_PATH:-}"
if [[ -z "$DSYM_DIR" || ! -d "$DSYM_DIR" ]]; then
  echo "warning: DWARF_DSYM_FOLDER_PATH is empty or missing; skipping Sentry dSYM upload" >&2
  exit 0
fi

find_sentry_cli() {
  if command -v sentry-cli >/dev/null 2>&1; then
    command -v sentry-cli
    return 0
  fi

  local repo_root
  repo_root="$(cd "${SRCROOT:-$(dirname "${BASH_SOURCE[0]}")/../ios}/.." && pwd)"
  local cli="$repo_root/.build/sentry-cli/sentry-cli"
  if [[ -x "$cli" ]]; then
    printf '%s\n' "$cli"
    return 0
  fi

  mkdir -p "$(dirname "$cli")"
  local version="${SENTRY_CLI_VERSION:-2.58.2}"
  local platform="Darwin-universal"
  local url="https://github.com/getsentry/sentry-cli/releases/download/${version}/sentry-cli-${platform}"
  echo "> downloading sentry-cli $version" >&2
  /usr/bin/curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 20 "$url" -o "$cli"
  chmod +x "$cli"
  printf '%s\n' "$cli"
}

SENTRY_CLI="$(find_sentry_cli)"
echo "> uploading dSYMs from $DSYM_DIR to Sentry project $SENTRY_ORG/$SENTRY_PROJECT"
"$SENTRY_CLI" \
  --url "$SENTRY_URL" \
  debug-files upload \
  --org "$SENTRY_ORG" \
  --project "$SENTRY_PROJECT" \
  "$DSYM_DIR"
