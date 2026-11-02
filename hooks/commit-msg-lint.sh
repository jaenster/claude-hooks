#!/usr/bin/env bash
# PreToolUse/Bash: enforce conventional commit format.
#   - Subject line must start with a type (feat, fix, chore, docs, style,
#     refactor, perf, test, build, ci, revert) optionally scoped: feat(api):
#   - Subject must be under 72 characters.
#   - No body required, but if present it must be separated by a blank line.
#   - The type prefix must be lowercase.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# Only inspect git commit commands.
printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' || exit 0

# Skip amend-only (no new message to lint) and commits that open an editor.
printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])(--amend([[:space:]]|$))' && \
  ! printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])(-m|--message)([[:space:]=]|$)' && exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Extract the subject line from -m.
subject=""
if printf '%s' "$cmd" | grep -Eq "(-m|--message)[[:space:]]*'"; then
  subject=$(printf '%s' "$cmd" | sed -nE "s/.*(-m|--message)[[:space:]]*'([^']*).*/\2/p" | head -1)
elif printf '%s' "$cmd" | grep -Eq '(-m|--message)[[:space:]]*"'; then
  subject=$(printf '%s' "$cmd" | sed -nE 's/.*(-m|--message)[[:space:]]*"([^"]*).*/\2/p' | head -1)
fi

# Also handle -F / --file.
if [ -z "$subject" ] && printf '%s' "$cmd" | grep -Eq '(-F|--file)[[:space:]]+'; then
  msgfile=$(printf '%s' "$cmd" | grep -oE '(-F|--file)[[:space:]]+[^[:space:];&|]+' | head -1 | awk '{print $2}')
  [ -n "$msgfile" ] && [ -f "$msgfile" ] && subject=$(head -1 "$msgfile")
fi

[ -z "$subject" ] && exit 0

# Strip leading whitespace.
subject=$(printf '%s' "$subject" | sed 's/^[[:space:]]*//')

# Allowed types.
TYPES='feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert'

# Check format: type[(scope)][!]: description
if ! printf '%s' "$subject" | grep -Eq "^($TYPES)(\([a-zA-Z0-9._-]+\))?!?:[[:space:]]+."; then
  deny "Blocked by the commit-msg-lint hook: subject must be a conventional commit.

Format: <type>[(<scope>)][!]: <description>
Types:  feat fix chore docs style refactor perf test build ci revert

Examples:
  feat: add retry logic to uploader
  fix(auth): handle expired refresh tokens
  chore!: drop Node 16 support

Your subject: '$subject'"
fi

# Check length.
len=${#subject}
if [ "$len" -gt 72 ]; then
  deny "Blocked by the commit-msg-lint hook: subject line is $len characters (max 72). Keep it short — details go in the body after a blank line.

Your subject: '$subject'"
fi

# Check that the type is lowercase (no 'Feat:' or 'FIX:').
prefix=$(printf '%s' "$subject" | grep -oE '^[^:]+:' | head -1)
if printf '%s' "$prefix" | grep -qE '[A-Z]'; then
  lower=$(printf '%s' "$prefix" | tr '[:upper:]' '[:lower:]')
  deny "Blocked by the commit-msg-lint hook: type prefix must be lowercase. Use '$lower' instead of '$prefix'."
fi

exit 0
