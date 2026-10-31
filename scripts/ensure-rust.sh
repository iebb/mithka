#!/bin/sh
#
# ensure-rust.sh — makes cargo and the given Rust targets available to the
# packages/mithka_proxy build hook. The hook runs cargo from inside
# `flutter build` / xcodebuild and also looks in $HOME/.cargo/bin, which is
# where rustup installs, so a later build phase finds it without this PATH.
#
#   scripts/ensure-rust.sh aarch64-apple-ios [more targets...]
#
# Installs a minimal stable toolchain only when no cargo is present; crate
# versions stay pinned by packages/mithka_proxy/native/Cargo.lock.

set -e

if ! command -v cargo >/dev/null 2>&1 && [ -x "$HOME/.cargo/bin/cargo" ]; then
  PATH="$HOME/.cargo/bin:$PATH"
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo "▸ installing a minimal Rust toolchain"
  tmp="$(mktemp -d)"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-delay 2 \
    https://sh.rustup.rs -o "$tmp/rustup-init.sh"
  sh "$tmp/rustup-init.sh" -y --profile minimal --default-toolchain stable \
    --no-modify-path
  rm -rf "$tmp"
  PATH="$HOME/.cargo/bin:$PATH"
fi
if [ "$#" -gt 0 ] && command -v rustup >/dev/null 2>&1; then
  rustup target add "$@"
fi
cargo --version
