#!/usr/bin/env bash
# PreToolUse/Bash: block sudo. Claude reaches for it on permission errors,
# but in a dev context it's almost never the right fix.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])sudo([[:space:]]|$)'; then
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Blocked by the no-sudo hook: do not use sudo. If you hit a permission error, figure out why — wrong directory, missing user-level install, needs a venv, or the user should run it themselves. If sudo is genuinely needed, say so and let the user decide."}}'
  exit 0
fi
exit 0
