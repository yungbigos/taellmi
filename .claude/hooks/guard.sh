#!/usr/bin/env bash
# PreToolUse (Edit|Write): block edits that break project rules. Exit 2 = block, stderr goes back to Claude.
INPUT=$(cat)
FILE=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")
NEW=$(jq -r '[.tool_input.content, .tool_input.new_string] | map(select(. != null)) | join("\n")' <<<"$INPUT")

case "$FILE" in
  *.pbxproj)
    echo "Blocked: the Xcode project is generated. Edit project.yml (XcodeGen) or Package.swift instead." >&2
    exit 2 ;;
  *.entitlements)
    if grep -q 'com.apple.security.network.client' <<<"$NEW"; then
      echo "Blocked: outgoing network breaks the local-only principle (AGENTS.md rule 1). Ask the owner first." >&2
      exit 2
    fi ;;
esac
exit 0
