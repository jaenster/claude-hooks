#!/usr/bin/env bash
# PreToolUse/Bash: block bypassing commit signing.
# If the user has gpgsign=true, Claude should not disable it.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Block -c commit.gpgsign=false
if printf '%s' "$cmd" | grep -Eiq 'commit\.gpgsign[[:space:]]*=[[:space:]]*false'; then
  deny 'Blocked by the no-gpgsign-bypass hook: do not disable commit signing. The user has gpgsign=true for a reason. Just run git commit without overriding it — the signing key is configured.'
fi

# Block --no-gpg-sign
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])--no-gpg-sign([[:space:]]|$)'; then
  deny 'Blocked by the no-gpgsign-bypass hook: do not use --no-gpg-sign. The user has commit signing enabled globally. Drop the flag and commit normally.'
fi

exit 0
