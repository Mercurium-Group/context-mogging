---
description: Create an implementation plan from a task description or research artifact. Spawns Plan Architect and saves the plan for human review before implementation begins.
allowed-tools: Agent, Read, Glob, Grep, Write
model: claude-opus-4-6
argument-hint: "[task description] or --from [research-artifact-path]"
---

## /draft-plan $ARGUMENTS

You are running the **Plan** phase of the context engineering pipeline.

### Step 0: Log phase start

```bash
python3 -c "import json,datetime,os; root=os.popen('git rev-parse --show-toplevel 2>/dev/null').read().strip() or os.getcwd(); log=os.path.join(root,'thoughts/shared/logs','events.jsonl'); os.makedirs(os.path.dirname(log),exist_ok=True); f=open(log,'a'); f.write(json.dumps({'ts':datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),'event':'phase_start','phase':'plan'})+chr(10)); f.close()" 2>/dev/null || true
```

### Step 1: Load context

If `$ARGUMENTS` contains `--from [path]`, read that research artifact.

Otherwise, look for the most recent file in `thoughts/shared/research/`. If found, ask:
> "Should I use `[filename]` as the research base, or start fresh?"

Always read:
- `CLAUDE.md` — project conventions and constraints
- `memory/core.md` — ADRs, known issues, architectural decisions

### Step 2: Spawn Plan Architect

Spawn a Plan Architect agent with:
- The task description (from `$ARGUMENTS` or the user)
- The research artifact path (if any)
- A note to read CLAUDE.md and memory/core.md

Plan Architect uses `claude-opus-4-6` — this is intentional. Planning quality is worth the cost. A bad plan is more expensive than a good one.

### Step 3: Review and save

Receive the plan from Plan Architect. Check it for completeness:
- Does every phase have specific files listed?
- Does every behavioral change have a test requirement?
- Are there Open Questions that need human input?

If the plan has Open Questions, surface them to the user **before saving**.

Create the plans directory if needed: `mkdir -p thoughts/shared/plans/`

Save the plan to:
```
thoughts/shared/plans/[slug].md
```
Where `[slug]` is a kebab-case summary of the task (e.g., `add-user-auth`).

### Step 4: Present for human review

Print the full plan. Then say:
> Plan saved to `thoughts/shared/plans/[slug].md`
>
> Please review the plan above. When ready, run `/implement thoughts/shared/plans/[slug].md` to begin.
>
> To modify the plan, edit the file directly and re-run `/implement`.

### Step 5: Log phase end

```bash
python3 -c "import json,datetime,os,shlex; root=os.popen('git rev-parse --show-toplevel 2>/dev/null').read().strip() or os.getcwd(); log=os.path.join(root,'thoughts/shared/logs','events.jsonl'); artifact=os.popen('ls -t '+shlex.quote(os.path.join(root,'thoughts/shared/plans'))+'/*.md 2>/dev/null | head -1').read().strip(); f=open(log,'a'); f.write(json.dumps({'ts':datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),'event':'phase_end','phase':'plan','artifact':artifact})+chr(10)); f.close()" 2>/dev/null || true
```

### Rules

- **Do not start implementing** — this phase ends at human review
- **Surface blockers early** — Open Questions must be answered before `/implement` runs
- **One plan per task** — if a plan already exists for this task, ask before overwriting
