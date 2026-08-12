#!/bin/sh
set -eu

# Apple build numbers are the full Git commit height. The 1.0.0 train starts
# after the temporary epoch-numbered migration builds, so no offset is needed.
BUILD_NUMBER_OFFSET=0
COMMIT="${1:-HEAD}"

COMMIT_HEIGHT="$(git rev-list --count "$COMMIT")"
case "$COMMIT_HEIGHT" in
  ''|*[!0-9]*)
    echo "error: expected a numeric commit height, got $COMMIT_HEIGHT" >&2
    exit 1
    ;;
esac

if [ "$COMMIT_HEIGHT" -lt 1 ]; then
  echo "error: commit height must be positive" >&2
  exit 1
fi

printf '%s\n' "$((BUILD_NUMBER_OFFSET + COMMIT_HEIGHT))"
