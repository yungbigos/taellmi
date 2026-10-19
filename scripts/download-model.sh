#!/usr/bin/env bash
# The one user-started network step (AGENTS.md rule 1): download a model listed in the seed config,
# verify every file against its pinned SHA-256, and mark it installed for the app.
#   scripts/download-model.sh parakeet-tdt-0.6b-v3
# Target folder: the sandboxed app's models folder, or $TAELLMI_MODELS_DIR.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL_ID="${1:?usage: scripts/download-model.sh <model-id>}"
SEEDS="Packages/TaellmiKit/Sources/Config/Resources/Seeds/models.json"
MODEL=$(jq -e --arg id "$MODEL_ID" '.[] | select(.id == $id)' "$SEEDS") || { echo "unknown model: $MODEL_ID"; exit 1; }
PROVIDER=$(jq -r .provider_id <<<"$MODEL")
[[ "$PROVIDER" == "huggingface" ]] || { echo "$MODEL_ID is not downloadable (provider: $PROVIDER)"; exit 1; }
REPO=$(jq -r .source_ref <<<"$MODEL")
REV=$(jq -r .revision <<<"$MODEL")

ROOT="${TAELLMI_MODELS_DIR:-$HOME/Library/Containers/app.taellmi/Data/Library/Application Support/taellmi/models}"
DEST="$ROOT/$MODEL_ID"
mkdir -p "$DEST"
rm -f "$DEST/.taellmi-verified"

TOTAL=$(jq '[.files[].bytes] | add' <<<"$MODEL")
echo "▸ $MODEL_ID from $REPO@${REV:0:8} ($((TOTAL / 1024 / 1024)) MB) → $DEST"

jq -c '.files[]' <<<"$MODEL" | while read -r file; do
  path=$(jq -r .path <<<"$file")
  sha=$(jq -r .sha256 <<<"$file")
  target="$DEST/$path"
  if [[ -f "$target" ]] && [[ "$(shasum -a 256 "$target" | cut -d' ' -f1)" == "$sha" ]]; then
    continue
  fi
  mkdir -p "$(dirname "$target")"
  echo "  ↓ $path"
  curl -fL --retry 3 --silent --show-error -o "$target.part" "https://huggingface.co/$REPO/resolve/$REV/$path"
  actual=$(shasum -a 256 "$target.part" | cut -d' ' -f1)
  if [[ "$actual" != "$sha" ]]; then
    rm -f "$target.part"
    echo "✘ checksum mismatch for $path (expected $sha, got $actual)"
    exit 1
  fi
  mv "$target.part" "$target"
done

printf '%s' "$REV" >"$DEST/.taellmi-verified"
echo "✔ $MODEL_ID verified and installed"
