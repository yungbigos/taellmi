#!/usr/bin/env bash
# AGENTS.md rule 1 and ADR 0016: tällmi itself never goes online; only its downloader may, with exactly two
# entitlements (app-sandbox, network.client) and only to the hosts it lists. Anything else fails.
#   scripts/check-network.sh                  the entitlement files in the repo (scripts/check.sh)
#   scripts/check-network.sh --app <.app>     a built, signed app: every program inside it (release)
#   scripts/check-network.sh --app <.app> --debug   the same for a debug build, which also may be debugged
set -euo pipefail
cd "$(dirname "$0")/.."

NETWORK="com.apple.security.network.client"
SANDBOX="com.apple.security.app-sandbox"
DOWNLOADER_KEYS='["com.apple.security.app-sandbox","com.apple.security.network.client"]'
HOSTS='["hf.co","huggingface.co"]'
fail() { echo "✘ $*"; exit 1; }

# The keys set to true in an entitlements or Info plist, as sorted JSON.
true_keys() { plutil -convert json -o - -- "$1" | jq -c '[to_entries[] | select(.value == true) | .key] | sort'; }
hosts() { plutil -extract TaellmiAllowedHosts json -o - -- "$1" 2>/dev/null | jq -c 'sort' || echo "none"; }

if [[ "${1:-}" != "--app" ]]; then
  DOWNLOADER="App/Downloader/Downloader.entitlements"
  while IFS= read -r file; do
    [[ "$file" == "$DOWNLOADER" ]] && continue
    if plutil -convert json -o - -- "$file" | jq -e --arg k "$NETWORK" 'has($k)' >/dev/null; then
      fail "$file asks for $NETWORK; only the downloader may (ADR 0016)"
    fi
  done < <(git ls-files '*.entitlements')
  [[ "$(true_keys App/taellmi.entitlements | jq -r --arg k "$SANDBOX" 'index($k) != null')" == true ]] \
    || fail "the app is not sandboxed"
  [[ "$(true_keys "$DOWNLOADER")" == "$DOWNLOADER_KEYS" ]] \
    || fail "$DOWNLOADER must have exactly $DOWNLOADER_KEYS"
  [[ "$(plutil -convert json -o - -- "$DOWNLOADER" | jq -c 'keys')" == "$DOWNLOADER_KEYS" ]] \
    || fail "$DOWNLOADER has entitlements besides $DOWNLOADER_KEYS"
  [[ "$(hosts App/Downloader/Info.plist)" == "$HOSTS" ]] || fail "the downloader may only reach $HOSTS"
  echo "✔ network: only the downloader may go online, to $HOSTS"
  exit 0
fi

APP="${2:?usage: scripts/check-network.sh --app <path to .app> [--debug]}"
DEBUG=false
[[ "${3:-}" == "--debug" ]] && DEBUG=true
SERVICE="Contents/XPCServices/taellmi-downloader.xpc"
ENTITLED="$SERVICE/Contents/MacOS/taellmi-downloader"

entitlements() { codesign -d --entitlements - --xml "$1" 2>/dev/null || true; }

# Every program in the bundle must be sandboxed: a program without the sandbox needs no entitlement to go online.
# Of them, only the downloader may have the network entitlement.
online=()
while IFS= read -r -d '' file; do
  file -b "$file" | grep -q "Mach-O.*executable" || continue
  plist="$(mktemp)"
  entitlements "$file" >"$plist"
  [[ -s "$plist" && "$(true_keys "$plist" | jq -r --arg k "$SANDBOX" 'index($k) != null')" == true ]] \
    || fail "${file#"$APP"/} is not sandboxed"
  if plutil -convert json -o - -- "$plist" | jq -e --arg k "$NETWORK" 'has($k)' >/dev/null; then
    online+=("${file#"$APP"/}")
  fi
  rm -f "$plist"
done < <(find "$APP" -type f -print0)
[[ "${online[*]:-}" == "$ENTITLED" ]] || fail "programs that may go online: ${online[*]:-none} (only $ENTITLED may)"

# The downloader: exactly its two entitlements, both on.
SERVICE_ENTITLEMENTS="$(mktemp)"
entitlements "$APP/$SERVICE" >"$SERVICE_ENTITLEMENTS"
KEYS="$(plutil -convert json -o - -- "$SERVICE_ENTITLEMENTS" | jq -c 'keys')"
# A debug build may also be attached to by the debugger (get-task-allow); a release may not.
$DEBUG && KEYS="$(jq -c 'map(select(. != "com.apple.security.get-task-allow"))' <<<"$KEYS")"
[[ "$KEYS" == "$DOWNLOADER_KEYS" ]] || fail "the downloader's entitlements are $KEYS, not $DOWNLOADER_KEYS"
ON="$(true_keys "$SERVICE_ENTITLEMENTS")"
$DEBUG && ON="$(jq -c 'map(select(. != "com.apple.security.get-task-allow"))' <<<"$ON")"
[[ "$ON" == "$DOWNLOADER_KEYS" ]] || fail "the downloader's entitlements that are on: $ON, not $DOWNLOADER_KEYS"
[[ "$(hosts "$APP/$SERVICE/Contents/Info.plist")" == "$HOSTS" ]] || fail "the downloader may only reach $HOSTS"
rm -f "$SERVICE_ENTITLEMENTS"
echo "✔ network: only $ENTITLED may go online, to $HOSTS"
