#!/usr/bin/env bash
# Install claude-hooks into ~/.claude/hooks/ and merge config into settings.json.
set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/hooks"

echo "claude-hooks installer"
echo "======================"
echo

# ---- sanity checks ----------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed."
  echo "  brew install jq"
  exit 1
fi

if [ ! -d "$SRC" ]; then
  echo "Error: hooks/ directory not found next to this script."
  echo "Run this from the cloned repo root."
  exit 1
fi

# ---- copy hooks -------------------------------------------------------------

mkdir -p "$HOOK_DIR"
echo "Copying hooks to $HOOK_DIR ..."

copied=0
for f in "$SRC"/*.sh; do
  name=$(basename "$f")
  # regress.sh is the test suite, not a runtime hook
  [ "$name" = "regress.sh" ] && continue
  cp "$f" "$HOOK_DIR/$name"
  chmod +x "$HOOK_DIR/$name"
  echo "  $name"
  copied=$((copied + 1))
done
echo "  $copied hooks installed."
echo

# ---- merge settings ---------------------------------------------------------

echo "Configuring settings ..."

if [ ! -f "$SETTINGS" ]; then
  echo "  No settings.json found — creating from example."
  # Expand ~ to $HOME in the example since settings.json needs absolute paths.
  sed "s|~/.claude/hooks|$HOOK_DIR|g" "$SCRIPT_DIR/settings.example.json" > "$SETTINGS"
  echo "  Created $SETTINGS"
else
  # Back up existing settings.
  backup="$SETTINGS.bak.$(date +%s)"
  cp "$SETTINGS" "$backup"
  echo "  Backed up existing settings to $backup"

  # Merge: add our hooks entries without clobbering existing ones.
  # Strategy: read the example, expand paths, and deep-merge the hooks key.
  example=$(sed "s|~/.claude/hooks|$HOOK_DIR|g" "$SCRIPT_DIR/settings.example.json")

  merged=$(jq --argjson example "$example" '
    # For each hook phase (PreToolUse, PostToolUse, Stop), append entries
    # from the example that are not already present (matched by command path).
    .hooks //= {} |
    reduce ($example.hooks | to_entries[]) as $phase (.;
      .hooks[$phase.key] //= [] |
      reduce $phase.value[] as $entry (.;
        if (.hooks[$phase.key] | map(.hooks[]?.command) | index($entry.hooks[0].command))
        then .
        else .hooks[$phase.key] += [$entry]
        end
      )
    )
  ' "$SETTINGS")

  printf '%s\n' "$merged" > "$SETTINGS"
  echo "  Merged hook configuration into $SETTINGS"
fi
echo

# ---- optional: copy CLAUDE.md -----------------------------------------------

if [ ! -f "$HOME/.claude/CLAUDE.md" ]; then
  printf "No ~/.claude/CLAUDE.md found. Copy the example? [y/N] "
  read -r answer
  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    cp "$SCRIPT_DIR/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    echo "  Copied CLAUDE.md"
  fi
elif [ -f "$SCRIPT_DIR/CLAUDE.md" ]; then
  echo "~/.claude/CLAUDE.md already exists -- skipping (see CLAUDE.md in this repo for reference)."
fi
echo

# ---- optional: global git hooks ---------------------------------------------

GIT_HOOKS_SRC="$SCRIPT_DIR/git-hooks"
GIT_HOOKS_DIR="$HOME/.config/git/hooks"

if [ -d "$GIT_HOOKS_SRC" ]; then
  printf "Install global git hooks (blocks Claude attribution at the git level)? [y/N] "
  read -r answer
  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    mkdir -p "$GIT_HOOKS_DIR"
    for f in "$GIT_HOOKS_SRC"/*; do
      name=$(basename "$f")
      if [ -f "$GIT_HOOKS_DIR/$name" ]; then
        echo "  $name already exists -- skipping"
      else
        cp "$f" "$GIT_HOOKS_DIR/$name"
        chmod +x "$GIT_HOOKS_DIR/$name"
        echo "  installed $name"
      fi
    done
    current=$(git config --global core.hooksPath 2>/dev/null || true)
    if [ -z "$current" ]; then
      git config --global core.hooksPath "$GIT_HOOKS_DIR"
      echo "  set core.hooksPath to $GIT_HOOKS_DIR"
    elif [ "$current" = "$GIT_HOOKS_DIR" ]; then
      echo "  core.hooksPath already set"
    else
      echo "  core.hooksPath is already '$current' -- not changing it"
    fi
  fi
  echo
fi

# ---- run regression suite ---------------------------------------------------

echo "Running regression tests ..."
echo
if "$SRC/regress.sh"; then
  echo
  echo "All tests passed. You're good to go."
else
  echo
  echo "Some tests failed -- check the output above."
  exit 1
fi
