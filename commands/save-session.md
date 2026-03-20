---
description: Intentional context hygiene. Save memory and choose your path: compact in-place or continue in a fresh session.
allowed-tools: Read, Bash, Glob, Write
model: claude-haiku-4-5-20251001
argument-hint: "[--preserve topic]"
---

## /save-session $ARGUMENTS

Saves all durable knowledge to memory, builds a continuation prompt, and gives you two clean paths forward: compact this session in-place using Claude's built-in /compact, or start a fresh session and paste the continuation prompt to pick up exactly where you left off.

Use this after /checkpoint, after /draft-plan, or any time context feels heavy (50-60%+ used).

### Step 1: Assess what's in context

Quickly review what has been loaded and discussed this session. Identify:
- **Active plan**: Is there a plan being executed? What phase is it on?
- **Unresolved issues**: Any test failures, blockers, or open questions?
- **Key decisions**: Any architectural choices made this session not yet in memory?
- **In-progress work**: Any uncommitted changes?

Run `git status --short` to check for uncommitted changes.

### Step 2: Write durable knowledge to memory

If there are key decisions or architectural changes from this session not yet in `memory/core.md`, write them now. Compaction will lose the detailed reasoning — capture the conclusion.

Only write things that are:
- Project-wide (not task-specific)
- Likely to matter in future sessions
- Not already in memory

**Before writing, check memory health:**

```bash
wc -l memory/core.md
```

- **Under 150 lines**: write directly to `core.md` as usual
- **150+ lines**: do NOT append to `core.md` — route new knowledge to a topic file instead:
  1. Create `memory/topics/[topic-name].md` with the detailed content
  2. Add a one-liner to the Topic Index in `core.md`: `- [topic-name](topics/topic-name.md) — [one-line description]`
  3. If existing sections in `core.md` are verbose (long lists, multi-line workarounds, feature inventories), move them to topic files too — this is a good time to do it

`core.md` is the always-loaded index (truncated after 200 lines). Topic files are fetched on demand. Keep core lean.

### Step 3: Build the preservation hint

Construct a preservation list for the built-in `/compact`:

```
Things to preserve after compaction:

1. Active plan: [path] — Phase [N] of [M], [what phase N does]
2. Unresolved issues: [list any blockers or open questions]
3. Key decisions made this session: [list or "none"]
4. Working state: branch=[name], last test=[PASS/FAIL], staged=[yes/no]
5. Next action: [what was I about to do next?]
```

If `$ARGUMENTS` contains `--preserve [topic]`, add that topic explicitly to the list.

If nothing is in progress (clean working tree, no active plan), simplify to:
```
Session complete. No active work to preserve.
```

### Step 4: Present paths forward

Print the following:

---

## Memory Saved — Choose Your Path

All durable knowledge is written to memory. Here are your two options:

### Path A — Compact in place (stay in this session)

Run Claude's built-in `/compact` command. When it asks what to preserve, paste the list above.
This compresses context but keeps you in the same session.

### Path B — Fresh session (recommended after major phase transitions)

1. Copy this continuation prompt:

---
**Continuation prompt** (paste at the start of your next `claude` session):

```
I'm continuing work on [PROJECT NAME].

Last completed: [LAST COMPLETED PHASE OR TASK — e.g., "drafted plan for X" / "implemented phase 2" / "checkpointed commit abc1234"]

Active plan: [PLAN FILE PATH if applicable, else "none"]

Run `/status` to orient, then [NEXT ACTION — e.g., "run /implement [plan path]"].
```
---

2. Exit this session (`Ctrl+C` or type `/quit`)
3. Run `claude` in your terminal
4. Paste the continuation prompt

> **Note**: Context-mogging has no `/compact` command of its own. `/save-session` is the preparation step — the actual compaction happens via Claude's built-in or a fresh session.

---

### Step 5: Log compaction

```bash
python3 -c "import json,datetime,os; root=os.popen('git rev-parse --show-toplevel 2>/dev/null').read().strip() or os.getcwd(); uncommitted=len(os.popen('git status --porcelain 2>/dev/null').read().splitlines()); log=os.path.join(root,'thoughts/shared/logs','events.jsonl'); os.makedirs(os.path.dirname(log),exist_ok=True); f=open(log,'a'); f.write(json.dumps({'ts':datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),'event':'save_session','uncommitted_files':uncommitted})+chr(10)); f.close()" 2>/dev/null || true
```

### Rules

- **Write memory before compacting** — never compact before capturing durable knowledge
- **Be specific in preservation hints** — "the plan" is less useful than the actual file path and phase number
- **Uncommitted changes are at risk** — always note them in the preservation hint
- **This command is fast** — quick assessment, write memory if needed, hand off. Don't over-analyze
