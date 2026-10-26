#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p .build/native-baseline
# Keep v0.4.2 intact, including its old thread scheduler and Swift bitmap path.
git fetch --depth=1 origin tag v0.4.2
git archive v0.4.2 core macos | tar -x -C .build/native-baseline
for variant in before after; do
  if [[ "$variant" == before ]]; then source_root="$PWD/.build/native-baseline"; else source_root="$PWD"; fi
  xcrun clang++ -std=c++17 -O3 -DNDEBUG -I "$source_root/core/include" -c "$source_root/core/src/ComicCore.cpp" -o ".build/native-$variant.o"
  source_files=("$source_root/macos/PageItem.swift" "$source_root/macos/PDFLoader.swift" "$source_root/macos/Settings.swift" "$source_root/macos/Recipe.swift" "$source_root/macos/Processor.swift")
  if [[ "$variant" == after ]]; then source_files+=("$source_root/macos/GrayPlane.swift"); fi
  source_files+=("$source_root/macos/Pipeline.swift")
  xcrun swiftc -swift-version 5 -O -whole-module-optimization -parse-as-library -import-objc-header "$source_root/core/include/ComicCore.h" \
    "${source_files[@]}" tests/native_pipeline_benchmark.swift ".build/native-$variant.o" -lc++ \
    -framework AppKit -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -framework Accelerate -o ".build/native-$variant"
  ".build/native-$variant" | tee ".build/native-$variant-comparison.log"
done
