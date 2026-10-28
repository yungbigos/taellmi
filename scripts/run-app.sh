#!/usr/bin/env bash
# Generate the Xcode project, build the app, and launch it.
#   scripts/run-app.sh            build, install to ~/Applications, launch
#   scripts/run-app.sh --build    build only (unsigned; used by scripts/check.sh)
#   scripts/run-app.sh --demo     a separate "taellmi-demo" app with its own data and Keychain entry,
#                                 for trying things on test thoughts (scripts/make-demo-archive.sh)
#   scripts/run-app.sh --install  from a git worktree: install to ~/Applications anyway
#   scripts/run-app.sh --fresh    a brand-new tällmi, as a new user gets it: each run is a new app identity
#                                 ("app.taellmi.fresh.<time>"), so macOS gives it an empty data folder, no
#                                 Keychain entry and no permissions yet. Other copies are stopped first, since
#                                 they would hold the same shortcut. Never installed; see --clean-fresh.
#   scripts/run-app.sh --fresh --finder  the same, shown in Finder instead of launched: double-click it, as a new
#                                 user does (only a launch you start yourself gets the focus from macOS)
#   scripts/run-app.sh --clean-fresh  stop and remove every --fresh copy: its data folders and Keychain entries
# The installed copy is the one you open yourself (Spotlight: "tällmi", Launchpad, Finder).
# Run from a git worktree (parallel agent sessions), the build is launched from the worktree's own
# build/run/ folder instead, so it never replaces the installed copy. It still uses the same data.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_ONLY=false
DEMO=false
INSTALL=false
FRESH=false
FINDER=false
for arg in "$@"; do
  case "$arg" in
    --build) BUILD_ONLY=true ;;
    --demo) DEMO=true ;;
    --install) INSTALL=true ;;
    --fresh) FRESH=true ;;
    --finder) FINDER=true ;;
    --clean-fresh)
      pkill -f "/taellmi-fresh.app/Contents/MacOS/taellmi" 2>/dev/null || true
      for container in "$HOME"/Library/Containers/app.taellmi.fresh.*; do
        [[ -e "$container" ]] || continue
        id="$(basename "$container")"
        for account in archive-key pending-recovery-key recovery-key; do
          security delete-generic-password -s "$id.archive" -a "$account" >/dev/null 2>&1 || true
        done
        tccutil reset All "$id" >/dev/null 2>&1 || true
        # macOS guards other apps' data: this needs a terminal that may change it (Full Disk Access).
        rm -rf "$container" 2>/dev/null || echo "✘ couldn't remove $container (give your terminal Full Disk Access, or move it to the Trash in Finder)"
      done
      rm -rf build/fresh/run
      echo "▸ removed the --fresh copies"
      exit 0 ;;
    *) echo "✘ unknown option: $arg (use --build, --demo, --install, --fresh, --finder, --clean-fresh)"; exit 1 ;;
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
  IDENTITY=(TAELLMI_APP_ID=app.taellmi.demo)
elif $FRESH; then
  NAME="taellmi-fresh"
  BUILD="build/fresh"
  # A new identity each run: a new sandbox container, Keychain entry and set of permissions.
  FRESH_ID="app.taellmi.fresh.t$(date +%Y%m%d%H%M%S)"
  IDENTITY=(TAELLMI_APP_ID="$FRESH_ID")
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
  if $FRESH; then
    # A new user has no other tällmi running; another copy would also take the global shortcuts.
    for other in "/taellmi.app/" "/taellmi-demo.app/" "/taellmi-fresh.app/"; do
      if pgrep -f "${other}Contents/MacOS/taellmi" >/dev/null; then
        pkill -f "${other}Contents/MacOS/taellmi" || true
        echo "▸ stopped the running ${other//\//} so its shortcuts don't interfere"
      fi
    done
  fi
  if $FRESH || { [[ -n "$WORKTREE" ]] && ! $INSTALL; }; then
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
  if $FINDER; then
    open -R "$TARGET"
    echo "▸ built $TARGET as ${FRESH_ID:-its usual identity}; it's selected in Finder: double-click it"
    exit 0
  fi
  # LaunchServices can still consider the old instance alive for a moment; retry briefly.
  for _ in $(seq 1 10); do open "$TARGET" 2>/dev/null && break; sleep 0.5; done
  pgrep -f "$TARGET/Contents/MacOS/taellmi" >/dev/null || { echo "✘ app did not launch"; exit 1; }
  echo "▸ launched $TARGET"
  $FRESH && echo "▸ as $FRESH_ID: a new user's first launch (remove old ones with --clean-fresh)"
  if [[ -n "$WORKTREE" ]] && ! $INSTALL && ! $FRESH; then
    echo "▸ this is worktree \"$WORKTREE\"'s build; ~/Applications/$NAME.app was not changed (--install to replace it)"
  fi
fi
