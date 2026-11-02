#!/usr/bin/env bash
# PreToolUse/Bash: prevent Claude from setting git user.email or user.name
# to the session's userEmail or any @anthropic.com address.
#
# Claude Code exposes the user's Anthropic account email as context, and
# sometimes uses it for git config — that's almost never what you want.
# This hook blocks it and tells Claude to use the global git config instead.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# Only care about git config commands that set user.email or user.name.
printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])git[[:space:]]+config' || exit 0
printf '%s' "$cmd" | grep -Eq 'user\.(email|name)' || exit 0

# Allow reads (no value after the key) and unsets.
printf '%s' "$cmd" | grep -Eq '(--get|--unset)' && exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Block any @anthropic.com or noreply@anthropic address.
if printf '%s' "$cmd" | grep -Eiq '@anthropic\.com|noreply@anthropic'; then
  deny 'Blocked by the git-identity hook: do not use an @anthropic.com email for git config. The user'\''s git identity is already set in their global git config — do not override it.'
fi

# Block the session userEmail if it differs from the global git email.
# The session email is the Anthropic account email, not the git identity.
global_email=$(git config --global user.email 2>/dev/null || true)
if [ -n "$global_email" ]; then
  # Extract the email being set from the command.
  setting=$(printf '%s' "$cmd" | grep -oE 'user\.email[[:space:]]+["'"'"']?[^"'"'"'[:space:]]+' | head -1 | sed -E 's/user\.email[[:space:]]+["'"'"']?//')
  if [ -n "$setting" ] && [ "$setting" != "$global_email" ]; then
    deny "Blocked by the git-identity hook: you tried to set user.email to '$setting' but the user's global git email is '$global_email'. Do not override git identity — the global config is correct. Drop the git config command entirely."
  fi
fi

exit 0
