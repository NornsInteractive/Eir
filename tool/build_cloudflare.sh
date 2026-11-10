#!/usr/bin/env bash
set -e

echo "==> [Cloudflare Build] Checking Flutter environment..."

if ! command -v flutter >/dev/null 2>&1; then
  echo "==> [Cloudflare Build] Flutter not detected. Downloading Flutter 3.24.5..."
  FLUTTER_INSTALL_DIR="/tmp/flutter"
  if [ ! -x "$FLUTTER_INSTALL_DIR/bin/flutter" ]; then
    mkdir -p /tmp
    curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz" | tar -xJ -C /tmp
  fi
  export PATH="$FLUTTER_INSTALL_DIR/bin:$PATH"
fi

echo "==> [Cloudflare Build] Using Flutter:"
flutter --version

echo "==> [Cloudflare Build] Fetching dependencies..."
flutter pub get

echo "==> [Cloudflare Build] Compiling Flutter Web Release..."
flutter build web --release

echo "==> [Cloudflare Build] Web build finished successfully in build/web!"
