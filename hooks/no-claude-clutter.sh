#!/usr/bin/env bash
# PreToolUse guard. Three jobs:
#   1. Keep Claude attribution boilerplate out of git commits/tags/notes and
#      GitHub/GitLab PRs, issues and releases (inline text AND -F/--body-file).
#   2. Refuse blanket staging (add-everything forms).
#   3. Keep implementation-plan narration out of code comments and commit
#      messages (numbered phases/stages, and "according to the plan" prose).
# Deliberately narrow: only git/gh/glab commands, commit-message-shaped writes
# and comment lines in code files are inspected, so editing ~/.claude, writing
# docs, or naming a variable "phase" is never blocked.
set -uo pipefail

SELF=${BASH_SOURCE[0]}
input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# ---- patterns (ERE, matched case-insensitively) -----------------------------

ATTRIB_RE='co-authored-by:[[:space:]]*claude|generated with \[?claude code|claude\.ai/code|claude-session:|noreply@anthropic\.com|🤖'

# A line that opens with a comment marker.
COMMENT_START='^[[:space:]]*(//+|#+|/\*+|\*+|--|<!--|;+|%+)'

# Comment marker, then a plan-numbered heading: "// Phase 1:", "# Stage two -".
PLAN_NUM_RE="${COMMENT_START}[[:space:]]*[-*[:space:]]*(phase|stage|part)[[:space:]]*#?[[:space:]]*([0-9]+|one|two|three|four|five)([^a-z0-9]|\$)"

# Plan narration in prose, tested only against comment lines.
PLAN_PROSE_RE='(as per|as in|according to|per|from|in|of) (our|the|my|this) (implementation |migration |rollout |refactor )?plan\b|as (we )?(planned|discussed) (above|earlier|before)|see (our|the) plan\b|(step|phase|stage) [0-9]+ of (our|the) (implementation |migration |rollout |refactor )?plan\b'

# In commit messages the word itself is the tell, wherever it sits.
COMMIT_PLAN_RE='((-m|--message)[[:space:]=]+["'"'"']?|^)[[:space:]]*(phase|stage|part)[[:space:]]*#?[[:space:]]*([0-9]+|one|two|three)([^a-z0-9]|$)'

ATTRIB_MSG='Blocked by the no-claude-clutter hook: this text carries Claude attribution boilerplate (Co-Authored-By: Claude, "Generated with Claude Code", a claude.ai/code link, Claude-Session:, noreply@anthropic.com, or a robot emoji). The user never wants Claude referenced in commits, tags or PRs. Rewrite it without that trailer/footer and retry.'

PLAN_MSG='Blocked by the no-claude-clutter hook: this reflects our implementation plan in the artifact (a numbered "Phase/Stage N" heading, or "according to the plan" prose). The user does not want plans mirrored into code comments or commit messages. Describe what the code does and why, not which step of our plan produced it.'

STAGE_MSG='Blocked by the no-claude-clutter hook: blanket staging is not allowed (no bare ".", no -A, no --all). Stage the specific paths you changed.'

# Files where a leading-# "Phase 1" line is a legitimate heading, not a comment.
is_doc() { printf '%s' "$1" | grep -Eiq '\.(md|markdown|txt|rst|adoc|org|tex)$'; }

scan_plan_comments() { # $1 = file content
  printf '%s' "$1" | grep -Eiq "$PLAN_NUM_RE" && return 0
  printf '%s' "$1" | grep -Ei "$COMMENT_START" | grep -Eiq "$PLAN_PROSE_RE" && return 0
  return 1
}

# ---- dispatch ---------------------------------------------------------------

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

    if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+add[[:space:]]+(-A([[:space:]]|$)|--all([[:space:]]|$)|\.([[:space:]]|$)|:/)'; then
      deny "$STAGE_MSG"
    fi

    if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])(git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(commit|tag|notes|merge|revert|cherry-pick|rebase)|gh[[:space:]]+(pr|issue|release)|glab[[:space:]]+(mr|issue))([[:space:]]|$)'; then
      payload=$cmd
      while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && payload="$payload
$(cat "$f")"
      done < <(printf '%s' "$cmd" \
        | grep -oE '(--body-file|--notes-file|--file|-F)[=[:space:]]+[^[:space:];&|"'"'"']+' \
        | sed -E 's/^(--body-file|--notes-file|--file|-F)[=[:space:]]+//')
      printf '%s' "$payload" | grep -Eiq "$ATTRIB_RE" && deny "$ATTRIB_MSG"
      printf '%s' "$payload" | grep -Eiq "$COMMIT_PLAN_RE" && deny "$PLAN_MSG"
      printf '%s' "$payload" | grep -Eiq "$PLAN_PROSE_RE" && deny "$PLAN_MSG"
    fi
    ;;

  Write|Edit)
    path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
    [ "$path" = "$SELF" ] && exit 0
    content=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // ""')

    if printf '%s' "$path" | grep -Eq 'COMMIT_EDITMSG|MERGE_MSG|TAG_EDITMSG|SQUASH_MSG|[-_./]?(pr|mr)[-_.]?(body|desc|description|message)|commit[-_.]?(msg|message)'; then
      printf '%s' "$content" | grep -Eiq "$ATTRIB_RE" && deny "$ATTRIB_MSG"
      printf '%s' "$content" | grep -Eiq "$COMMIT_PLAN_RE" && deny "$PLAN_MSG"
    fi

    if ! is_doc "$path"; then
      scan_plan_comments "$content" && deny "$PLAN_MSG"
    fi
    ;;
esac

exit 0
