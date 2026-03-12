# Phase Guide

This document explains each stage of the Research → Plan → Implement → Checkpoint pipeline in detail: what it does, what it needs, what it produces, and how to use it well.

---

## Overview

The pipeline has four main phases and two utility commands:

```
/research  →  /plan  →  /implement  →  /checkpoint
                                  ↕
                             /status  /compact
```

Each phase has a clear input and output. The output of one phase is the input to the next. Nothing starts until the previous phase is complete and reviewed.

---

## Phase 1: Research (`/research`)

### What it does

Research maps the territory before any planning begins. It spawns read-only Explorer agents that systematically scan the codebase from different angles, then synthesizes their findings into a single artifact.

### Input

```
/research [topic or question]
```

Examples:
- `/research authentication flow`
- `/research how are database migrations handled`
- `/research where does the payment processing logic live`

### What happens

1. The command extracts the topic from your input.
2. It spawns 2–3 Explorer agents in parallel, each with a different focus:
   - One maps file structure and entry points
   - One traces data flow and key function calls
   - One covers cross-cutting concerns (config, tests, types) if the topic warrants it
3. If this is an unfamiliar area or you're asking "how do we do X," a Pattern Finder agent is also spawned.
4. All agent outputs are synthesized into a research artifact — not just concatenated, but distilled into key findings, open questions, and relevant file paths.
5. The artifact is saved to `thoughts/shared/research/YYYY-MM-DD-HHmm-[slug].md`.

### Output

A research artifact file containing:
- **Key Findings** — the most important discoveries, numbered
- **Relevant Files** — file paths with brief descriptions
- **Patterns Observed** — coding patterns relevant to the topic
- **Open Questions** — things that need clarification before planning

A brief summary is printed to the conversation, along with the artifact path.

### When to use it

Use `/research` before any non-trivial task. Skip it only when:
- You are fixing a well-understood, isolated bug
- You wrote the relevant code recently and know exactly what needs to change

### Context discipline

Research is designed to be context-light. The Explorer agents do the heavy reading; the main context only sees the synthesized summary. The command targets ≤40% context use when complete. If you find yourself loading many files directly while researching, use Explorer agents instead.

---

## Phase 2: Plan (`/plan`)

### What it does

Plan turns research findings (or a task description) into a precise, phase-by-phase implementation plan. The Plan Architect agent does the planning work using Opus — intentionally, because planning quality matters more than planning speed.

### Input

```
/plan [task description]
/plan --from thoughts/shared/research/YYYY-MM-DD-HHmm-slug.md
```

If you run `/plan` without `--from`, it looks for the most recent research artifact and asks whether to use it.

### What happens

1. The command loads the research artifact (if specified), `CLAUDE.md`, and `memory/core.md`.
2. It spawns Plan Architect with the task description and research context.
3. Plan Architect reads the research, examines the relevant code, sequences the work into phases, identifies risks, and lists rejected alternatives.
4. The plan is checked for completeness: every phase needs specific files, every behavioral change needs a test requirement.
5. If the plan has Open Questions, they are surfaced to you before the plan is saved.
6. You review the full plan. It is saved only after you've seen it.

### Output

A plan file at `thoughts/shared/plans/[slug].md` containing:
- **Context Summary** — 2–3 sentences synthesizing the relevant state
- **Phases** — each with: goal, files to change, functions to add/modify, test requirements, failure modes
- **Rejected Alternatives** — what was considered and why it was dismissed
- **Open Questions** — anything that needs human input before starting

### When to use it

Use `/plan` for any task with more than one logical step. If the task is one file and one function, you might skip this. For anything else — new features, refactors, bug fixes that touch multiple systems — plan first.

### The human review gate

This is the most important moment in the pipeline. The plan is presented for your review before any code is written. This is where you:
- Catch wrong assumptions
- Add context the agent didn't have
- Adjust scope
- Answer Open Questions

If anything in the plan is wrong or unclear, edit the plan file directly before running `/implement`. The plan file is just markdown — you can change it however you want.

### Why Opus?

Plan Architect uses `claude-opus-4-6`. Planning is the highest-leverage moment in the pipeline — a good plan makes implementation fast and accurate, a bad plan causes cascading problems. The quality improvement from Opus is worth the extra cost here.

---

## Phase 3: Implement (`/implement`)

### What it does

Implement executes the plan one phase at a time, running tests and a security review after each phase. It stops at any failure rather than pushing through.

### Input

```
/implement thoughts/shared/plans/[slug].md
/implement --latest
```

`--latest` finds the most recent plan in `thoughts/shared/plans/`.

### What happens

For each phase in the plan:

1. **Spawn Implementer** with the phase description, specific files to change, and test requirements.
2. **Run tests** after Implementer reports completion.
3. **If tests fail**: Stop. Report what failed. Wait for your instruction. Do not proceed to the next phase.
4. **If tests pass**: Spawn Security Reviewer with the list of changed files.
5. **If Security Reviewer finds Critical issues**: Stop. Report findings. Wait for your instruction.
6. **If Security Reviewer finds only Warnings or nothing**: Log any warnings, continue to the next phase.

