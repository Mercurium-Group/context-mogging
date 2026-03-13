---
description: Execute an implementation plan phase by phase. Orchestrates Implementer, Security Reviewer, Test Architect, and Doc Agent in sequence. Run after /plan.
allowed-tools: Agent, Read, Write, Edit, Bash, Glob, Grep
model: claude-sonnet-4-6
argument-hint: "[plan-file-path] or --latest"
---

## /implement $ARGUMENTS

You are running the **Implement** phase of the context engineering pipeline.

### Step 1: Load the plan

If `$ARGUMENTS` is `--latest`, find the most recent file in `thoughts/shared/plans/`.

Read the plan file. Read nothing else except:
- `CLAUDE.md` (for build/test commands)
- `memory/core.md` (for architectural constraints)

Do not load the research artifact. Do not browse the codebase. The plan is the source of truth.

### Step 1.5: Log implementation start

```bash
python3 -c "import json,datetime,os; root=os.popen('git rev-parse --show-toplevel 2>/dev/null').read().strip() or os.getcwd(); log=os.path.join(root,'thoughts/shared/logs','events.jsonl'); os.makedirs(os.path.dirname(log),exist_ok=True); f=open(log,'a'); f.write(json.dumps({'ts':datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),'event':'phase_start','phase':'implement'})+chr(10)); f.close()" 2>/dev/null || true
```

### Step 2: Execute phases

For each phase in the plan:

**1. Spawn Implementer** with:
   - The phase description from the plan
   - The specific files to change
   - The test requirements for this phase

**2. Run tests** after Implementer reports completion:
   ```bash
   [test command from CLAUDE.md]
   ```

**3. If tests fail**: Stop. Log the failure, report what failed. Do NOT proceed to the next phase. Wait for user instruction.

```bash
python3 -c "import json,datetime,os; root=os.popen('git rev-parse --show-toplevel 2>/dev/null').read().strip() or os.getcwd(); log=os.path.join(root,'thoughts/shared/logs','events.jsonl'); f=open(log,'a'); f.write(json.dumps({'ts':datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),'event':'phase_end','phase':'implement','result':'BLOCKED'})+chr(10)); f.close()" 2>/dev/null || true
```

**4. If tests pass**: Spawn Security Reviewer with the list of changed files.

**5. If Security Reviewer finds Critical issues**: Stop. Report the findings. Do NOT proceed. Wait for user instruction.

**6. If Security Reviewer finds only Warnings/Passed**: Log the warnings, continue to next phase.

### Step 3: Post-implementation

After all phases complete successfully:

1. Spawn **Test Architect** with all changed files — let it add any missing test coverage
2. Spawn **Doc Agent** with all changed files — let it update affected documentation

### Step 4: Finish

Print a summary:
```
## Implementation Complete
**Plan**: [plan file path]
**Phases completed**: N/N
**Files changed**: [list]
**Tests**: PASS
**Security**: [CLEAN / N warnings noted]
```

Log the completion:

```bash
python3 -c "import json,datetime,os; root=os.popen('git rev-parse --show-toplevel 2>/dev/null').read().strip() or os.getcwd(); log=os.path.join(root,'thoughts/shared/logs','events.jsonl'); f=open(log,'a'); f.write(json.dumps({'ts':datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),'event':'phase_end','phase':'implement','result':'COMPLETE'})+chr(10)); f.close()" 2>/dev/null || true
```

Then say:
> Run `/checkpoint` to commit this work and update memory.

### Rules

- **One phase at a time** — never overlap phases
- **Block on failure** — a blocked pipeline is better than a broken codebase
- **Don't improvise** — if the plan is ambiguous, surface the ambiguity to the user rather than guessing
- **Context hygiene** — delegate all file reading/writing to sub-agents. Keep the main context for orchestration only
- **Never skip Security Review** — even if you're confident the change is safe
