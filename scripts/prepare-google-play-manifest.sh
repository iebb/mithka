#!/bin/sh
set -eu

# Direct APK builds can open downloaded updates through Android's package
# installer. Google Play builds update through Play and must not request the
# restricted REQUEST_INSTALL_PACKAGES permission.
manifest="${1:-android/app/src/main/AndroidManifest.xml}"
permission="android.permission.REQUEST_INSTALL_PACKAGES"

if ! grep -q "$permission" "$manifest"; then
  echo "error: expected $permission in $manifest" >&2
  exit 1
fi

sed -i.bak "/$permission/d" "$manifest"
rm -f "${manifest}.bak"

if grep -q "$permission" "$manifest"; then
  echo "error: failed to remove $permission from $manifest" >&2
  exit 1
fi

echo "Removed direct APK install permission from the Google Play manifest"
