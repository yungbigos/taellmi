#!/usr/bin/env bash
# Generate the Xcode project, build the app, and launch it.
#   scripts/run-app.sh            build, install to ~/Applications, launch
#   scripts/run-app.sh --build    build only (unsigned; used by scripts/check.sh)
#   scripts/run-app.sh --demo     a separate "taellmi-demo" app with its own data and Keychain entry,
#                                 for trying things on test thoughts (scripts/make-demo-archive.sh)
#   scripts/run-app.sh --install  from a git worktree: install to ~/Applications anyway
# The installed copy is the one you open yourself (Spotlight: "tällmi", Launchpad, Finder).
# Run from a git worktree (parallel agent sessions), the build is launched from the worktree's own
# build/run/ folder instead, so it never replaces the installed copy. It still uses the same data.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_ONLY=false
DEMO=false
INSTALL=false
for arg in "$@"; do
  case "$arg" in
    --build) BUILD_ONLY=true ;;
    --demo) DEMO=true ;;
    --install) INSTALL=true ;;
    *) echo "✘ unknown option: $arg (use --build, --demo, --install)"; exit 1 ;;
  esac
done
# A linked worktree has its own git dir; the main checkout's git dir is the shared one.
WORKTREE=""
if [[ "$(git rev-parse --absolute-git-dir)" != "$(cd "$(git rev-parse --git-common-dir)" && pwd)" ]]; then
  WORKTREE="$(basename "$PWD")"
fi

xcodegen generate --quiet
NAME="taellmi"
BUILD="build"
IDENTITY=()
if $DEMO; then
  NAME="taellmi-demo"
  BUILD="build/demo"
  # Only the bundle id differs (PRODUCT_NAME would also rename the package's resource bundles).
  IDENTITY=(PRODUCT_BUNDLE_IDENTIFIER=app.taellmi.demo)
fi
LOG="$BUILD/xcodebuild.log"
SIGNING=()
# A build-only check (used by scripts/check.sh) just needs to compile; signing needs the keychain,
# which may not be able to ask for permission in the background.
$BUILD_ONLY && SIGNING=(CODE_SIGNING_ALLOWED=NO)
mkdir -p "$BUILD"
if ! xcodebuild -project Taellmi.xcodeproj -scheme Taellmi -configuration Debug -derivedDataPath "$BUILD" \
  -skipPackagePluginValidation ${SIGNING[@]+"${SIGNING[@]}"} ${IDENTITY[@]+"${IDENTITY[@]}"} build >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | head -40
  echo "✘ build failed (full log: $LOG)"
  exit 1
fi
echo "▸ build succeeded"
APP="$BUILD/Build/Products/Debug/taellmi.app"

if ! $BUILD_ONLY; then
  if [[ -n "$WORKTREE" ]] && ! $INSTALL; then
    TARGET="$PWD/$BUILD/run/$NAME.app"
  else
    TARGET="$HOME/Applications/$NAME.app"
  fi
  # Copies of the same app share one data folder, so only one may run: stop every copy of this app
  # (installed or from any worktree), but never the other app (the demo app is "taellmi-demo.app").
  RUNNING="/$NAME.app/Contents/MacOS/taellmi"
  pkill -f "$RUNNING" 2>/dev/null || true
  for _ in $(seq 1 50); do pgrep -f "$RUNNING" >/dev/null || break; sleep 0.1; done
  mkdir -p "$(dirname "$TARGET")"
  rm -rf "$TARGET"
  ditto "$APP" "$TARGET"
  # LaunchServices can still consider the old instance alive for a moment; retry briefly.
  for _ in $(seq 1 10); do open "$TARGET" 2>/dev/null && break; sleep 0.5; done
  pgrep -f "$TARGET/Contents/MacOS/taellmi" >/dev/null || { echo "✘ app did not launch"; exit 1; }
  echo "▸ launched $TARGET"
  if [[ -n "$WORKTREE" ]] && ! $INSTALL; then
    echo "▸ this is worktree \"$WORKTREE\"'s build; ~/Applications/$NAME.app was not changed (--install to replace it)"
  fi
fi
