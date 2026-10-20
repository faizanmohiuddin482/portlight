#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64), ad-hoc signed build/Portlight.app.
# Each arch is built separately and merged with lipo, because SwiftPM's
# multi-arch flag needs full Xcode and we only require the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

BINS=()
for ARCH in arm64 x86_64; do
  TRIPLE="$ARCH-apple-macosx14.0"
  swift build -c release --triple "$TRIPLE"
  BINS+=("$(swift build -c release --triple "$TRIPLE" --show-bin-path)/Portlight")
done

APP=build/Portlight.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/Portlight"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
