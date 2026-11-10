#!/usr/bin/env bash
# Publish a debug APK that can run on a real ARM phone.
#
# Why this exists: `flutter test integration_test/... -d <android device>`
# writes its test APK to build/app/outputs/flutter-apk/app-debug.apk and ships
# libflutter.so only for the target device ABI (x86_64 on the emulator). That
# file installs fine but crashes immediately on an arm64 phone (missing
# lib/arm64-v8a/libflutter.so) and its Dart entrypoint is the test, not the app.
#
# This script builds the real product debug APK (all ABIs, lib/main.dart),
# verifies it, and publishes it to artifacts/mvp/android/app-debug.apk — a path
# the test tool never writes.
#
# Usage:
#   tool/android_debug_apk.sh                build + verify + publish
#   tool/android_debug_apk.sh verify <apk>   verify an APK only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ART="$ROOT/artifacts/mvp"

fail() { echo "FAIL: $*" >&2; exit 1; }

verify_apk() {
  local apk="$1"
  [[ -f "$apk" ]] || fail "no such APK: $apk"

  local listing
  listing="$(unzip -l "$apk" 2>/dev/null)" || fail "$apk is not a readable APK/zip"

  # Real phones are arm64 (e.g. Galaxy Z Flip7) or armeabi-v7a; both need the
  # Flutter engine. The integration-test/emulator build has it only for x86_64.
  local abi
  for abi in arm64-v8a armeabi-v7a; do
    grep -q "lib/$abi/libflutter.so" <<<"$listing" \
      || fail "$apk lacks lib/$abi/libflutter.so — test/emulator build, not a phone build"
  done

  # Debug APKs carry a plain-text kernel blob; an integration_test entrypoint
  # still contains the test package. Release APKs carry libapp.so instead.
  local blob
  blob="$(mktemp)"
  if unzip -p "$apk" assets/flutter_assets/kernel_blob.bin >"$blob" 2>/dev/null; then
    if grep -aqF "package:integration_test" "$blob"; then
      rm -f "$blob"
      fail "$apk was built with an integration_test entrypoint, not lib/main.dart"
    fi
  elif ! grep -q "lib/arm64-v8a/libapp.so" <<<"$listing"; then
    rm -f "$blob"
    fail "$apk has neither a debug kernel nor libapp.so"
  fi
  rm -f "$blob"

  echo "OK: $apk"
}

case "${1:-build}" in
  verify)
    [[ -n "${2:-}" ]] || fail "usage: $0 verify <apk>"
    verify_apk "$2"
    ;;
  build)
    cd "$ROOT"
    export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/tmp/eir-gradle-home}"
    flutter build apk --debug --target lib/main.dart
    src="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
    verify_apk "$src"
    mkdir -p "$ART/android" "$ART/checksums"
    cp "$src" "$ART/android/app-debug.apk"
    sha256sum "$ART/android/app-debug.apk" | tee "$ART/checksums/android-app-debug.sha256"
    echo "Publishable APK: $ART/android/app-debug.apk"
    ;;
  *)
    fail "unknown command: $1 (use: build | verify <apk>)"
    ;;
esac
