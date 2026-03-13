---
description: Report current pipeline state, active artifacts, git status, and context health. Run anytime to get oriented.
allowed-tools: Bash, Read, Glob
model: claude-haiku-4-5-20251001
argument-hint: ""
---

## /status

Report the current state of the pipeline and working environment.

### Gather information

Run these commands:
```bash
git status --short
git log --oneline -5
git branch --show-current
```

Check for active artifacts:
```bash
ls thoughts/shared/research/ 2>/dev/null | sort | tail -5
ls thoughts/shared/plans/ 2>/dev/null | sort | tail -5
ls thoughts/shared/logs/ 2>/dev/null | sort | tail -5
```

Read the first 50 lines of `memory/core.md` to get project identity and recent ADRs.

### Output format

```
## Status Report
**Branch**: [branch name]
**Last commit**: [hash] [message] ([time ago])
**Working tree**: [clean / N files changed]

## Active Artifacts
**Research**: [most recent research file, or "none"]
**Plans**: [most recent plan file, or "none"]
**Logs**: [most recent log file, or "none"]

## Recent Commits
[last 5 commits, one line each]

## Project
[project name from memory/core.md]
[one-line description of current work if known from memory]

## Context Health
[light / moderate / heavy] — [brief assessment]
```

### Context assessment

- **Light**: Short conversation, few files loaded → continue freely
- **Moderate**: Long conversation or several large files loaded → consider `/save-session` soon
- **Heavy**: Very long conversation or context feels sluggish → run `/save-session` before next task

End with one of:
> Use `/research [topic]` to start investigating, `/plan [task]` to plan work, or `/implement --latest` to resume an existing plan.

Or if context is heavy:
> Run `/save-session` before starting the next task to keep things clean.

For detailed pipeline KPIs and session health:
> Run `/metrics` to see checkpoint success rates, session durations, and pipeline conversion rates.
