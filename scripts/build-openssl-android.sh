#!/usr/bin/env bash
#
# build-openssl-android.sh
#
# Cross-compiles a static OpenSSL (libcrypto.a + libssl.a + headers) per Android
# ABI into .tdlib-build/openssl/<abi>, which is exactly where
# build-tdjson-android.sh expects it (OPENSSL_ROOT_DIR / .../lib/lib{crypto,ssl}.a
# + .../include). TDLib links OpenSSL statically, so this must be built before
# the tdjson build.
#
# Requirements: Android NDK (ANDROID_NDK_HOME or auto-detected), curl, make, perl.
#
# Usage:
#   ./scripts/build-openssl-android.sh [abi ...]
#   (default ABIs: arm64-v8a armeabi-v7a x86_64)
#   OPENSSL_VERSION / ANDROID_API override the defaults.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.tdlib-build"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.2}"
API="${ANDROID_API:-21}"

if [[ "$#" -gt 0 ]]; then
  ABIS=("$@")
else
  ABIS=(arm64-v8a armeabi-v7a x86_64)
fi

# Locate the NDK (same logic as build-tdjson-android.sh).
: "${ANDROID_NDK_HOME:=}"
if [[ -z "$ANDROID_NDK_HOME" ]]; then
  SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  if [[ -d "$SDK/ndk" ]]; then
    ANDROID_NDK_HOME="$SDK/ndk/$(ls "$SDK/ndk" | sort -V | tail -1)"
  fi
fi
if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "ERROR: Android NDK not found. Set ANDROID_NDK_HOME." >&2
  exit 1
fi

# NDK clang toolchain on PATH (OpenSSL's android-* targets pick up clang from it).
HOST_TAG="linux-x86_64"
[[ "$(uname)" == "Darwin" ]] && HOST_TAG="darwin-x86_64"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/bin:$PATH"
echo "NDK: $ANDROID_NDK_HOME"

mkdir -p "$BUILD_DIR"
SRC="$BUILD_DIR/openssl-$OPENSSL_VERSION"
if [[ ! -d "$SRC" ]]; then
  echo "Downloading OpenSSL $OPENSSL_VERSION..."
  curl -fsSL \
    "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" \
    -o "$BUILD_DIR/openssl.tar.gz"
  mkdir -p "$SRC"
  tar xzf "$BUILD_DIR/openssl.tar.gz" -C "$SRC" --strip-components=1
fi

# ABI → OpenSSL Configure target.
declare -A TARGET=(
  [arm64-v8a]=android-arm64
  [armeabi-v7a]=android-arm
  [x86_64]=android-x86_64
  [x86]=android-x86
)

for ABI in "${ABIS[@]}"; do
  PREFIX="$BUILD_DIR/openssl/$ABI"
  if [[ -f "$PREFIX/lib/libssl.a" && -f "$PREFIX/lib/libcrypto.a" ]]; then
    echo "OpenSSL $ABI already built — skipping."
    continue
  fi
  T="${TARGET[$ABI]:-}"
  [[ -n "$T" ]] || { echo "Unknown ABI: $ABI" >&2; exit 1; }
  echo "Building OpenSSL for $ABI ($T)..."
  (
    cd "$SRC"
    make clean >/dev/null 2>&1 || true
    ./Configure "$T" "-D__ANDROID_API__=$API" \
      no-shared no-tests no-apps no-docs --libdir=lib --prefix="$PREFIX"
    make -j"$(getconf _NPROCESSORS_ONLN)" build_libs
    make install_dev
  )
  echo "  OK: $PREFIX/lib/{libssl,libcrypto}.a"
done

echo "Done."
