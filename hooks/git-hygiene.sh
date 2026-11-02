#!/usr/bin/env bash
# PreToolUse/Bash guard for git hygiene:
#   1. mv/rm on git-tracked paths -> must go through git mv / git rm.
#   2. Secrets in the staged diff before a commit lands.
#   3. --no-verify (bypasses every guard you set up).
#   4. Bare --force pushes, and any force push to a protected branch.
#   5. Blanket staging (git add . / -A / --all / * / :/).
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null
# Honour a leading "cd <dir> &&" so tracked-ness is resolved in the repo the
# command actually targets, not just the session's cwd.
lead=$(printf '%s' "$cmd" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^;&|]+)[[:space:]]*(&&|;).*/\1/p' | tr -d "\"'" | sed 's/[[:space:]]*$//' | head -1)
[ -n "$lead" ] && [ -d "$lead" ] && cd "$lead" 2>/dev/null

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

in_repo() { git rev-parse --git-dir >/dev/null 2>&1; }
has() { printf '%s' "$cmd" | grep -Eq "$1"; }

# ---- 3. --no-verify ---------------------------------------------------------
if has '(^|[;&|(]|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(commit|push|merge)([[:space:]]|$)' && has '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
  deny 'Blocked by the git-hygiene hook: --no-verify bypasses the pre-commit/pre-push guards this repo installed on purpose. Fix what the guard is complaining about instead. If the guard itself is wrong, say so and let the user decide.'
fi

# ---- 5. blanket staging -----------------------------------------------------
if has '(^|[;&|(]|[[:space:]])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+add([[:space:]]+[^;&|]*)?[[:space:]]+(\.|\./|-A|--all|\*|:/|:/\.)([[:space:]]|[;&|)]|$)'; then
  deny 'Blocked by the git-hygiene hook: blanket staging (git add . / -A / --all / *) sweeps in whatever else is lying around - build output, scratch files, secrets. Stage the files you changed by name: git add path/one path/two.'
fi

# ---- 4. force push ----------------------------------------------------------
if has '(^|[;&|(]|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'; then
  if has '(^|[[:space:]])(--force|-f)([[:space:]]|$)'; then
    deny 'Blocked by the git-hygiene hook: bare --force discards whatever someone else pushed. Use --force-with-lease, which refuses when the remote moved under you.'
  fi
  if has '(^|[[:space:]])--force-with-lease' ; then
    rest=$(printf '%s\n' "$cmd" | sed -E 's/^.*[[:space:]]push([[:space:]]|$)//' | tr ' ' '\n' | grep -Ev '^-|^$')
    if [ "$(printf '%s\n' "$rest" | grep -c .)" -ge 2 ]; then
      target=$(printf '%s\n' "$rest" | sed -n '2p' | sed 's/.*://')
    else
      target=$(git symbolic-ref --short HEAD 2>/dev/null)
    fi
    target=$(printf '%s' "$target" | grep -Ex '(main|master|develop|production)')
    if [ -n "$target" ]; then
      deny "Blocked by the git-hygiene hook: force pushing to '$target' rewrites shared history. Do this on a feature branch, or ask the user to run it themselves if it is genuinely intended."
    fi
  fi
fi

# ---- 1. mv / rm on tracked paths -------------------------------------------
# Drop a leading "cd <dir> &&" (already consumed above) so the directory is not
# mistaken for an mv/rm operand, and neutralise git's own mv/rm.
# Drop a leading "cd <dir> &&" (already consumed above), neutralise git's own
# mv/rm, and discard heredoc bodies - text inside a heredoc is data, not a
# command being run now.
bare=$(printf '%s\n' "$cmd" \
  | sed -E 's/^[[:space:]]*cd[[:space:]]+[^;&|]+[[:space:]]*(&&|;)[[:space:]]*//' \
  | sed -E 's/git[[:space:]]+(mv|rm)/gitxx/g' \
  | awk '{ if (index($0,"<<")>0) { sub(/<<.*/,""); print; exit } print }')

