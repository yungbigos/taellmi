#!/usr/bin/env bash
# Generate the Xcode project, build the app, and launch it.
#   scripts/run-app.sh            build, install to ~/Applications, launch
#   scripts/run-app.sh --build    build only (unsigned; used by scripts/check.sh)
#   scripts/run-app.sh --demo     a separate "taellmi-demo" app with its own data and Keychain entry,
#                                 for trying things on test thoughts (scripts/make-demo-archive.sh)
# The installed copy is the one you open yourself (Spotlight: "tällmi", Launchpad, Finder).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
NAME="taellmi"
BUILD="build"
IDENTITY=()
if [[ "${1:-}" == "--demo" ]]; then
  NAME="taellmi-demo"
  BUILD="build/demo"
  # Only the bundle id differs (PRODUCT_NAME would also rename the package's resource bundles).
  IDENTITY=(PRODUCT_BUNDLE_IDENTIFIER=app.taellmi.demo)
fi
LOG="$BUILD/xcodebuild.log"
SIGNING=()
# A build-only check (used by scripts/check.sh) just needs to compile; signing needs the keychain,
# which may not be able to ask for permission in the background.
[[ "${1:-}" == "--build" ]] && SIGNING=(CODE_SIGNING_ALLOWED=NO)
mkdir -p "$BUILD"
if ! xcodebuild -project Taellmi.xcodeproj -scheme Taellmi -configuration Debug -derivedDataPath "$BUILD" \
  -skipPackagePluginValidation ${SIGNING[@]+"${SIGNING[@]}"} ${IDENTITY[@]+"${IDENTITY[@]}"} build >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | head -40
  echo "✘ build failed (full log: $LOG)"
  exit 1
fi
echo "▸ build succeeded"
APP="$BUILD/Build/Products/Debug/taellmi.app"

if [[ "${1:-}" != "--build" ]]; then
  INSTALLED="$HOME/Applications/$NAME.app"
  # Both apps run as "taellmi"; match on the installed path so one never stops the other.
  RUNNING="$INSTALLED/Contents/MacOS/taellmi"
  pkill -f "$RUNNING" 2>/dev/null || true
  for _ in $(seq 1 50); do pgrep -f "$RUNNING" >/dev/null || break; sleep 0.1; done
  mkdir -p "$HOME/Applications"
  rm -rf "$INSTALLED"
  ditto "$APP" "$INSTALLED"
  APP="$INSTALLED"
  # LaunchServices can still consider the old instance alive for a moment; retry briefly.
  for _ in $(seq 1 10); do open "$APP" 2>/dev/null && break; sleep 0.5; done
  pgrep -f "$RUNNING" >/dev/null || { echo "✘ app did not launch"; exit 1; }
  echo "▸ launched $APP"
fi
