#!/bin/sh
set -eu

# The marketing version an Apple upload carries, for the branch it is built
# from.
#
# App Store Connect reviews a marketing version rather than a build. A nightly
# increments its patch every time master moves, so those uploads collapse onto
# one X.Y.0 train and are told apart by their build number; without that, every
# night would open a review train of its own.
#
# A release is the opposite case: it is named for the exact version it ships, so
# it keeps its patch. Anything else — a manual dispatch, a local run — is
# treated as a nightly, which is the choice that cannot pollute the store with
# an unintended train.

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <X.Y.Z[+build]> [branch]" >&2
  exit 64
fi

source_version="${1%%+*}"
branch="${2:-}"

if ! printf '%s\n' "$source_version" |
  awk -F. 'NF == 3 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { found = 1 }
    END { exit found ? 0 : 1 }'; then
  echo "error: expected a numeric X.Y.Z version, got $source_version" >&2
  exit 1
fi

case "$branch" in
  release | release-* | release/*)
    printf '%s\n' "$source_version"
    ;;
  *)
    printf '%s\n' "$source_version" | awk -F. '{ print $1 "." $2 ".0" }'
    ;;
esac
