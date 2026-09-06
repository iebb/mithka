#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
architecture="${1:?usage: build-linux-appimage.sh <x64|arm64> <bundle> <output.AppImage>}"
bundle="$(realpath "${2:?missing Flutter bundle}")"
output="$(realpath -m "${3:?missing output AppImage path}")"
case "$architecture" in
  x64)
    appimage_arch=x86_64
    expected_machine=62
    tool_digest=c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d
    ;;
  arm64)
    appimage_arch=aarch64
    expected_machine=183
    tool_digest=620095110d693282b8ebeb244a95b5e911cf8f65f76c88b4b47d16ae6346fcff
    ;;
  *) echo "Unsupported Linux architecture: $architecture" >&2; exit 1 ;;
esac

# Reject missing or mixed-architecture bundles before downloading tools.
python3 - "$bundle" "$expected_machine" <<'PY'
import pathlib
import struct
import sys

bundle = pathlib.Path(sys.argv[1])
for name in ('mithka', 'lib/libflutter_linux_gtk.so', 'lib/libapp.so', 'lib/libtdjson.so'):
    with (bundle / name).open('rb') as binary:
        header = binary.read(20)
    if (len(header) != 20 or header[:6] != b'\x7fELF\x02\x01'
            or struct.unpack_from('<H', header, 18)[0] != int(sys.argv[2])):
        raise SystemExit(f'Wrong ELF architecture: {name}')
if not (bundle / 'data/flutter_assets').is_dir():
    raise SystemExit('Missing Flutter assets')
PY

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
appdir="$work/Mithka.AppDir"
mkdir -p "$appdir/usr/bin" "$(dirname -- "$output")"
cp -a "$bundle/." "$appdir/usr/bin/"
# Flutter resolves data and lib relative to its executable. Keep that layout
# while allowing linuxdeploy to collect plugin and dlopen dependencies in lib.
mv "$appdir/usr/bin/lib" "$appdir/usr/lib"
ln -s ../lib "$appdir/usr/bin/lib"
# MDK ships this optional decoder on arm64, but its librockchip_mpp dependency
# belongs to Rockchip board images. Generic desktop AppImages use MDK's FFmpeg
# fallback instead; the original portable tarball retains the optional plugin.
rm -f "$appdir/usr/lib/libmdk-rockchip.so"
install -m 0644 \
  "$repository_root/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png" \
  "$work/ad.neko.mithka.png"

tool="$work/linuxdeploy-$appimage_arch.AppImage"
curl --fail --location --retry 3 \
  "https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-$appimage_arch.AppImage" \
  --output "$tool"
printf '%s  %s\n' "$tool_digest" "$tool" | sha256sum --check --status
curl --fail --location --retry 3 \
  'https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/linuxdeploy-plugin-gtk.sh' \
  --output "$work/linuxdeploy-plugin-gtk.sh"
printf '%s  %s\n' \
  b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171 \
  "$work/linuxdeploy-plugin-gtk.sh" | sha256sum --check --status
chmod 0755 "$tool" "$work/linuxdeploy-plugin-gtk.sh"

# Explicit --library arguments also collect the dependencies of libraries
# loaded through Dart FFI, which ldd on the launcher alone cannot see.
libraries=()
while IFS= read -r -d '' library; do
  libraries+=(--library "$library")
done < <(find "$appdir/usr/lib" -type f -name '*.so*' -print0)
export ARCH="$appimage_arch" OUTPUT="$output" APPIMAGE_EXTRACT_AND_RUN=1
export DEPLOY_GTK_VERSION=3
# Some FFI libraries (including FFmpeg's bundled libc++) have no peer-library
# RUNPATH. Resolve those from the bundle while linuxdeploy scans dependencies.
export LD_LIBRARY_PATH="$appdir/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$tool" --appdir "$appdir" --executable "$appdir/usr/bin/mithka" \
  "${libraries[@]}" --plugin gtk \
  --desktop-file "$repository_root/linux/appimage/ad.neko.mithka.desktop" \
  --icon-file "$work/ad.neko.mithka.png" \
  --custom-apprun "$repository_root/linux/appimage/AppRun" --output appimage
test -s "$output"
chmod 0755 "$output"

# Exercise the produced runtime without requiring FUSE on the CI runner.
mkdir "$work/check"
(cd "$work/check" && "$output" --appimage-extract >/dev/null)
test -x "$work/check/squashfs-root/AppRun"
test -x "$work/check/squashfs-root/usr/bin/mithka"
test -f "$work/check/squashfs-root/usr/bin/lib/libtdjson.so"
test -d "$work/check/squashfs-root/usr/bin/data/flutter_assets"
echo "AppImage created and extracted successfully: $output"
