#!/usr/bin/env bash
# Generate the Xcode project, build the app, and launch it.
#   scripts/run-app.sh            build + launch
#   scripts/run-app.sh --build    build only
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
LOG="build/xcodebuild.log"
SIGNING=()
# A build-only check (used by scripts/check.sh) just needs to compile; signing needs the keychain,
# which may not be able to ask for permission in the background.
[[ "${1:-}" == "--build" ]] && SIGNING=(CODE_SIGNING_ALLOWED=NO)
mkdir -p build
if ! xcodebuild -project Taellmi.xcodeproj -scheme Taellmi -configuration Debug -derivedDataPath build \
  -skipPackagePluginValidation "${SIGNING[@]}" build >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | head -40
  echo "✘ build failed (full log: $LOG)"
  exit 1
fi
echo "▸ build succeeded"
APP="build/Build/Products/Debug/taellmi.app"

if [[ "${1:-}" != "--build" ]]; then
  pkill -x taellmi 2>/dev/null || true
  for _ in $(seq 1 50); do pgrep -x taellmi >/dev/null || break; sleep 0.1; done
  # LaunchServices can still consider the old instance alive for a moment; retry briefly.
  for _ in $(seq 1 10); do open "$APP" 2>/dev/null && break; sleep 0.5; done
  pgrep -x taellmi >/dev/null || { echo "✘ app did not launch"; exit 1; }
  echo "▸ launched $APP"
fi
