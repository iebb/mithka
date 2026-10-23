#!/usr/bin/env bash
# enable-ohos-plugins.sh — activate the HarmonyOS plugin overlay before an
# OHOS build, and restore the stock pubspec afterwards.
#
# Why: the ohos plugin ports for package_info_plus / permission_handler /
# file_picker / geolocator / flutter_secure_storage / record declare
# `environment: sdk <3.0.0` on every published version, so they cannot sit in
# the main pubspec.yaml — stock CI (`flutter pub get`) would fail version
# solving. The Dart-3-compatible ports (see pubspec.yaml) are regular
# dependencies already; this script layers the blocked ones on top via
# dependency_overrides, which ignores the overridden packages' sdk bounds.
#
# Usage:
#   scripts/enable-ohos-plugins.sh apply    # merge overlay into pubspec.yaml
#   scripts/enable-ohos-plugins.sh revert   # restore pubspec.yaml from backup
#
# `apply` preserves the existing dependency_overrides block verbatim (the fvp
# git pin) and appends the overlay's scalar overrides. A backup is kept so
# `revert` restores exactly the previous content even if it had uncommitted
# changes. Run with the OHOS Flutter fork's `flutter` on PATH, then
# `flutter pub get` before building; run `revert` before switching back to
# stock builds.
set -euo pipefail

cd "$(dirname "$0")/.."
OVERLAY="pubspec_overrides.ohos.yaml"
TARGET="pubspec.yaml"
BACKUP="pubspec.yaml.ohos-backup"

cmd="${1:-}"
if [[ "$cmd" != "apply" && "$cmd" != "revert" ]]; then
  echo "usage: $0 apply|revert" >&2
  exit 2
fi

if [[ "$cmd" == "revert" ]]; then
  if [[ -f "$BACKUP" ]]; then
    mv "$BACKUP" "$TARGET"
    echo "restored $TARGET from backup"
  else
    git checkout -- "$TARGET" && echo "restored $TARGET from git"
  fi
  exit 0
fi

[[ -f "$OVERLAY" ]] || { echo "overlay $OVERLAY not found" >&2; exit 1; }

python3 - "$TARGET" "$OVERLAY" "$BACKUP" <<'PY'
import sys

target, overlay, backup = sys.argv[1:4]
t_lines = open(target).read().splitlines()
o_lines = open(overlay).read().splitlines()

# Scalar "key: value" entries under the overlay's dependency_overrides section.
ovr, section = {}, None
for raw in o_lines:
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    if not raw.startswith((" ", "\t")):
        section = raw.rstrip(":").strip() if raw.rstrip().endswith(":") else None
        continue
    if section == "dependency_overrides" and ":" in raw:
        key, _, val = raw.strip().partition(":")
        ovr.setdefault(key.strip(), val.strip())

open(backup, "w").write("\n".join(t_lines) + "\n")

# Split pubspec.yaml into pre / overrides-body / post around the block.
pre, body, post = [], [], []
state = "pre"
for l in t_lines:
    if state == "pre":
        if l == "dependency_overrides:":
            state = "body"
            continue
        pre.append(l)
    elif state == "body":
        if l and not l[0].isspace():
            state = "post"
            post.append(l)
        else:
            body.append(l)
    else:
        post.append(l)

# Keep existing body lines except scalar keys the overlay re-defines.
body_kept = [
    l for l in body
    if not (l.strip() and not l.strip().startswith("#")
            and l.strip().partition(":")[0].strip() in ovr)
]
appended = [f"  {k}: {v}" for k, v in ovr.items()]

final = pre + ["dependency_overrides:"] + body_kept + appended
final.append("")
final += post

open(target, "w").write("\n".join(final).rstrip("\n") + "\n")
print(f"merged {len(appended)} overrides into {target} (backup: {backup})")
PY

# Never commit the backup or a pubspec.lock rewritten for OHOS.
if ! grep -q "^/pubspec.yaml.ohos-backup$" .gitignore 2>/dev/null; then
  printf '\n# OHOS plugin overlay working copies (scripts/enable-ohos-plugins.sh)\n/pubspec.yaml.ohos-backup\n' >> .gitignore
  echo "added /pubspec.yaml.ohos-backup to .gitignore"
fi
