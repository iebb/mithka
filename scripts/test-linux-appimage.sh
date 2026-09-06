#!/usr/bin/env bash
set -euo pipefail
appimage="$(realpath "${1:?usage: test-linux-appimage.sh <file.AppImage>}")"
test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT
# A visible window requires the native plugins and Flutter's first frame to
# work. Use disposable app data and software rendering on both CI architectures.
HOME="$test_home" XDG_CONFIG_HOME="$test_home/config" \
XDG_DATA_HOME="$test_home/data" XDG_CACHE_HOME="$test_home/cache" \
APPIMAGE_EXTRACT_AND_RUN=1 LIBGL_ALWAYS_SOFTWARE=1 \
  timeout 90s dbus-run-session -- xvfb-run -a bash -s -- "$appimage" <<'BASH'
"$1" >"$HOME/launch.log" 2>&1 &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true' EXIT
if ! timeout 60s xdotool search --sync --onlyvisible --name "^Mithka$"; then
  cat "$HOME/launch.log" >&2
  exit 1
fi
sleep 3
kill -0 "$app_pid"
BASH
echo 'AppImage displayed its first Flutter frame successfully'
