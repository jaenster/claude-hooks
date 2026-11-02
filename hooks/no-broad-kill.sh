#!/usr/bin/env bash
# PreToolUse/Bash: block overly broad process killing.
# pkill/killall without a specific target can nuke unrelated processes.
# Also block kill -9 on PIDs from loose greps.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Block bare pkill/killall with no arguments or overly broad patterns.
if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])(pkill|killall)([[:space:]]|$)'; then
  # Extract what comes after pkill/killall (the target pattern).
  target=$(printf '%s' "$cmd" | grep -oE '(pkill|killall)[[:space:]]+[^;&|]+' | head -1 | sed -E 's/^(pkill|killall)[[:space:]]*//')
  # Strip flags to find the actual pattern.
  pattern=$(printf '%s' "$target" | sed -E 's/[[:space:]]*-[a-zA-Z0-9]+[[:space:]]*//g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

  if [ -z "$pattern" ]; then
    deny 'Blocked by the no-broad-kill hook: pkill/killall with no target would kill everything matching. Specify the exact process name.'
  fi

  # Allow pkill -f "full command line" — that's specific enough.
  if printf '%s' "$target" | grep -Eq '(-f|--full)'; then
    exit 0
  fi

  # Bare process names like "node", "python", "ruby" kill every instance.
  # Use lsof/ps to find the specific PID instead.
  deny "Blocked by the no-broad-kill hook: 'pkill/killall $pattern' would kill ALL processes matching that name. Find the specific PID first: 'lsof -i :<port>' for servers, or 'ps aux | grep $pattern' to identify the right one, then 'kill <pid>'."
fi

# Block kill on $() subshells that grep broadly (kill $(pgrep ...) patterns).
if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])kill[[:space:]].*\$\((pgrep|pidof)'; then
  deny "Blocked by the no-broad-kill hook: kill with a pgrep/pidof subshell is fragile — it can catch unrelated processes. Find the specific PID first with 'lsof -i :<port>' or 'ps aux | grep <name>', verify it, then kill that PID."
fi

exit 0