check_tracked() { # $1 = candidate path
  local tok=$1 tracked=""
  [ -n "$tok" ] || return 0
  case "$tok" in -*) return 0 ;; esac
  [ -e "$tok" ] || return 0
  if [ -d "$tok" ]; then
    [ -n "$(git ls-files -- "$tok" 2>/dev/null | head -1)" ] && tracked=1
  else
    git ls-files --error-unmatch -- "$tok" >/dev/null 2>&1 && tracked=1
  fi
  [ -n "$tracked" ] || return 0
  deny "Blocked by the git-hygiene hook: '$tok' is tracked by git. Use 'git mv' to move or rename it, or 'git rm' to delete it, so history follows the file. Plain mv/rm makes it look like a delete plus an unrelated add."
}

if in_repo; then
  while IFS= read -r stmt; do
    # shellcheck disable=SC2086
    set -- $stmt
    [ $# -gt 0 ] || continue
    op=$1; shift
    case "$op" in mv|rm) ;; *) continue ;; esac
    args=""
    for a in "$@"; do
      case "$a" in -*) continue ;; esac
      args="$args$a
"
    done
    n=$(printf '%s' "$args" | grep -c .)
    # For mv the final operand is the destination; moving a new file INTO a
    # tracked directory is fine and needs no git mv.
    [ "$op" = mv ] && [ "$n" -gt 1 ] && n=$((n - 1))
    [ "$n" -gt 0 ] || continue
    i=0
    while IFS= read -r a; do
      i=$((i + 1)); [ "$i" -gt "$n" ] && break
      check_tracked "$a"
    done < <(printf '%s' "$args")
  done < <(printf '%s\n' "$bare" | tr ';&|' '\n\n\n' | sed -e 's/^[[:space:]]*//' -e "s/[\"']//g")
fi

# ---- 2. secrets in the staged diff ------------------------------------------
if in_repo && has '(^|[;&|(]|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'; then
  added=$(git diff --cached 2>/dev/null | grep '^+' | grep -v '^+++')
  if has '(^|[[:space:]])-[a-zA-Z]*a([[:space:]]|$)|(^|[[:space:]])--all([[:space:]]|$)'; then
    added="$added
$(git diff 2>/dev/null | grep '^+' | grep -v '^+++')"
  fi

  HIGH='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{50,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|glpat-[A-Za-z0-9_-]{20,}'
  hit=$(printf '%s' "$added" | grep -Eo -- "$HIGH" | head -1)
  if [ -n "$hit" ]; then
    deny "Blocked by the git-hygiene hook: the staged diff contains what looks like a live credential (matched: $(printf '%s' "$hit" | cut -c1-12)...). Unstage it, move the value to an environment variable or secret store, and rotate the key if it was ever real."
  fi

  # Generic key=value secrets, ignoring obvious placeholders and indirection.
  GENERIC='(api[_-]?key|secret[_-]?(key|token)?|auth[_-]?token|access[_-]?token|passwd|password)["'"'"' ]*[:=]+["'"'"' ]*[A-Za-z0-9/+_=-]{24,}'
  hit=$(printf '%s' "$added" | grep -Eio -- "$GENERIC" \
        | grep -Eiv 'xxx|yyy|zzz|example|placeholder|changeme|redacted|dummy|sample|your[-_]|test[-_]?(key|token)|process\.env|os\.getenv|\$\{|<' | head -1)
  if [ -n "$hit" ]; then
    deny "Blocked by the git-hygiene hook: the staged diff assigns a long literal to a secret-shaped name ($(printf '%s' "$hit" | cut -c1-40)...). If it is a real credential, pull it out and rotate it. If it is a fixture, tell the user and let them decide."
  fi

  envf=$(git diff --cached --name-only 2>/dev/null | grep -E '(^|/)\.env(\.|$)' | grep -Ev '\.(example|sample|template|dist)$' | head -1)
  if [ -n "$envf" ]; then
    deny "Blocked by the git-hygiene hook: '$envf' is staged. Environment files hold live credentials. Unstage it and add it to .gitignore."
  fi
fi

exit 0
