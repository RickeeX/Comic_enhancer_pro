#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This script requires macOS 13+ and Xcode Command Line Tools.' >&2; exit 1
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD="$PWD/.build"
APP="$BUILD/Comic Enhancer.app"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
  TARGET="$ARCH-apple-macos13.0"
  xcrun clang++ -std=c++17 -O3 -DNDEBUG -target "$TARGET" -isysroot "$SDK" \
    -I core/include -c core/src/ComicCore.cpp -o "$BUILD/core-$ARCH.o"
  xcrun swiftc -swift-version 5 -O -whole-module-optimization -parse-as-library \
    -target "$TARGET" -sdk "$SDK" -import-objc-header core/include/ComicCore.h \
    macos/Settings.swift macos/Processor.swift macos/Model.swift macos/App.swift \
    "$BUILD/core-$ARCH.o" -lc++ -framework SwiftUI -framework AppKit \
    -framework ImageIO -framework UniformTypeIdentifiers -o "$BUILD/ComicEnhancer-$ARCH"
done
xcrun lipo -create "$BUILD/ComicEnhancer-arm64" "$BUILD/ComicEnhancer-x86_64" -output "$APP/Contents/MacOS/ComicEnhancer"
cp macos/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
xcrun lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/ComicEnhancer"
echo "Built: $APP"
