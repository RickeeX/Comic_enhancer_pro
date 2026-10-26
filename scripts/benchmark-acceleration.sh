#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p .build
xcrun clang++ -std=c++17 -O3 -DNDEBUG -I core/include -c core/src/ComicCore.cpp -o .build/acceleration-core.o
xcrun swiftc -swift-version 5 -O -whole-module-optimization -parse-as-library -import-objc-header core/include/ComicCore.h \
  macos/PageItem.swift macos/PDFLoader.swift macos/Settings.swift macos/Recipe.swift macos/Processor.swift macos/GrayPlane.swift tests/MetalCandidate.swift macos/Pipeline.swift tests/macos_acceleration.swift .build/acceleration-core.o \
  -lc++ -framework AppKit -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -framework Metal -framework Accelerate -o .build/acceleration-benchmark
.build/acceleration-benchmark
