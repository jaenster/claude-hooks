#!/usr/bin/env bash
# PreToolUse/Bash: this machine uses pnpm. npm is never the right call.
# npx is left alone - it is a separate launcher, not a package manager, and
# still the portable way to run a one-off binary.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# Ignore heredoc bodies and anything after a comment marker.
scan=$(printf '%s\n' "$cmd" | awk '{ if (index($0,"<<")>0) { sub(/<<.*/,""); print; exit } print }')

if printf '%s' "$scan" | grep -Eq '(^|[;&|(]|[[:space:]])npm([[:space:]]|$)'; then
  sub=$(printf '%s' "$scan" | grep -oE '(^|[;&|(]|[[:space:]])npm[[:space:]]+[a-z-]+' | head -1 | awk '{print $2}')
  # Bare "npm install" installs the whole tree; with a package it adds one.
  rest=$(printf '%s' "$scan" | grep -oE '(^|[;&|(]|[[:space:]])npm[[:space:]]+[a-z-]+([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]][^[:space:]]*' | head -1)
  case "$sub" in
    install|i|add)   if [ -n "$rest" ]; then alt="pnpm add"; else alt="pnpm install"; fi ;;
    ci)              alt="pnpm install --frozen-lockfile" ;;
    run)             alt="pnpm run" ;;
    test)            alt="pnpm test" ;;
    uninstall|rm|remove) alt="pnpm remove" ;;
    exec)            alt="pnpm exec" ;;
    "")              alt="pnpm" ;;
    *)               alt="pnpm $sub" ;;
  esac
  jq -n --arg a "$alt" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("Blocked by the pnpm-only hook: this machine uses pnpm, never npm. Use `" + $a + "` instead. (npx is still fine for one-off binaries.) If a package-lock.json is what forced npm here, say so - the fix is to migrate the lockfile, not to shell out to npm.")}}'
  exit 0
fi
exit 0
