#!/usr/bin/env bash
# PostToolUse recorder feeding the require-tests Stop hook.
# Appends "E <epoch> <path>" when code changes, "V <epoch>" when something
# that actually exercises the code runs. State is per session, pruned weekly.
set -uo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
session=$(printf '%s' "$input" | jq -r '.session_id // ""')
[ -n "$session" ] || exit 0

dir="$HOME/.claude/state"
mkdir -p "$dir" 2>/dev/null
f="$dir/verify-$session"
now=$(date +%s)

case "$tool" in
  Write|Edit|NotebookEdit)
    path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
    [ -n "$path" ] || exit 0
    # Only source changes create an obligation to verify.
    printf '%s' "$path" | grep -Eiq '\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|rb|php|java|kt|swift|c|h|cc|cpp|hpp|cs|sh|bash|zsh|sql|vue|svelte|ipynb)$' || exit 0
    # Config/hook edits under ~/.claude have no test suite to run.
    case "$path" in "$HOME"/.claude/*) exit 0 ;; esac
    printf 'E %s %s\n' "$now" "$path" >> "$f"
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
    VERIFY='(^|[;&|(]|[[:space:]])(npm|pnpm|yarn|bun|deno)[[:space:]]+(run[[:space:]]+)?(test|build|typecheck|type-check|lint|check|start|dev|e2e)|npx[[:space:]]+(tsx|ts-node|jest|vitest|tsc|eslint|playwright)|(^|[;&|(]|[[:space:]])(tsc|jest|vitest|pytest|mocha|rspec|phpunit|gotestsum)([[:space:]]|$)|(^|[;&|(]|[[:space:]])(go|cargo)[[:space:]]+(test|build|run|check)|(^|[;&|(]|[[:space:]])(make|mvn|gradle|\./gradlew|dotnet)([[:space:]]|$)|(^|[;&|(]|[[:space:]])(node|python3?|ruby|php|bun)[[:space:]]+[^[:space:]]+\.(js|ts|mjs|cjs|py|rb|php)|docker[[:space:]]+compose[[:space:]]+(up|run)|curl[[:space:]]+[^|]*(localhost|127\.0\.0\.1)|(^|[;&|(]|[[:space:]])(just|task|tox|bazel|nx|turbo|rake|air)([[:space:]]|$)|(^|[;&|(]|[[:space:]])deno[[:space:]]+task|(^|[;&|(]|[[:space:]])(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+[a-zA-Z]|(^|[;&|(]|[[:space:]])\./[^[:space:]]*\.sh|(^|[;&|(]|[[:space:]])(bash|sh|zsh)[[:space:]]+(-[a-z]+[[:space:]]+)*[^[:space:]]+\.(sh|bash|zsh)([[:space:]]|$)'
    printf '%s' "$cmd" | grep -Eq "$VERIFY" && printf 'V %s\n' "$now" >> "$f"
    ;;
esac
exit 0
