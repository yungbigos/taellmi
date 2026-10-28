#!/usr/bin/env bash
# The single quality gate: format lint → network entitlements → build → fast tests.
# Used by the git pre-commit hook, the Claude Code Stop hook, GitHub Actions (check, release), and by hand.
#   scripts/check.sh         check only
#   scripts/check.sh --fix   auto-format first, then check
set -euo pipefail  # pipefail: a failing build/test fails the script even when piped through tail
cd "$(dirname "$0")/.."

PKG="Packages/TaellmiKit"
SRC_DIRS=()
for d in "$PKG" App; do [[ -d "$d" ]] && SRC_DIRS+=("$d"); done

if [[ "${1:-}" == "--fix" && ${#SRC_DIRS[@]} -gt 0 ]]; then
  swift format format --in-place --recursive --parallel "${SRC_DIRS[@]}"
fi

if [[ ${#SRC_DIRS[@]} -gt 0 ]]; then
  echo "▸ format lint"
  swift format lint --strict --recursive --parallel "${SRC_DIRS[@]}"
fi

echo "▸ network"
scripts/check-network.sh

if [[ -f "$PKG/Package.swift" ]]; then
  echo "▸ build"
  swift build --package-path "$PKG" 2>&1 | tail -n 40
  echo "▸ fast tests"
  # On failure, show the failing tests wherever they are in the output, not only its last lines.
  LOG="$(mktemp -t taellmi-tests)"
  if ! swift test --package-path "$PKG" --parallel --skip IntegrationTests >"$LOG" 2>&1; then
    grep -E -A4 "✘|error:" "$LOG" | head -n 120 || true
    echo "✘ fast tests failed (full output: $LOG)"
    exit 1
  fi
  tail -n 60 "$LOG"
else
  echo "▸ no package yet ($PKG) — lint only"
fi

if [[ -f project.yml ]]; then
  echo "▸ app build"
  scripts/run-app.sh --build
fi

echo "✔ check passed"
