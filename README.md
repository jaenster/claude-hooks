# Claude Code Hooks

A collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) hooks that enforce coding standards, git hygiene, and prevent common AI-assistant footguns.

These hooks run as `PreToolUse` and `PostToolUse` interceptors — Claude Code calls them before (or after) every tool invocation, and they can **deny** a call with a reason that teaches the model what to do instead. Think of them as guardrails that make Claude a better collaborator without you having to repeat yourself.

## What's included

| Hook | Trigger | What it does |
|-|-|-|
| **no-claude-clutter** | `Bash`, `Write`, `Edit` | Blocks Claude attribution in commits/PRs, blanket `git add .`, and plan-narration comments in code |
| **git-hygiene** | `Bash` | Enforces `git mv`/`git rm` for tracked files, blocks `--no-verify`, bare `--force` pushes, force pushes to protected branches, blanket staging, and secrets in staged diffs |
| **git-identity** | `Bash` | Prevents Claude from overriding your git identity with its session email (the Anthropic account email, not your git email) |
| **md-style** | `Write`, `Edit` | Enforces minimal markdown table separators (`\|-\|-\|`) and bans box-drawing characters |
| **pnpm-only** | `Bash` | Blocks `npm` commands and suggests the `pnpm` equivalent (leaves `npx` alone) |
| **require-tests** | Stop hook | Blocks Claude from finishing its turn if source files were changed but nothing was built/tested |
| **track-verify** | `PostToolUse` | Records which files changed and when tests/builds ran; feeds the require-tests stop hook |
| **regress** | — | Regression test suite for all the above hooks |

## Quick install (macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/jaenster/claude-hooks/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/jaenster/claude-hooks.git
cd claude-hooks
./install.sh
```

The installer:
1. Copies hooks to `~/.claude/hooks/`
2. Makes them executable
3. Merges the hook config into your `~/.claude/settings.json` (backs up first)
4. Runs the regression suite to verify everything works

## Manual setup

1. Copy the `hooks/` directory to `~/.claude/hooks/`
2. Make them executable: `chmod +x ~/.claude/hooks/*.sh`
3. Add the hook configuration to your `~/.claude/settings.json` — see [settings.example.json](settings.example.json) for the exact structure

## How hooks work

Claude Code hooks intercept tool calls at three points:

- **PreToolUse** — runs before a tool executes. Can `deny` the call with a reason (Claude sees the reason and retries differently) or `allow` it.
- **PostToolUse** — runs after a tool executes. Can record state but can't undo the call.
- **Stop** — runs when Claude wants to end its turn. Can `block` to force Claude to keep going (e.g. "you haven't tested yet").

Each hook receives JSON on stdin with `tool_name`, `tool_input`, `session_id`, and `cwd`. It prints JSON to stdout only when it wants to intervene — silent exit means "allow".

See [docs/hook-reference.md](docs/hook-reference.md) for a detailed breakdown of each hook.

## Customization

Every hook is a standalone bash script. Fork and adjust:

- **pnpm-only.sh** — swap `pnpm` for `yarn` or `bun` if that's your package manager
- **git-hygiene.sh** — edit the `HIGH` regex to add your org's secret patterns, or change the protected branch list
- **no-claude-clutter.sh** — the plan-narration patterns are tuned for how Claude talks; you probably won't need to change these
- **md-style.sh** — if you actually want padded table separators, just delete this hook
- **git-identity.sh** — works out of the box by comparing against your `git config --global user.email`

## The CLAUDE.md

This repo includes a [CLAUDE.md](CLAUDE.md) with opinionated defaults for how Claude should behave. It's not required for the hooks to work, but it's the set of instructions these hooks were built to enforce. Copy it to `~/.claude/CLAUDE.md` or to your project's root.

## Writing your own hooks

A hook is any executable that:
1. Reads JSON from stdin
2. Optionally prints a JSON response to stdout
3. Exits 0

For a PreToolUse deny:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Human-readable reason Claude will see and learn from"
  }
}
```

For a Stop block:
```json
{
  "decision": "block",
  "reason": "Why Claude can't stop yet"
}
```

The reason text is critical — it's what teaches the model. Write it like you're correcting a junior dev: say what's wrong and what to do instead.

## Testing

Run the regression suite:

```bash
./hooks/regress.sh
```

It creates a throwaway git repo in `/tmp`, exercises every hook with known-good and known-bad inputs, and reports pass/fail.

## License

MIT
