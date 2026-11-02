#!/usr/bin/env bash
# Stop hook: refuse to end the turn on unverified source changes.
# "ALWAYS test after making changes. Never stop before things are tested and
# verified working." - honours stop_hook_active so it can never loop.
set -uo pipefail

input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
session=$(printf '%s' "$input" | jq -r '.session_id // ""')

dir="$HOME/.claude/state"
find "$dir" -maxdepth 1 -name 'verify-*' -mtime +7 -delete 2>/dev/null

f="$dir/verify-$session"
[ -f "$f" ] || exit 0

# Decide on line order, not timestamps: `date +%s` is second-resolution, so an
# edit made in the same second as a test run would compare equal and slip past.
vline=$(grep -n '^V ' "$f" | tail -1 | cut -d: -f1)
vline=${vline:-0}
files=$(awk -v n="$vline" 'NR>n && $1=="E" {print $3}' "$f" | sort -u)
n=$(printf '%s' "$files" | grep -c . )

if [ "$n" -gt 0 ]; then
  list=$(printf '%s\n' "$files" | head -8 | sed 's/^/  - /')
  jq -n --arg r "Stopped by the require-tests hook: $n source file(s) changed since anything last ran.
$list

Build it, run it, or run the tests, and check the output before you finish. If it genuinely cannot be run here (no suite, needs hardware, needs the user's credentials), say so explicitly in your reply and stop - do not claim it works untested." '{decision:"block", reason:$r}'
  exit 0
fi
exit 0
