---
description: Prepare for context compaction. Captures durable knowledge to memory, then provides preservation hints for Claude's built-in /compact command.
allowed-tools: Read, Bash, Glob, Write
model: claude-haiku-4-5-20251001
argument-hint: "[--preserve topic]"
---

## /save-session $ARGUMENTS

Prepare for context compaction. This command does NOT compact the context — it gets you ready to use Claude's built-in `/compact` effectively so nothing important is lost.

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

### Step 4: Hand off to built-in /compact

Print:
```
## Ready to Compact

Memory is up to date.

Here's what to preserve — paste this when /compact asks:

---
[preservation list]
---

Next: Run the built-in `/compact` command now.
After compaction, run `/status` to verify orientation.
```

### Step 5: Log compaction

```bash
python3 -c "import json,datetime,os; root=os.popen('git rev-parse --show-toplevel 2>/dev/null').read().strip() or os.getcwd(); uncommitted=len(os.popen('git status --porcelain 2>/dev/null').read().splitlines()); log=os.path.join(root,'thoughts/shared/logs','events.jsonl'); os.makedirs(os.path.dirname(log),exist_ok=True); f=open(log,'a'); f.write(json.dumps({'ts':datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),'event':'save_session','uncommitted_files':uncommitted})+chr(10)); f.close()" 2>/dev/null || true
```

### Rules

- **Write memory before compacting** — never compact before capturing durable knowledge
- **Be specific in preservation hints** — "the plan" is less useful than the actual file path and phase number
- **Uncommitted changes are at risk** — always note them in the preservation hint
- **This command is fast** — quick assessment, write memory if needed, hand off. Don't over-analyze
