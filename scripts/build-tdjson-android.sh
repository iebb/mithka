#!/usr/bin/env bash
#
# build-tdjson-android.sh
#
# Cross-compiles TDLib's `tdjson` shared library for Android and installs the
# per-ABI .so files into android/app/src/main/jniLibs/, where the Android Gradle
# plugin bundles them automatically. The Dart FFI layer then resolves the
# symbols at runtime via DynamicLibrary.open('libtdjson.so').
#
# Requirements:
#   - Android NDK (set ANDROID_NDK_HOME, or it is auto-detected under
#     $ANDROID_HOME/ndk/<version>)
#   - cmake, git, gperf, and a cross-built OpenSSL per ABI under
#     .tdlib-build/openssl/<abi> (or point OPENSSL_ROOT_DIR at one).
#
# Usage:
#   ./scripts/build-tdjson-android.sh [abi ...]
#   (default ABIs: arm64-v8a armeabi-v7a x86_64)
#   Set TD_ENABLE_LTO=OFF for a faster (larger) build.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.tdlib-build"
JNI_DIR="$REPO_ROOT/android/app/src/main/jniLibs"

if [[ "$#" -gt 0 ]]; then
  ABIS=("$@")
else
  ABIS=(arm64-v8a armeabi-v7a x86_64)
fi

: "${ANDROID_NDK_HOME:=}"
if [[ -z "$ANDROID_NDK_HOME" ]]; then
  SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  if [[ -d "$SDK/ndk" ]]; then
    ANDROID_NDK_HOME="$SDK/ndk/$(ls "$SDK/ndk" | sort -V | tail -1)"
  fi
fi
if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "ERROR: Android NDK not found. Install it and set ANDROID_NDK_HOME." >&2
  exit 1
fi
echo "NDK: $ANDROID_NDK_HOME"

mkdir -p "$BUILD_DIR"
if [[ ! -d "$BUILD_DIR/td" ]]; then
  echo "Cloning TDLib..."
  git clone --depth 1 https://github.com/tdlib/td.git "$BUILD_DIR/td"
fi

# TDLib generates some sources (e.g. mime_type_to_extension.cpp) with host tools
# at build time; cross-compiling needs them pre-generated. Build the native
# `prepare_cross_compiling` target with the HOST compiler (force it, since the
# NDK toolchain may be on PATH) + host OpenSSL.
if [[ ! -f "$BUILD_DIR/td/tdutils/generate/auto/mime_type_to_extension.cpp" ]]; then
  echo "Preparing cross-compiling (host source generation)..."
  cmake -S "$BUILD_DIR/td" -B "$BUILD_DIR/build-native" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DOPENSSL_ROOT_DIR="${HOST_OPENSSL_ROOT_DIR:-/opt/homebrew/opt/openssl@3}"
  cmake --build "$BUILD_DIR/build-native" --target prepare_cross_compiling \
    -j"$(getconf _NPROCESSORS_ONLN)"
fi

for ABI in "${ABIS[@]}"; do
  echo "Building tdjson for ${ABI}..."
  OUT="$BUILD_DIR/build-android-${ABI}"
  OSSL="${OPENSSL_ROOT_DIR:-$BUILD_DIR/openssl/${ABI}}"
  # The Android toolchain restricts find_* to the NDK sysroot, so OPENSSL_ROOT_DIR
  # alone isn't enough — point CMake straight at the static libs/headers and let
  # it search outside the find-root.
  rm -rf "$OUT"
  cmake -S "$BUILD_DIR/td" -B "$OUT" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="${ABI}" \
    -DANDROID_PLATFORM=android-21 \
    -DCMAKE_BUILD_TYPE=Release \
    -DTD_ENABLE_LTO="${TD_ENABLE_LTO:-ON}" \
    -DOPENSSL_ROOT_DIR="$OSSL" \
    -DOPENSSL_INCLUDE_DIR="$OSSL/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$OSSL/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$OSSL/lib/libssl.a" \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
  cmake --build "$OUT" --target tdjson -j"$(getconf _NPROCESSORS_ONLN)"

  mkdir -p "$JNI_DIR/${ABI}"
  cp "$OUT/libtdjson.so" "$JNI_DIR/${ABI}/libtdjson.so"
  # Strip symbols/debug info (an unstripped tdjson is ~500MB; stripped ~37MB).
  # --strip-unneeded keeps the exported td_json_client_* dynamic symbols.
  STRIP="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-strip | head -1)"
  "$STRIP" --strip-unneeded "$JNI_DIR/${ABI}/libtdjson.so"
  echo "  OK: $JNI_DIR/${ABI}/libtdjson.so ($(du -h "$JNI_DIR/${ABI}/libtdjson.so" | cut -f1))"
done

echo "Done. Run: flutter run"
