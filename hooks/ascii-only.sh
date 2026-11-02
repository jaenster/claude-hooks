#!/usr/bin/env bash
# PreToolUse/Write|Edit|Bash: block fancy Unicode in code, comments, and commits.
# Claude loves em-dashes, curly quotes, arrows, and other typographic characters
# that have no business in source code. ASCII only.
#
# Scoped: only fires on source files and commit messages, not prose (.md, .txt).
set -uo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Detect non-ASCII typographic characters by checking for any byte outside
# printable ASCII (0x20-0x7E) and newline/tab. This is simpler and more
# reliable than listing every Unicode codepoint.
# We exempt a few ranges that appear in legitimate source (e.g. UTF-8 string
# literals in user-facing messages) by only scanning comment lines and
# string-free contexts — but that's over-complex for a guard hook. Instead:
# just flag any non-ASCII byte. If it's in a string literal the user intended,
# they can allow it. False positives on intentional i18n strings are rare in
# code comments and commit messages.
has_non_ascii() {
  # Match any byte outside 0x09 (tab), 0x0A (newline), 0x0D (CR), 0x20-0x7E.
  printf '%s' "$1" | perl -e '$d=join("",<STDIN>); exit($d=~/[^\t\n\r\x20-\x7e]/ ? 0 : 1)' 2>/dev/null
}

# For the deny message, identify which kind of fancy character was found.
describe_chars() {
  local text=$1
  local found=""
  # Use perl for reliable Unicode property matching.
  printf '%s' "$text" | perl -ne 'exit 0 if /\x{2014}/' 2>/dev/null && found="$found em-dash,"
  printf '%s' "$text" | perl -ne 'exit 0 if /\x{2013}/' 2>/dev/null && found="$found en-dash,"
  printf '%s' "$text" | perl -ne 'exit 0 if /[\x{2010}-\x{2012}\x{2015}]/' 2>/dev/null && found="$found Unicode dash,"
  printf '%s' "$text" | perl -ne 'exit 0 if /[\x{2018}\x{2019}]/' 2>/dev/null && found="$found curly single quotes,"
  printf '%s' "$text" | perl -ne 'exit 0 if /[\x{201C}\x{201D}]/' 2>/dev/null && found="$found curly double quotes,"
  printf '%s' "$text" | perl -ne 'exit 0 if /[\x{00AB}\x{00BB}\x{2039}\x{203A}]/' 2>/dev/null && found="$found guillemets,"
  printf '%s' "$text" | perl -ne 'exit 0 if /\x{2026}/' 2>/dev/null && found="$found ellipsis,"
  printf '%s' "$text" | perl -ne 'exit 0 if /[\x{2190}-\x{2199}\x{21D2}]/' 2>/dev/null && found="$found Unicode arrow,"
  printf '%s' "$text" | perl -ne 'exit 0 if /\x{2022}/' 2>/dev/null && found="$found bullet,"
  printf '%s' "$text" | perl -ne 'exit 0 if /[\x{00D7}\x{00F7}\x{2212}\x{2248}\x{2260}\x{2261}\x{2264}\x{2265}\x{2044}]/' 2>/dev/null && found="$found Unicode math operator,"
  printf '%s' "$text" | perl -ne 'exit 0 if /[\x{00A0}\x{00AD}\x{2002}-\x{200D}\x{FEFF}]/' 2>/dev/null && found="$found invisible/fancy whitespace,"
  [ -z "$found" ] && found=" non-ASCII character,"
  printf '%s' "$found" | sed 's/,$//' | sed 's/^ //'
}

# Prose files where fancy characters are fine.
is_prose() { printf '%s' "$1" | grep -Eiq '\.(md|markdown|mdx|txt|rst|adoc|org|tex|html|css|svg)$'; }

describe_chars() {
  local text=$1
  local found=""
  printf '%s' "$text" | grep -Poq '\x{2014}' 2>/dev/null && found="$found em-dash,"
  printf '%s' "$text" | grep -Poq '\x{2013}' 2>/dev/null && found="$found en-dash,"
  printf '%s' "$text" | grep -Poq '[\x{2010}-\x{2012}\x{2015}]' 2>/dev/null && found="$found Unicode dash,"
  printf '%s' "$text" | grep -Poq '[\x{2018}\x{2019}]' 2>/dev/null && found="$found curly single quotes,"
  printf '%s' "$text" | grep -Poq '[\x{201C}\x{201D}]' 2>/dev/null && found="$found curly double quotes,"
  printf '%s' "$text" | grep -Poq '[\x{00AB}\x{00BB}\x{2039}\x{203A}]' 2>/dev/null && found="$found guillemets,"
  printf '%s' "$text" | grep -Poq '\x{2026}' 2>/dev/null && found="$found ellipsis,"
  printf '%s' "$text" | grep -Poq '[\x{2190}-\x{2199}\x{21D2}]' 2>/dev/null && found="$found Unicode arrow,"
  printf '%s' "$text" | grep -Poq '\x{2022}' 2>/dev/null && found="$found bullet,"
  printf '%s' "$text" | grep -Poq '[\x{00D7}\x{00F7}\x{2212}\x{2248}\x{2260}\x{2261}\x{2264}\x{2265}\x{2044}]' 2>/dev/null && found="$found Unicode math operator,"
  printf '%s' "$text" | grep -Poq '[\x{00A0}\x{00AD}\x{2002}-\x{200D}\x{FEFF}]' 2>/dev/null && found="$found invisible/fancy whitespace,"
  printf '%s' "$found" | sed 's/,$//' | sed 's/^ //'
}

case "$tool" in
  Write|Edit)
    path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
    is_prose "$path" && exit 0
    content=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // ""')
    if has_non_ascii "$content"; then
      chars=$(describe_chars "$content")
      deny "Blocked by the ascii-only hook: source code must use ASCII only. Found: $chars. Use straight quotes (' \"), hyphens (-), three dots (...), and ASCII arrows (->, =>) instead."
    fi
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
    # Only check git commit message bodies, not the whole command.
    printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' || exit 0
    msg=""
    if printf '%s' "$cmd" | grep -Eq "(-m|--message)[[:space:]]*'"; then
      msg=$(printf '%s' "$cmd" | sed -nE "s/.*(-m|--message)[[:space:]]*'([^']*).*/\2/p" | head -1)
    elif printf '%s' "$cmd" | grep -Eq '(-m|--message)[[:space:]]*"'; then
      msg=$(printf '%s' "$cmd" | sed -nE 's/.*(-m|--message)[[:space:]]*"([^"]*).*/\2/p' | head -1)
    fi
    [ -z "$msg" ] && exit 0
    if has_non_ascii "$msg"; then
      chars=$(describe_chars "$msg")
      deny "Blocked by the ascii-only hook: commit messages must use ASCII only. Found: $chars. Use straight quotes, hyphens, and plain dots instead."
    fi
    ;;
esac

exit 0
