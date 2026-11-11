#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Building Flutter Web (release) for Smart TV..."
flutter build web --release --no-wasm-dry-run

# LG webOS (.ipk) and Samsung Tizen (.wgt) load index.html from a local package URL.
# Replacing <base href="/"> with <base href="./"> prevents asset/worker 404s.
sed -i.bak 's|<base href="/">|<base href="./">|g' build/web/index.html
rm -f build/web/index.html.bak

echo "==> Preparing Samsung Tizen .wgt package..."
rm -rf build/tizen_wgt
mkdir -p build/tizen_wgt
cp -R build/web/* build/tizen_wgt/
# Remove webOS-only metadata from Tizen bundle
rm -f build/tizen_wgt/appinfo.json build/tizen_wgt/largeIcon.png

if command -v tizen >/dev/null 2>&1; then
  tizen package -t wgt -o build -- build/tizen_wgt
  echo "==> Built signed/unsigned Tizen WGT in build/"
else
  (cd build/tizen_wgt && zip -rq ../YesXtream-tizen-unsigned.wgt .)
  echo "==> Created build/YesXtream-tizen-unsigned.wgt (sign with Tizen Studio / 'tizen package -t wgt' for TV install)"
fi

echo "==> Preparing LG webOS .ipk package..."
rm -rf build/webos_app
mkdir -p build/webos_app
cp -R build/web/* build/webos_app/
# Remove Tizen-only metadata from webOS bundle
rm -f build/webos_app/config.xml

if command -v ares-package >/dev/null 2>&1; then
  ares-package build/webos_app -o build/
  echo "==> Built LG webOS IPK in build/ via ares-package"
else
  echo "==> 'ares-package' not found; staged webOS bundle at build/webos_app/ (install @webosose/ares-cli to package .ipk)"
fi

