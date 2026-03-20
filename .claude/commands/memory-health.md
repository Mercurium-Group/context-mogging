---
description: Audit and restructure project memory. Interviews you to surface what matters, proposes a lean core.md with topic files, then executes with your approval.
allowed-tools: Bash, Read, Write, Edit, Glob
model: claude-sonnet-4-6
argument-hint: ""
---

## /memory-health

You are running a **Memory Health Audit**. The goal: keep `memory/core.md` as a lean, always-loaded index under 150 lines — and make sure it contains what actually matters at the start of every session, not just what has accumulated over time.

### Step 1: Assess current state

```bash
wc -l memory/core.md
ls memory/topics/ 2>/dev/null || echo "(no topic files yet)"
```

Read `memory/core.md` in full. Note:
- Total line count and which sections are verbose (more than ~10 lines each)
- What's missing: is there a Product Philosophy section? Working style? Key constraints?
- Any ADR full text living inline (it belongs in `memory/topics/`)
- Content that looks outdated: resolved issues, completed features unlikely to matter again

Report what you find before asking any questions:
> "core.md is N lines. [1–3 sentences on what's bloated or missing.]"

### Step 2: Interview — one question at a time

Say: "I'm going to ask 5 quick questions to make sure memory reflects what actually matters. Answer as briefly or fully as you like — I'll wait for each one."

Ask these questions **one at a time**. Do not ask the next until you have the answer.

**Question A**: What are the major areas you've been working on? (e.g., auth, sidebar, payments, API layer, framework, design system)

**Question B**: For each area — is it complete, actively in progress, or deferred?

**Question C**: What are 3–5 things a fresh Claude session would need to know to not make mistakes? Think: product philosophy, target user, working style, "why didn't we just use X" — things not obvious from reading the code.

**Question D**: Are there decisions we made that we might second-guess or re-litigate? Close calls, contentious choices. These must stay visible in memory.

**Question E**: Any open issues or blockers right now?

### Step 3: Propose a restructuring plan

Using what you read and what you learned from the interview, propose:

**What stays in `core.md`** — target ≤ 120 lines to leave headroom:
- Project identity + build commands
- **Product Philosophy** (if Q.C revealed principles that affect every decision — add this section if it doesn't exist)
- Conventions (one-liners only)
- ADR Index (one-liner per ADR + link to topic file — never full ADR text inline)
- Known Issues (active blockers only — resolved issues go to a phase log topic or deleted)
- Rejected Alternatives (one-liners — prevent re-litigation)
- Topic Index

**What moves to topic files** — list each `memory/topics/[name].md` and what content goes in it.

**What gets deleted** — duplicated content, stale resolved issues, outdated feature notes.

Show the proposed new `core.md` **outline only** (section names + estimated line counts). Do not write any file content yet.

Then say:
> Does this look right? Reply "yes" to proceed, or tell me what to change.

**Do not write any files until the user explicitly approves.**

### Step 4: Execute (only after approval)

Once the user approves:

1. Create each topic file in `memory/topics/`
2. Rewrite `memory/core.md` with the lean index

Then verify:
```bash
wc -l memory/core.md
ls memory/topics/
```

### Step 5: Report

```
## Memory Health Complete
**core.md**: [N] lines (was [N])
**Topic files created**: [list, or "none"]
**Content removed**: [brief description]
```

Then:
> Run `/checkpoint` to commit these changes.

### Rules

- **Never write files before the user approves the plan** — always show the outline first
- **Product Philosophy belongs in core.md** — it affects every decision and is the hardest thing to reconstruct from code; add it if absent
- **ADR full text always goes in topics** — one-liner index entries only in core.md
- **Rejected Alternatives stay in core.md** — they're one-liners and prevent re-litigation
- **Interview surfaces what code doesn't show** — product philosophy, working style, key decisions often exist only in the team's heads; the interview is the whole point
- **When in doubt, ask** — if you're unsure whether something is still relevant, ask the user rather than silently removing it
