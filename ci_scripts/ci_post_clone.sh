#!/bin/sh
set -e

# Xcode Cloud discovers custom scripts from the repository root. Dispatch to
# the platform-specific setup without changing the established iOS workflow.
# MITHKA_CI_PLATFORM is a workflow environment variable configured on the
# macOS Xcode Cloud workflow. Keep the historical iOS fallback for local
# invocations and existing workflows that don't provide it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
case "${MITHKA_CI_PLATFORM:-ios}" in
  macos)
    exec "$SCRIPT_DIR/macos_post_clone.sh"
    ;;
  ios|"")
    exec "$SCRIPT_DIR/../ios/ci_scripts/ci_post_clone.sh"
    ;;
  *)
    echo "error: unsupported Mithka CI platform: ${MITHKA_CI_PLATFORM}" >&2
    exit 1
    ;;
esac
