# Writing Your Own Hooks

## The basics

A Claude Code hook is any executable (bash, python, node, whatever) that:

1. Reads JSON from stdin
2. Optionally prints JSON to stdout
3. Exits with code 0

There are three hook points:

| Point | When it runs | Can it stop things? |
|-|-|-|
| **PreToolUse** | Before a tool call | Yes — `deny` prevents execution |
| **PostToolUse** | After a tool call | No — but can record state |
| **Stop** | When Claude wants to end its turn | Yes — `block` forces it to continue |

## Input format

Every hook receives a JSON object on stdin:

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m 'fix: something'"
  },
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "stop_hook_active": false
}
```

The shape of `tool_input` depends on the tool:
- `Bash`: `{ "command": "..." }`
- `Write`: `{ "file_path": "...", "content": "..." }`
- `Edit`: `{ "file_path": "...", "old_string": "...", "new_string": "..." }`
- Stop hooks get `stop_hook_active: true` when the stop hook itself triggers another tool call (to prevent infinite loops)

## Output format

**Silent exit = allow.** If your hook prints nothing and exits 0, the tool call proceeds normally.

**PreToolUse deny:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Explain what's wrong and what to do instead"
  }
}
```

**Stop block:**
```json
{
  "decision": "block",
  "reason": "Explain why Claude can't stop yet"
}
```

## The deny reason is everything

The reason string is what Claude sees. It's your one chance to teach the model. Good reasons:
- Say what's wrong
- Say what to do instead
- Are specific enough that Claude doesn't repeat the mistake

Bad: `"Don't use npm"`
Good: `"This machine uses pnpm, never npm. Use pnpm add instead. npx is still fine for one-off binaries."`

## Configuration

Hooks are registered in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/your/hook.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

- **matcher**: pipe-separated tool names (`"Bash|Write|Edit"`)
- **timeout**: seconds before the hook is killed (keep it short — hooks run on every tool call)
- **command**: absolute path to the executable

## Tips

**Use `jq` for JSON parsing.** It's the simplest way to extract fields from the input and produce the output.

**Keep hooks fast.** They run on every matching tool call. A 5-second hook on `Bash` means 5 seconds added to every shell command.

**Test with regress.sh as a template.** Pipe fake JSON into your hook and check the output:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"npm install"}}' | ./hooks/pnpm-only.sh
```

**Use `set -uo pipefail`** but not `set -e`. A hook that crashes (exit != 0) is treated as an error, not a deny. You want controlled denials via the JSON output.

**Scope narrowly.** A hook that scans every Write for every possible problem will be slow and full of false positives. Match on specific tool names, check paths early, and exit 0 as soon as you know it's irrelevant.

**PostToolUse hooks can feed Stop hooks.** PostToolUse records state, Stop reads it. This is the pattern for "enforce X before finishing."
