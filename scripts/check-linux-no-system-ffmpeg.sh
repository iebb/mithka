#!/usr/bin/env bash
# Fail if a Linux bundle links the host's FFmpeg libraries.
#
# MDK ships its own libffmpeg.so.9 and Mithka decodes scrub thumbnails through
# it. A plugin that links libavformat/libavcodec/libswscale from the build host
# makes linuxdeploy bundle roughly 30 MB of FFmpeg 6 for the AppImage and stops
# the portable tarball from starting where those libraries are not installed.
#
# Usage: scripts/check-linux-no-system-ffmpeg.sh <bundle-or-appdir>
set -euo pipefail

root="${1:?usage: check-linux-no-system-ffmpeg.sh <bundle-or-appdir>}"
if [[ -n "${READELF:-}" ]]; then
  readelf="$READELF"
elif command -v readelf >/dev/null 2>&1; then
  readelf="readelf"
elif [[ -x /opt/homebrew/opt/binutils/bin/readelf ]]; then
  readelf="/opt/homebrew/opt/binutils/bin/readelf"
else
  echo "error: readelf not found (set READELF or install binutils)" >&2
  exit 2
fi
libraries='lib(avformat|avcodec|avutil|swscale|swresample|avfilter|avdevice)'
status=0

while IFS= read -r -d '' file; do
  [[ "$(head -c 4 "$file" | od -An -tx1 | tr -d ' \n')" == 7f454c46 ]] || continue
  needed="$(
    "$readelf" -d "$file" 2>/dev/null \
      | grep -oE "\\[${libraries}\\.so[^]]*\\]" || true
  )"
  if [[ -n "$needed" ]]; then
    echo "error: ${file#"$root"/} links the host FFmpeg: $(echo "$needed" | tr '\n' ' ')" >&2
    status=1
  fi
done < <(find "$root" -type f -print0)

host_ffmpeg="$(
  find "$root" \( -type f -o -type l \) -print \
    | grep -E "/${libraries}\\.so" || true
)"
if [[ -n "$host_ffmpeg" ]]; then
  echo "$host_ffmpeg" >&2
  echo 'error: the bundle must not contain host FFmpeg libraries' >&2
  status=1
fi
exit "$status"
