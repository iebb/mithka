#!/usr/bin/env bash
#
# bump-version.sh — bump the app version in pubspec.yaml, commit, and tag.
#
# pubspec version is "X.Y.Z+B": X.Y.Z is the user-facing semver (also the release
# tag the update-checker compares), and B is Flutter's package build metadata.
# Android releases use the separate monotonic value in android/version-code.txt.
# This bumps all three values, then creates the git tag "vX.Y.Z". Push the commit
# to the release branch to trigger the stable workflow; pushing master does not
# build an APK.
#
# Usage:
#   ./scripts/bump-version.sh [major|minor|patch]   # default: patch
#   ./scripts/bump-version.sh patch --push          # also push commit + tag
#
set -euo pipefail
cd "$(dirname "$0")/.."

part="patch"
push=false
for arg in "$@"; do
  case "$arg" in
    major|minor|patch) part="$arg" ;;
    --push) push=true ;;
    *) echo "usage: $0 [major|minor|patch] [--push]" >&2; exit 1 ;;
  esac
done

cur="$(grep -E '^version:' pubspec.yaml | head -1 | sed -E 's/^version:[[:space:]]*//')"
semver="${cur%%+*}"
build="${cur##*+}"
[ "$build" = "$cur" ] && build=0   # no "+B" present
IFS='.' read -r MA MI PA <<< "$semver"

case "$part" in
  major) MA=$((MA + 1)); MI=0; PA=0 ;;
  minor) MI=$((MI + 1)); PA=0 ;;
  patch) PA=$((PA + 1)) ;;
esac
build=$((build + 1))
new_semver="$MA.$MI.$PA"
new="$new_semver+$build"

android_version_file="android/version-code.txt"
android_version_code="$(bash scripts/android-version-code.sh "$android_version_file")"
next_android_version_code=$((android_version_code + 1))
current_epoch="$(date -u '+%s')"
if [ "$current_epoch" -gt "$next_android_version_code" ]; then
  next_android_version_code="$current_epoch"
fi

# Rewrite the version line (portable sed for macOS + Linux).
sed -i.bak -E "s/^version:.*/version: $new/" pubspec.yaml && rm -f pubspec.yaml.bak
printf '%s\n' "$next_android_version_code" > "$android_version_file"
bash scripts/android-version-code.sh "$android_version_file" >/dev/null

echo "Version: $cur → $new"
echo "Android version code: $android_version_code → $next_android_version_code"

if git rev-parse --git-dir >/dev/null 2>&1; then
  git add pubspec.yaml "$android_version_file"
  git commit -m "Bump version to $new"
  git tag "v$new_semver"
  echo "Committed + tagged v$new_semver."
  # Push the branch + ONLY the new tag — never --tags, which would also push
  # stale local tags and trigger spurious release builds.
  if $push; then
    git push origin HEAD "v$new_semver"
    echo "Pushed — a release-branch push triggers the stable build."
  else
    echo "Push this commit from the release branch to trigger the stable build:"
    echo "  git push origin HEAD v$new_semver"
  fi
fi
