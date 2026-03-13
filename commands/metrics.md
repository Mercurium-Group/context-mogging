---
description: Display pipeline metrics, session health, and task KPIs from event logs and git history. Run anytime to assess pipeline health.
allowed-tools: Bash, Read, Glob
model: claude-sonnet-4-6
argument-hint: "[--since 7d] [--json]"
---

## /metrics $ARGUMENTS

You are running the **Metrics** phase of the context engineering pipeline.

### Step 1: Parse arguments

Parse `$ARGUMENTS`:
- `--since [N]d` or `--since [N]h`: Time window for git history (default: `7d`)
- `--json`: Output raw JSON instead of formatted dashboard

### Step 2: Read event log

```bash
cat thoughts/shared/logs/events.jsonl 2>/dev/null
```

If the file does not exist or is empty, skip to **Step 6** and display the empty-state message.

Parse the JSONL output line by line. Skip any lines that are not valid JSON. Extract:
- `session_start` / `session_end` pairs → session count, durations
- `phase_start` / `phase_end` pairs grouped by `phase` field → per-phase timing
- `guard_block` events → count by `tool` field
- `checkpoint` events → count, commits, files changed
- `checkpoint_failed` events → count
- `save_session` events → compaction count
- `post_edit` events → proxy for context activity

### Step 3: Scan artifacts

```bash
ls -lt thoughts/shared/research/ 2>/dev/null | grep '\.md$' | head -20
ls -lt thoughts/shared/plans/ 2>/dev/null | grep '\.md$' | head -20
```

Count:
- Total research artifacts (`.md` files in `thoughts/shared/research/`)
- Total plan artifacts (`.md` files in `thoughts/shared/plans/`)
- Research-to-plan ratio (plans / research artifacts, or 0 if none)

### Step 4: Parse git history

```bash
git log --oneline --since="7 days ago" 2>/dev/null | head -30
git log --since="7 days ago" --format="" --shortstat 2>/dev/null | tail -5
```

Adjust `--since` to match the `--since` argument from Step 1 (default: `7d` → `"7 days ago"`, `30d` → `"30 days ago"`, `24h` → `"24 hours ago"`).

Extract:
- Commit count in window
- Total files changed, insertions, deletions across commits in window

### Step 5: Parse memory

```bash
grep -c "^### ADR-" memory/core.md 2>/dev/null || echo 0
grep -c "^- \*\*" memory/core.md 2>/dev/null || echo 0
```

Count ADRs and items under Known Issues / Conventions.

### Step 6: Compute KPIs and display

**If no events exist** (Step 2 found nothing), display:

```
## Context-Mogging Metrics
No metrics data yet.

Run a full pipeline cycle to start collecting:
  /research [topic]  →  /draft-plan [task]  →  /implement [plan]  →  /checkpoint

Hooks and commands will log events automatically to:
  thoughts/shared/logs/events.jsonl
```

**Otherwise**, compute:

**Session KPIs** (from session_start/session_end pairs):
- Session count = number of `session_start` events
- Average session duration = mean of (session_end.ts - session_start.ts) in minutes, paired by proximity
- Compaction frequency = save_session count / session count (target: ≤ 0.33, i.e., once per 3+ sessions)

**Pipeline KPIs** (from phase events):
- Implement success rate = checkpoint count / (checkpoint + checkpoint_failed) events (if any; else N/A)
- Research → Plan conversion = plan artifacts / research artifacts (if any; else N/A)

**Guard KPIs** (from guard_block events):
- Total guard blocks, broken down by Write vs Bash

**Code KPIs** (from git log):
- Commits in window, total lines changed

Display the dashboard:

```
## Context-Mogging Metrics
Period: last [N] days | [N sessions] sessions

### Session Health
Sessions:          [N]
Avg duration:      [Xm] (if calculable, else "—")
Compactions:       [N] ([ratio] per session) [⚠ if > 1/3]
Guard blocks:      [N] ([Write: N] [Bash: N])
Post-edit events:  [N]

### Pipeline Flow
Research artifacts: [N]
Plan artifacts:     [N] (conversion: [N]%)
Implements:        [N complete] [N blocked] ([success rate]%)
Checkpoints:       [N pass] / [N+fail total] ([success rate]%)

### Code Activity (last [N] days)
Commits:           [N]
Lines changed:     +[N] -[N]

### Memory
ADRs:              [N]
Tracked items:     [N]

### Recommendations
[1-3 actionable items based on data, or "Pipeline looks healthy." if all metrics are good]
```

**Recommendation logic** (generate only relevant ones):
- If compaction frequency > 1 per 2 sessions: "Compacting frequently — start fresh sessions earlier or run /save-session sooner"
- If checkpoint success rate < 80% and checkpoints > 2: "Low checkpoint success rate — improve test coverage or plan specificity"
- If research-to-plan ratio < 0.5 and research artifacts > 2: "Many orphaned research artifacts — consider archiving or planning from them"
- If no events in last 7 days but artifacts exist: "No recent pipeline activity — pipeline data may be stale"
- If all metrics are within normal range: "Pipeline looks healthy."

### Rules

- **Read-only** — this command never writes files
- **Graceful degradation** — empty data → show empty-state message with instructions
- **No external dependencies** — bash, git, python3 only
- **Skip unparseable lines** — malformed JSONL lines are ignored with no error
- **--json mode**: output all KPI values as a single JSON object and stop, no dashboard formatting
