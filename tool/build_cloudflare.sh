#!/usr/bin/env bash
set -e

echo "==> [Cloudflare Build] Checking Flutter environment..."

if ! command -v flutter >/dev/null 2>&1; then
  FLUTTER_INSTALL_DIR="/tmp/flutter"
  if [ -x "$FLUTTER_INSTALL_DIR/bin/flutter" ]; then
    export PATH="$FLUTTER_INSTALL_DIR/bin:$PATH"
  elif [ -f "build/web/index.html" ]; then
    echo "==> [Cloudflare Build] Prebuilt build/web found. Proceeding with existing assets."
  else
    echo "==> [Cloudflare Build] Cloning Flutter stable (shallow depth 1)..."
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_INSTALL_DIR"
    export PATH="$FLUTTER_INSTALL_DIR/bin:$PATH"
    flutter config --no-analytics
  fi
fi

if command -v flutter >/dev/null 2>&1; then
  echo "==> [Cloudflare Build] Flutter version:"
  flutter --version
  echo "==> [Cloudflare Build] Getting packages..."
  flutter pub get
  echo "==> [Cloudflare Build] Compiling Flutter Web..."
  flutter build web --release
fi

if [ ! -f "build/web/index.html" ]; then
  echo "==> [Cloudflare Build] Error: build/web/index.html was not generated!"
  exit 1
fi

echo "==> [Cloudflare Build] Web build ready in build/web!"
