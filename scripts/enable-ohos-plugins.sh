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
# Usage (from the repo root):
#   scripts/enable-ohos-plugins.sh apply    # merge overlay into pubspec.yaml
#   scripts/enable-ohos-plugins.sh revert   # restore pubspec.yaml and
#                                           # pubspec.lock from their backups
#
# Safety contract (PR #272 review): the operation is transactional on the two
# files `flutter pub get` rewrites — pubspec.yaml and pubspec.lock.
#
#   apply  refuses to run when an overlay is already active (a backup exists)
#          or when a backup would be overwritten, so repeated apply is a
#          no-op refusal, never a loss of the pre-overlay original.
#   revert refuses to run when no apply is active, so it can never
#          `git checkout` away a pubspec.yaml the user had edited but not
#          committed. It restores the exact bytes of both files, including
#          uncommitted local edits present at apply time.
#
# Neither command edits any other tracked file, and the script never
# resets, checks out or discards user files. Run with the OHOS Flutter
# fork's `flutter` on PATH, then `flutter pub get` before building; run
# `revert` before switching back to stock builds.
set -euo pipefail

cd "$(dirname "$0")/.."
OVERLAY="pubspec_overrides.ohos.yaml"
TARGET="pubspec.yaml"
LOCK="pubspec.lock"
BACKUP="pubspec.yaml.ohos-backup"
LOCK_BACKUP="pubspec.lock.ohos-backup"

die() { echo "enable-ohos-plugins: $*" >&2; exit 1; }

cmd="${1:-}"
case "$cmd" in
  apply|revert) ;;
  *) echo "usage: $0 apply|revert" >&2; exit 2 ;;
esac

if [[ "$cmd" == "revert" ]]; then
  [[ -f "$BACKUP" ]] || die "no active overlay to revert (no $BACKUP). Refusing to touch $TARGET so uncommitted edits are not lost; restore it manually if you really meant to."
  [[ ! -f "$LOCK_BACKUP" || -f "$LOCK" ]] || die "expected $LOCK with a pending $LOCK_BACKUP"
  mv -f "$BACKUP" "$TARGET"
  if [[ -f "$LOCK_BACKUP" ]]; then
    mv -f "$LOCK_BACKUP" "$LOCK"
  else
    # The original had no lockfile (the backup's absence records that), so a
    # lock that OHOS pub get created during the overlay must not survive the
    # revert either: restore absence as well as content.
    rm -f "$LOCK"
  fi
  echo "restored $TARGET and $LOCK from backups"
  exit 0
fi

# apply: refuse unsafe states instead of discarding work.
[[ -f "$OVERLAY" ]] || die "overlay $OVERLAY not found"
[[ -f "$BACKUP" ]] && die "overlay already active ($BACKUP exists). Run revert first; refusing to overwrite the only backup of the original pubspec."
[[ -f "$LOCK_BACKUP" ]] && die "stale $LOCK_BACKUP left behind. Run revert or remove it manually first."
[[ -f "$TARGET" ]] || die "$TARGET not found"

python3 - "$TARGET" "$OVERLAY" "$BACKUP" "$LOCK" "$LOCK_BACKUP" <<'PY'
import shutil
import sys

target, overlay, backup, lock, lock_backup = sys.argv[1:6]
t_text = open(target).read()
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

# Back up the exact original bytes of both files pub get rewrites: the
# YAML is copied byte-for-byte (newline style included), never re-encoded
# through text mode, so a dirty CRLF file restores byte-identically.
with open(target, "rb") as f:
    t_bytes = f.read()
with open(backup, "wb") as f:
    f.write(t_bytes)
try:
    shutil.copy2(lock, lock_backup)
except FileNotFoundError:
    pass  # pub get has not run yet; revert then leaves the lock absent too.

t_lines = t_text.splitlines()

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
print(f"merged {len(appended)} overrides into {target} (backups: {backup}, {lock_backup})")
PY

# The backups and a lockfile rewritten for OHOS must never be committed; the
# committed ignore entries (/pubspec.yaml.ohos-backup,
# /pubspec.lock.ohos-backup) keep them out of the working copy's status.
