#!/usr/bin/env bash
# Measures search quality with the real embedding model on three sets: the synthetic journal (eval/), and
# the German and English controls (scripts/download-eval-data.sh). Writes a Markdown report.
#   scripts/eval-search.sh [report.md]
# Needs: the embedding model (scripts/download-model.sh qwen3-embedding-0.6b-8bit, or TAELLMI_MODELS_DIR),
# the control sets, and Xcode's Metal Toolchain (for MLX's shaders).
set -euo pipefail
cd "$(dirname "$0")/.."

EVAL_DIR="${TAELLMI_EVAL_DIR:-$HOME/Library/Caches/taellmi-dev/eval}"
MODELS="${TAELLMI_MODELS_DIR:-$HOME/Library/Containers/app.taellmi/Data/Library/Application Support/taellmi/models}"
REPORT="${1:-$EVAL_DIR/report.md}"

[[ -f "$EVAL_DIR/germanquad/corpus.jsonl" ]] || scripts/download-eval-data.sh
python3 eval/synthetic-journal/build.py "$EVAL_DIR"

scripts/run-app.sh --build >/dev/null
METALLIB="$PWD/$(find build/Build/Products/Debug -path '*mlx-swift_Cmlx.bundle*' -name default.metallib | head -n 1)"

swift run --package-path Packages/TaellmiKit -c release SearchEvalTool \
  --models "$MODELS" --metallib "$METALLIB" --out "$REPORT" \
  --set "$EVAL_DIR/synthetic-journal" --set "$EVAL_DIR/germanquad:1000" --set "$EVAL_DIR/squad:1000"
