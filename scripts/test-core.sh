#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
PLATFORM_FLAGS=()
if [[ "$(uname -s)" == Darwin ]]; then PLATFORM_FLAGS=(-framework Accelerate); fi
"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Wpedantic -pthread -I core/include \
  core/src/ComicCore.cpp tests/core_tests.cpp "${PLATFORM_FLAGS[@]}" -o .build/core-tests
.build/core-tests
