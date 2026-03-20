# Core Memory

> This is the project's persistent memory. Claude reads this at the start of every session.
> **Keep this file under 150 lines.** It is truncated at 200 — anything beyond that is invisible.
>
> **Two-tier memory model:**
> - `core.md` (this file) = always-loaded index. One-liners only. No long lists, no verbose notes.
> - `memory/topics/*.md` = detail fetched on demand. Move anything verbose here.
>
> When a section grows beyond ~10 lines, move it to `memory/topics/[topic].md` and replace it
> with a one-line Topic Index entry. Run `wc -l memory/core.md` at each `/checkpoint` to check.

## Project Identity

- **Name**: {{PROJECT_NAME}}
- **Created**: {{DATE}}
- **Stack**: {{STACK}}

## Product Philosophy

<!-- 3–5 bullets: who this is for, how they should feel, guiding principles.      -->
<!-- These affect every decision — copy tone, UX choices, architecture forks.      -->
<!-- Fill this in at project start. It is the hardest thing to reconstruct from    -->
<!-- code after the fact. Run /memory-health if this section is blank after day 1. -->

## Build Commands

```bash
install: {{INSTALL_CMD}}
dev:     {{DEV_CMD}}
test:    {{TEST_CMD}}
lint:    {{LINT_CMD}}
build:   {{BUILD_CMD}}
```

## ADR Index

<!-- One-liner per ADR. Full text belongs in memory/topics/adrs.md (or split by domain). -->
<!-- Writing full ADR text inline here is the #1 cause of core.md bloat — don't do it.  -->
<!-- Format: - **ADR-001**: [one-line summary] → [topics/adrs.md](topics/adrs.md)        -->

## Conventions

<!-- Discovered by pattern-finder or established by the team -->
<!-- Format: - **[Convention]**: [Description] (source: [file:line]) -->

## Known Issues

<!-- Format: - **[Issue]**: [Description] — Workaround: [workaround] -->

## Rejected Alternatives

<!-- Things we tried and decided against — prevents revisiting dead ends -->
<!-- Format: - **[Alternative]**: [Why rejected] (date: [DATE]) -->

## Topic Index

<!-- Offload detail here. When any section above grows beyond ~10 lines, move it to a topic file. -->
<!-- Claude will Read() topic files on demand when working in that area.                         -->
<!-- Format: - [topic-name](topics/topic-name.md) — [one-line description]                      -->
