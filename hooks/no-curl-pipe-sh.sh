#!/usr/bin/env bash
# PreToolUse/Bash: block curl-pipe-to-shell patterns.
# Downloading and executing in one shot skips inspection. Claude should
# download first, let the user see it, then run it.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

if printf '%s' "$cmd" | grep -Eq '(curl|wget)[[:space:]].*\|[[:space:]]*(bash|sh|zsh|dash|source|\.)([[:space:]]|$)'; then
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Blocked by the no-curl-pipe-sh hook: do not pipe downloads directly into a shell. Download the script first, let the user inspect it, then run it as a separate step. Example: curl -fsSL <url> -o /tmp/script.sh && cat /tmp/script.sh"}}'
  exit 0
fi
exit 0
