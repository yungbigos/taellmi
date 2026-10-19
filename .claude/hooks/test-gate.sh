#!/usr/bin/env bash
# Stop: if code changed since the last passing run, run scripts/check.sh and refuse to finish while it fails.
cd "$CLAUDE_PROJECT_DIR" || exit 0
cat >/dev/null  # discard hook input

CHANGED=$( { git diff --name-only HEAD 2>/dev/null || git diff --name-only; git diff --cached --name-only; git ls-files -o --exclude-standard; } \
  | sort -u | grep -E '\.(swift)$|Package\.swift$|project\.yml$|Seeds/.*\.json$|\.swift-format$' || true)
[[ -z "$CHANGED" ]] && exit 0

STAMP_DIR=".build"; mkdir -p "$STAMP_DIR"
STAMP="$STAMP_DIR/.check-passed"
HASH=$(while read -r f; do [[ -f "$f" ]] && shasum "$f"; echo "$f"; done <<<"$CHANGED" | shasum | cut -d' ' -f1)
[[ -f "$STAMP" && "$(cat "$STAMP")" == "$HASH" ]] && exit 0

if OUT=$(scripts/check.sh --fix 2>&1); then
  echo "$HASH" >"$STAMP"
  exit 0
fi
{
  echo "scripts/check.sh failed. Fix it before finishing (do not weaken tests):"
  echo "$OUT" | tail -n 60
} >&2
exit 2
