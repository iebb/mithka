#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <X.Y.Z[+build]>" >&2
  exit 64
fi

source_version="${1%%+*}"
marketing_version="$(
  printf '%s\n' "$source_version" |
    awk -F. 'NF == 3 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { print $1 "." $2 ".0" }'
)"

if [ -z "$marketing_version" ]; then
  echo "error: expected a numeric X.Y.Z macOS version, got $source_version" >&2
  exit 1
fi

printf '%s\n' "$marketing_version"