After all phases complete:

7. Spawn **Test Architect** with all changed files to fill any missing test coverage.
8. Spawn **Doc Agent** with all changed files to update affected documentation.

### Output

A completion summary showing:
- Which plan was executed
- How many phases completed
- Which files changed
- Test status
- Security review status

Followed by a prompt to run `/checkpoint`.

### The "block on failure" principle

`/implement` will never proceed past a failing test or a critical security finding. This is intentional. A blocked pipeline is better than a broken codebase.

If you want to override a failure and proceed anyway — because you know why the test is failing and you'll fix it later — tell Claude explicitly. The command defers to your judgment; it just won't move forward silently.

### Context hygiene

The command loads only three things: the plan file, `CLAUDE.md`, and `memory/core.md`. It does not browse the codebase. It does not re-read the research artifact. All file reading and writing is delegated to the Implementer agent. This keeps the main context clean for orchestration.

### What the plan needs to be

Because `/implement` doesn't browse, the plan needs to be complete. Every phase should specify exact file paths, function signatures, and test file locations. If a phase says "update the authentication module" without naming the file, Implementer will have to guess. If a phase says "update `src/auth/session.ts:validateToken`," Implementer can execute it precisely.

If you notice vague steps in the plan before running `/implement`, edit the plan file first.

---

## Phase 4: Checkpoint (`/checkpoint`)

### What it does

Checkpoint is the commit gate. It runs tests, commits passing changes, and updates persistent memory. It does not commit if tests fail.

### Input

```
/checkpoint
/checkpoint "feat: add OAuth login via GitHub"
```

If you provide a commit message, it will be used exactly. Otherwise, a message is generated from the changes.

### What happens

1. **Run tests** — finds the test command from `CLAUDE.md` or `package.json` scripts and runs it.
2. **If tests fail**: Stop. Print the failure output. Do not commit. Wait for your fix.
3. **If tests pass**: Show a diff summary and flag anything unexpected (files outside the intended scope).
4. **Commit** — stage the changed files and commit with the message.
5. **Update memory** — read `memory/core.md` and update it if:
   - A new architectural decision was made
   - A known issue was resolved
   - A new project-wide convention was established
   - Build, test, or deploy commands changed
6. **Report** — print the commit hash, files changed, and memory update status. Assess context weight and suggest next steps.

### Output

```
## Checkpoint Complete
Committed: abc1234 — feat: add OAuth login via GitHub
Files: 8 files changed
Memory: updated — added ADR: use JWT for session tokens
```

### Never commit broken code

The no-failing-tests rule is strict. Checkpoint will refuse to commit if tests fail, regardless of arguments. If you need to commit work-in-progress code without tests passing, use git directly and bypass the command.

### Memory discipline

Checkpoint only updates `memory/core.md` for genuinely durable, project-wide information. It does not log implementation details, reasoning, or task-specific notes. Memory should contain things that matter in future sessions, not a diary of what happened this session.

---

## Utility: Status (`/status`)

### What it does

Status gives you a quick orientation — where you are in the pipeline, what artifacts are active, and how the context is holding up.

### When to run it

- At the start of a session, to get oriented
- When you've been away and forgotten where you left off
- When the context feels heavy and you want an honest assessment

### Output

```
## Status Report
Branch: feature/oauth-login
Last commit: abc1234 — fix: token validation (2 hours ago)
Working tree: 3 files changed

## Active Artifacts
Research: 2024-01-15-1430-auth-flow-overview.md
Plans: add-oauth-login.md
Logs: none

## Recent Commits
[last 5 commits]

## Project
[project name and current work from memory/core.md]

## Context Health
moderate — long conversation, consider /compact before next task
```

---

## Utility: Compact (`/compact`)

### What it does

Compact prepares you to safely reset the context window. It does not compact on its own — it gets you ready to use Claude's built-in `/compact` without losing important information.

### When to run it

- When `/status` reports moderate or heavy context
- Between tasks, before starting something new
- When the session has been going for a while and things feel sluggish

### What happens

1. Assesses the current session: active plan, unresolved issues, key decisions, uncommitted changes.
2. Writes anything important that isn't already in `memory/core.md`.
3. Builds a preservation list — a structured summary of what the built-in `/compact` should preserve.
4. Hands off to you with instructions for running the built-in `/compact`.

### The preservation list

The list looks like this:

```
Things to preserve after compaction:

1. Active plan: thoughts/shared/plans/add-oauth-login.md — Phase 3 of 5, adding token refresh logic
2. Unresolved issues: session invalidation edge case on concurrent login
3. Key decisions made this session: use refresh token rotation, not sliding expiry
4. Working state: branch=feature/oauth-login, last test=PASS, staged=no
5. Next action: implement Phase 3 — src/auth/token.ts:refreshToken
```

Paste this when the built-in `/compact` asks what to preserve. After compaction, run `/status` to verify you're oriented.

### Write memory before compacting

Never compact before writing important knowledge to memory. Compaction throws away the conversation. If a decision was made this session that should survive, it needs to be in `memory/core.md` first. `/compact` handles this automatically, but it's worth understanding why the order matters.
