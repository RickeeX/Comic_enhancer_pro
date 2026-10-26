#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p .build
xcrun clang++ -std=c++17 -O2 -I core/include -c core/src/ComicCore.cpp -o .build/integration-core.o
xcrun swiftc -swift-version 5 -O -parse-as-library -import-objc-header core/include/ComicCore.h \
  macos/PageItem.swift macos/PDFLoader.swift macos/Settings.swift macos/Recipe.swift macos/Processor.swift macos/Pipeline.swift macos/Model.swift macos/PreviewCanvas.swift tests/macos_integration.swift .build/integration-core.o \
  -lc++ -framework SwiftUI -framework AppKit -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -o .build/macos-tests
.build/macos-tests
