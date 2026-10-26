#!/bin/sh
set -eu

# Preserve the exact source/GitHub X.Y.Z marketing version on every branch.
# Only the optional +build suffix is removed; Apple build numbers are assigned
# separately. The optional branch argument remains accepted for existing callers
# but must never change the patch or select a different marketing train.

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <X.Y.Z[+build]> [branch]" >&2
  exit 64
fi

source_version="${1%%+*}"

if ! printf '%s\n' "$source_version" |
  awk -F. 'NF == 3 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { found = 1 }
    END { exit found ? 0 : 1 }'; then
  echo "error: expected a numeric X.Y.Z version, got $source_version" >&2
  exit 1
fi

printf '%s\n' "$source_version"
