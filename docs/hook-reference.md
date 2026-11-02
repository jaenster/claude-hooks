# Hook Reference

Detailed breakdown of every hook, what it catches, and why.

## no-claude-clutter.sh

**Trigger:** `PreToolUse` on `Bash`, `Write`, `Edit`

Claude has a strong tendency to insert attribution into everything it touches — `Co-Authored-By: Claude` trailers, "Generated with Claude Code" footers, `claude.ai/code` links, and robot emoji. This hook catches all of those before they reach git commits, tags, PRs, issues, or releases.

It also catches two other Claude habits:

**Blanket staging.** `git add .`, `git add -A`, `git add --all` — these sweep in scratch files, build output, and secrets. The hook forces Claude to name specific paths.

**Plan narration.** Claude loves to label things "Phase 1:", "Stage 2:", "Part three:" in code comments and commit messages when working from a plan. The hook blocks numbered plan headings in comment lines and "according to our plan" prose. Variable names like `phase` and domain terms like "stage 2 of the ETL pipeline" are left alone — it only fires on lines that start with a comment marker.

### What it inspects

- **Bash:** git commit/tag/merge/rebase/cherry-pick commands (inline `-m` and `-F`/`--body-file` contents), and `gh`/`glab` PR/issue/release commands
- **Write/Edit:** files whose path looks like a commit message (`COMMIT_EDITMSG`, `pr-body`, etc.), and comment lines in any non-doc source file

### False positive safety

- Fenced code blocks are stripped before scanning (you can document the patterns)
- Doc files (`.md`, `.txt`, `.rst`, etc.) are exempt from plan-comment scanning
- Variable/property names containing "phase" or "stage" are fine — only comment-leading lines trigger

## git-hygiene.sh

**Trigger:** `PreToolUse` on `Bash`

Five guards:

1. **Tracked file moves/deletes.** If a file is tracked by git, `mv` and `rm` lose history. The hook checks `git ls-files` and blocks plain `mv`/`rm` on tracked paths, telling Claude to use `git mv`/`git rm`. Moving an untracked file *into* a tracked directory is allowed.

2. **Secrets in staged diffs.** Before any `git commit`, the hook scans the staged diff for:
   - High-confidence patterns: private keys, AWS access keys, GitHub tokens, Slack tokens, Google API keys, GitLab PATs, Anthropic API keys
   - Generic `api_key=<long literal>` patterns (ignoring obvious placeholders like `xxx`, `changeme`, `process.env`)
   - Staged `.env` files (not `.env.example` or `.env.template`)

3. **`--no-verify`.** Blocks `git commit --no-verify` / `git push --no-verify` — these bypass the repo's own pre-commit hooks, which exist for a reason.

4. **Force pushes.** Bare `--force` is always blocked (use `--force-with-lease`). Even `--force-with-lease` is blocked when targeting `main`, `master`, `develop`, or `production`.

5. **Blanket staging.** Same as no-claude-clutter but from the git-hygiene angle: `git add .`, `-A`, `--all`, `*`, `:/`.

### False positive safety

- Heredoc bodies are stripped before scanning `mv`/`rm` — a `rm` inside a heredoc is data, not a command
- `git mv` and `git rm` are explicitly allowed (the hook neutralizes them before scanning)
- `node_modules` and other untracked directories aren't flagged
- The leading `cd <dir> &&` pattern is followed so tracked-ness is checked in the right repo

## git-identity.sh

**Trigger:** `PreToolUse` on `Bash`

Claude Code has access to the user's Anthropic account email via session context. It sometimes uses this email when running `git config user.email`, which pollutes commits with the wrong identity.

This hook:
- Blocks any `git config user.email` that sets an `@anthropic.com` address
- Blocks any `git config user.email` that differs from the global git email
- Allows reads (`--get`) and unsets

## md-style.sh

**Trigger:** `PreToolUse` on `Write`, `Edit`

Enforces two markdown table rules:

1. **No box-drawing characters.** Unicode line-drawing characters are banned everywhere. Not in tables, not in "terminal output", not for "clarity". They render inconsistently and break copy-paste.

2. **Minimal separators.** Markdown table separators must use a single hyphen per column, not padded runs.

### Scope

Only fires on prose files (`.md`, `.markdown`, `.mdx`, `.txt`, `.rst`). Source code that legitimately draws TUI boxes is not touched. Content inside fenced code blocks is stripped before scanning — you can document the banned patterns without triggering the hook.

## pnpm-only.sh

**Trigger:** `PreToolUse` on `Bash`

If your project uses pnpm, Claude will still reach for `npm` half the time. This hook catches it and suggests the correct pnpm equivalent:

- `npm install` -> `pnpm install`
- `npm install <pkg>` -> `pnpm add <pkg>`
- `npm ci` -> `pnpm install --frozen-lockfile`
- `npm run <script>` -> `pnpm run <script>`
- `npm test` -> `pnpm test`
- etc.

`npx` is deliberately left alone — it's a one-off binary runner, not a package manager.

### Customization

To adapt this for `yarn` or `bun`, change the detection pattern and the suggestion map. The structure is the same.

## regress.sh

Not a runtime hook — this is the test suite. Run it to verify all hooks work correctly:

```bash
./hooks/regress.sh
```

It creates a throwaway git repo, exercises every hook with known-good and known-bad inputs, and prints pass/fail. The suite covers:
- False positives that were historically problematic (moving untracked files into tracked dirs, domain terms like "stage" in commit messages, fenced code blocks with banned characters)
- True positives (moving tracked files, blanket staging, plan comments, npm commands, padded separators, sudo, secrets, conventional commits)
