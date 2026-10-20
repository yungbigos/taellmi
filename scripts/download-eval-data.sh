#!/usr/bin/env bash
# Developer step: download the two public control sets for evaluating search (German GermanQuAD, English SQuAD),
# verify each file's SHA-256, and convert them for scripts/eval-search.sh. Not part of the app; the app never
# downloads these. Target: $TAELLMI_EVAL_DIR or ~/Library/Caches/taellmi-dev/eval.
set -euo pipefail
cd "$(dirname "$0")/.."

EVAL_DIR="${TAELLMI_EVAL_DIR:-$HOME/Library/Caches/taellmi-dev/eval}"
RAW="$EVAL_DIR/raw"
mkdir -p "$RAW"

# name  repo@revision:file  bytes  sha256
FILES=(
  "germanquad-corpus.arrow mteb/germanquad-retrieval@9af36714ebd9bba5235c4b9862779adaddbfae52:corpus/data-00000-of-00001.arrow 944328 396449efe7478e7a8edc480fd85ccee4b20002ea609f519fcd8cd62add042b45"
  "germanquad-queries.arrow mteb/germanquad-retrieval@9af36714ebd9bba5235c4b9862779adaddbfae52:queries/data-00000-of-00001.arrow 158704 4bdea8268da0cbc32c031a1c6ea078fcac435c6bef3c68c7b4367498c19ea5e9"
  "germanquad-qrels.arrow mteb/germanquad-retrieval-qrels@ed232776ce5d736028c1da18e81ab7048969f369:test/data-00000-of-00001.arrow 54296 4c119a8339e58ebb6382e3df45279086bd1f44504b9edab2bf0a933f7de5b55c"
  "squad-validation.parquet rajpurkar/squad@7b6d24c440a36b6815f21b70d25016731768db1f:plain_text/validation-00000-of-00001.parquet 1819889 8c6646d36bd5a95061e076788cf3161d11f6f3e7d625dac7a83bbed0a49f69f7"
)

for row in "${FILES[@]}"; do
  read -r name source _bytes sha <<<"$row"
  repo=${source%@*}; rest=${source#*@}; rev=${rest%%:*}; file=${rest#*:}
  target="$RAW/$name"
  if [[ -f "$target" ]] && [[ "$(shasum -a 256 "$target" | cut -d' ' -f1)" == "$sha" ]]; then continue; fi
  echo "  ↓ $repo/$file"
  curl -fL --retry 3 --silent --show-error -o "$target.part" "https://huggingface.co/datasets/$repo/resolve/$rev/$file"
  [[ "$(shasum -a 256 "$target.part" | cut -d' ' -f1)" == "$sha" ]] || { rm -f "$target.part"; echo "✘ checksum mismatch: $name"; exit 1; }
  mv "$target.part" "$target"
done

# A private Python environment just for reading Arrow/Parquet.
VENV="$EVAL_DIR/.venv"
[[ -x "$VENV/bin/python" ]] || python3 -m venv "$VENV"
"$VENV/bin/python" -c "import pyarrow" 2>/dev/null || "$VENV/bin/pip" install --quiet "pyarrow==22.0.0"
"$VENV/bin/python" eval/convert_controls.py "$RAW" "$EVAL_DIR"
echo "✔ control sets ready in $EVAL_DIR (GermanQuAD CC BY 4.0, SQuAD CC BY-SA 4.0)"
