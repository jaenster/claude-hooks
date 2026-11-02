#!/usr/bin/env bash
# PreToolUse/Write|Edit: enforce the user's strict table rules in prose files.
#   - no box-drawing / ASCII-art tables, ever
#   - markdown table separators must be minimal (|-|-|), not padded (|---|---|)
# Scoped to prose files so TUI source that legitimately draws boxes is untouched.
set -uo pipefail

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
printf '%s' "$path" | grep -Eiq '\.(md|markdown|mdx|txt|rst)$' || exit 0

content=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // ""')
# Fenced blocks quote someone else's output or demonstrate syntax; they are not
# tables this document is authoring.
content=$(printf '%s\n' "$content" | awk '/^[[:space:]]*```/{f=!f; next} !f')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

if printf '%s' "$content" | grep -q '[┌┬┐└┴┘├┼┤╔╦╗╚╩╝╠╬╣═║│─]'; then
  deny 'Blocked by the md-style hook: box-drawing characters are banned everywhere, with no exceptions - not for clarity, not for alignment, not for terminal output. Use a normal markdown table with minimum separators (|-|-|), or a plain list.'
fi

if printf '%s' "$content" | grep -Eq '\|[[:space:]]*:?-{2,}:?[[:space:]]*\|'; then
  deny 'Blocked by the md-style hook: markdown table separators must be minimal. Write |-|-| , never |---|---| . Collapse the runs of hyphens to a single hyphen per column.'
fi

exit 0
