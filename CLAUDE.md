## Context Efficiency

### Subagent Discipline

*Context-aware delegation:*
- Under ~50k context: prefer inline work for tasks under ~5 tool calls.
- Over ~50k context: prefer subagents for self-contained tasks, even simple ones — the per-call token tax on large contexts adds up fast.

When using subagents, include output rules: "Final response under 2000 characters. List outcomes, not process."

### File Reading

Read files with purpose. Before reading a file, know what you're looking for.
Use Grep to locate relevant sections before reading entire large files.
Never re-read a file you've already read in this session.
For files over 500 lines, use offset/limit to read only the relevant section.

### Responses

Don't echo back file contents you just read — the user can see them.
Don't narrate tool calls ("Let me read the file..." / "Now I'll edit..."). Just do it.
Keep explanations proportional to complexity. Simple changes need one sentence, not three paragraphs.

*Tables — STRICT RULES (apply everywhere, always):*
- Markdown tables: use minimum separator (single hyphen per column). Never pad with repeated hyphens.
- NEVER use box-drawing / ASCII-art tables. No corner, junction, or line-drawing Unicode characters. These are completely banned.
- No exceptions. Not for "clarity", not for alignment, not for terminal output.

## Git rules

- Never do `git add .` — stage specific files by path.
- Never add Claude attribution to git commits (no Co-Authored-By, no "Generated with Claude Code", no robot emoji).
- When you move or delete files that are tracked by git, use `git mv` / `git rm` so history follows.
- Do not reflect implementation plans in code comments or commit messages. No "Phase 1:", "Stage 2:", or "according to our plan". Describe what the code does, not which step produced it.
- Do not override git identity. The user's global git config has the correct email and name.

## Quality

- **ALWAYS test after making changes.** Never stop before things are tested and verified working. Build, run, check logs.
- Be direct. Criticize bad ideas. Ask clarifying questions.
