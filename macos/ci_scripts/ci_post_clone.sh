#!/bin/sh
set -eu

# Xcode Cloud resolves custom scripts relative to the macOS workspace root.
# Keep the implementation shared with local/CI validation at repository root.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/../../ci_scripts/macos_post_clone.sh"
