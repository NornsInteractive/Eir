#!/usr/bin/env bash
# Build Android Tailcat C-shared native libraries with 16KB ELF page size alignment.
#
# Android 15+ devices using 16KB memory page sizes enforce that ELF LOAD segments
# in shared objects have p_align >= 0x4000 (16KB). Otherwise dlopen() will fail.
#
# This script compiles native/tailcat/tailcat_bridge.go for:
#   - arm64-v8a -> android/app/src/main/jniLibs/arm64-v8a/libtailcat.so
#   - x86_64    -> android/app/src/main/jniLibs/x86_64/libtailcat.so
#
# Usage:
#   tool/build_tailcat_android.sh           # Build and verify all ABIs
#   tool/build_tailcat_android.sh arm64     # Build and verify arm64-v8a only
#   tool/build_tailcat_android.sh x86_64    # Build and verify x86_64 only
#   tool/build_tailcat_android.sh verify    # Verify existing .so files only

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JNILIBS="$ROOT/android/app/src/main/jniLibs"
SRC_DIR="$ROOT/native/tailcat"

# Detect NDK directory
NDK_DIR="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
if [[ -z "$NDK_DIR" || ! -d "$NDK_DIR" ]]; then
  for cand in /opt/android-sdk/ndk/28.2.13676358 /opt/android-sdk/ndk/27.1.12297006; do
    if [[ -d "$cand" ]]; then
      NDK_DIR="$cand"
      break
    fi
  done
fi

[[ -n "$NDK_DIR" && -d "$NDK_DIR" ]] || {
  echo "ERROR: Android NDK not found. Set ANDROID_NDK_HOME or install NDK 27/28." >&2
  exit 1
}

TOOLCHAIN="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"
API_LEVEL="24"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

verify_so() {
  local abi="$1"
  local so_path="$JNILIBS/$abi/libtailcat.so"

  [[ -f "$so_path" ]] || fail "Missing library: $so_path"

  echo "=== Verifying $abi ($so_path) ==="

  # Check 16KB alignment on LOAD segments
  local bad_align=0
  while read -r line; do
    local align
    align="$(echo "$line" | awk '{print $NF}')"
    # p_align should be at least 0x4000 (16384) or 0x10000 (65536)
    if [[ "$align" == "0x1000" || "$align" == "0x2000" ]]; then
      echo "ERROR: Segment alignment is $align (< 0x4000 / 16KB): $line" >&2
      bad_align=1
    fi
  done < <(readelf -l "$so_path" | grep -A 1 "LOAD" | grep -E "R|RW|R E")

  if [[ "$bad_align" -ne 0 ]]; then
    fail "$abi/libtailcat.so failed 16KB page alignment check!"
  fi
  echo "  [OK] 16KB ELF LOAD segment alignment verified (p_align >= 0x4000)"

  # Check required exports
  local sym_dump
  sym_dump="$(nm -D "$so_path")"
  local missing_sym=0
  for sym in TailcatStartServer TailcatStartClient TailcatSend TailcatIsDirect TailcatClose TailcatFree; do
    if ! echo "$sym_dump" | grep -w "$sym" >/dev/null; then
      echo "ERROR: Symbol $sym not exported in $so_path" >&2
      missing_sym=1
    fi
  done

  if [[ "$missing_sym" -ne 0 ]]; then
    fail "$abi/libtailcat.so is missing required FFI export symbols!"
  fi
  echo "  [OK] All 6 FFI symbols (including TailcatFree) verified"
  echo "  SHA-256: $(sha256sum "$so_path" | awk '{print $1}')"
}

build_abi() {
  local abi="$1"
  local goarch="$2"
  local cc_name="$3"

  local cc="$TOOLCHAIN/$cc_name"
  [[ -x "$cc" ]] || fail "Compiler not found: $cc"

  local out_dir="$JNILIBS/$abi"
  mkdir -p "$out_dir"
  local out_so="$out_dir/libtailcat.so"
  local out_h="$out_dir/libtailcat.h"

  echo "Building $abi using $cc..."
  (
    cd "$SRC_DIR"
    CGO_ENABLED=1 \
    CC="$cc" \
    GOOS=android \
    GOARCH="$goarch" \
    go build -buildmode=c-shared \
      -ldflags="-extldflags '-Wl,-z,max-page-size=16384'" \
      -o "$out_so" .
  )

  # Clean up generated header in jniLibs
  rm -f "$out_h"

  verify_so "$abi"
}

TARGET="${1:-all}"

case "$TARGET" in
  arm64|arm64-v8a)
    build_abi "arm64-v8a" "arm64" "aarch64-linux-android${API_LEVEL}-clang"
    ;;
  x86_64)
    build_abi "x86_64" "amd64" "x86_64-linux-android${API_LEVEL}-clang"
    ;;
  verify)
    verify_so "arm64-v8a"
    verify_so "x86_64"
    ;;
  all)
    build_abi "arm64-v8a" "arm64" "aarch64-linux-android${API_LEVEL}-clang"
    build_abi "x86_64" "amd64" "x86_64-linux-android${API_LEVEL}-clang"
    ;;
  *)
    fail "Unknown target: $TARGET (use: all | arm64 | x86_64 | verify)"
    ;;
esac

echo "Tailcat Android native libraries build & verification finished successfully."
