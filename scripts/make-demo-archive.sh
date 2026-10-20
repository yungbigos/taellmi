#!/usr/bin/env bash
# Build an encrypted demo Archive from test thoughts, for the separate demo app (scripts/run-app.sh --demo).
#   scripts/make-demo-archive.sh <output-folder> <thoughts.jsonl>...
# Then in the demo app: Settings → privacy → change folder → pick <output-folder>, and enter the printed
# demo recovery key after the restart. Your real Archive is never touched.
set -euo pipefail
mkdir -p "$1"
ARGS=()
for path in "$@"; do ARGS+=("$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"); done
cd "$(dirname "$0")/../Packages/TaellmiKit"
swift run --quiet DemoArchiveTool "${ARGS[@]}"
