#!/usr/bin/env bash
# Slow tests against real models. Needs the models downloaded (scripts/download-model.sh).
#   scripts/test-integration.sh              all integration suites
#   scripts/test-integration.sh FluidAudio   only matching suites
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --package-path Packages/TaellmiKit --filter "${1:-}.*IntegrationTests" 2>&1 | tail -n 40
