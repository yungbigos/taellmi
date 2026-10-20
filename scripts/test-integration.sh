#!/usr/bin/env bash
# Slow tests against real models. Needs the models downloaded (scripts/download-model.sh).
#   scripts/test-integration.sh              all integration suites
#   scripts/test-integration.sh FluidAudio   only matching suites
set -euo pipefail
cd "$(dirname "$0")/.."

# `swift test` cannot compile MLX's Metal shaders; the Xcode app build does. Build it and point the MLX
# tests at its shaders (needs Xcode's Metal Toolchain: xcodebuild -downloadComponent MetalToolchain).
scripts/run-app.sh --build >/dev/null
METALLIB=$(find build/Build/Products/Debug -path '*mlx-swift_Cmlx.bundle*' -name default.metallib | head -n 1)
[[ -n "$METALLIB" ]] && export TAELLMI_MLX_METALLIB="$PWD/$METALLIB"

swift test --package-path Packages/TaellmiKit --filter "${1:-}.*IntegrationTests" 2>&1 | tail -n 40
