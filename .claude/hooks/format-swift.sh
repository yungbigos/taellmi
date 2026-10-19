#!/usr/bin/env bash
# PostToolUse: format any Swift file Claude just edited.
FILE=$(jq -r '.tool_input.file_path // empty')
[[ "$FILE" == *.swift && -f "$FILE" ]] || exit 0
swift format format --in-place "$FILE" 2>/dev/null || true
exit 0
