#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p .build
CXX_FLAGS=(-O2)
SWIFT_FLAGS=(-O -g)
if [[ "${COMIC_SANITIZE:-0}" == 1 ]]; then
  CXX_FLAGS=(-O1 -g -fsanitize=address -fno-omit-frame-pointer)
  SWIFT_FLAGS=(-O -g -sanitize=address)
fi
xcrun clang++ -std=c++17 "${CXX_FLAGS[@]}" -I core/include -c core/src/ComicCore.cpp -o .build/integration-core.o
xcrun swiftc -swift-version 5 "${SWIFT_FLAGS[@]}" -parse-as-library -import-objc-header core/include/ComicCore.h \
  macos/PageItem.swift macos/PDFLoader.swift macos/Settings.swift macos/Recipe.swift macos/Processor.swift macos/GrayPlane.swift macos/Pipeline.swift macos/BatchExporter.swift macos/Model.swift macos/PreviewCanvas.swift tests/macos_integration.swift .build/integration-core.o \
  -lc++ -framework SwiftUI -framework AppKit -framework Accelerate -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -o .build/macos-tests
.build/macos-tests
