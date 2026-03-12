---
description: Run tests, commit passing changes, and update memory. Does not commit if tests fail. Run after /implement or any significant work session.
allowed-tools: Bash, Read, Write, Edit
model: claude-sonnet-4-6
argument-hint: "[optional commit message]"
---

## /checkpoint $ARGUMENTS

You are running the **Checkpoint** phase of the context engineering pipeline.

### Step 1: Run tests

Find the test command from CLAUDE.md or `package.json` scripts. Run it:
```bash
[test command]
```

If tests fail, stop immediately:
```
## Checkpoint Failed — Tests Not Passing

[paste test output]

Fix the failing tests before checkpointing. Do not commit broken code.
```

Do not continue until tests pass.

### Step 2: Review what changed

```bash
git status
git diff --stat HEAD
```

Print a brief summary of what changed. If anything looks unexpected (files outside the intended scope), flag it and ask the user to confirm before continuing.

### Step 3: Commit

Stage the changed files and commit:
```bash
git add [changed files]
git commit -m "[message]"
```

**Commit message rules:**
- If `$ARGUMENTS` contains a message, use it exactly
- Otherwise, generate a message from the changes:
  - Start with a verb: Add, Fix, Update, Remove, Refactor
  - Describe what changed, not why
  - Keep under 72 characters
  - If multiple logical changes, use a multi-line format with a summary line and bullet points

### Step 4: Update memory

Read `memory/core.md`. Update it only if:
- A new architectural decision was made during this work
- A known issue was resolved
- A new project-wide convention was established
- The build, test, or deploy commands changed

Skip this step if nothing important changed. Do not update memory for implementation details.

### Step 5: Report

```
## Checkpoint Complete
**Committed**: [short hash] — [message]
**Files**: [N files changed]
**Memory**: [updated: [what changed] / no changes]
```

Assess context weight:
- If the conversation has been long or many files were loaded, say:
  > Context is getting heavy. Run `/compact` before starting the next task.
- Otherwise:
  > Ready for the next task. Run `/research [topic]` or `/plan [task]` to continue.

### Rules

- **Never commit failing tests** — tests must pass before any commit
- **Never force-push** — if a push is needed, ask the user explicitly
- **Commit message discipline** — no "WIP", "misc", or "fix" without specifics
- **Memory is optional** — only update it for genuinely durable, project-wide information
