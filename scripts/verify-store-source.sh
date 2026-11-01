#!/bin/bash
set -euo pipefail

if [ "${GITHUB_REPOSITORY:-}" != 'iebb/mithka' ]; then
  echo 'Store builds must use the canonical Mithka repository.' >&2
  exit 1
fi
expected="${EXPECTED_SOURCE_COMMIT:-}"
if [ -n "$expected" ]; then
  if ! [[ "$expected" =~ ^[a-f0-9]{40}$ ]] || [ "$expected" != "${GITHUB_SHA:-}" ]; then
    echo 'The dispatched source does not match the immutable release snapshot.' >&2
    exit 1
  fi
fi

case "${GITHUB_REF:-}" in
  refs/tags/store-v*)
    if [ "${GITHUB_EVENT_NAME:-}" != 'workflow_dispatch' ] || [ -z "$expected" ]; then
      echo 'Store snapshot tags require an exact-source manual dispatch.' >&2
      exit 1
    fi
    version="$(sh scripts/apple_marketing_version.sh "$(awk '/^version:/ { print $2; exit }' pubspec.yaml)")"
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[1-9][0-9]*$ ]] || [ "$GITHUB_REF" != "refs/tags/store-v$version" ]; then
      echo 'Store tag and normal nonzero patch version must match.' >&2
      exit 1
    fi
    ;;
esac
