#!/bin/sh
# Fail when a built iOS app's compiled asset catalogue exceeds its budget.
# Alternate app icons dominate Assets.car; see tool/optimize_app_artwork.py.
set -eu

app="$1"
budget_mib="${2:-100}"
catalogue="$app/Assets.car"
test -f "$catalogue"
bytes="$(stat -f%z "$catalogue")"
mib="$((bytes / 1048576))"
echo "Assets.car: $mib MiB (budget $budget_mib MiB)"
if [ "$bytes" -gt "$((budget_mib * 1048576))" ]; then
  echo "::error::Assets.car is $mib MiB, over the $budget_mib MiB budget. Keep flat alternate icons as .appiconset only."
  exit 1
fi
