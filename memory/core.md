# Core Memory

> This is the project's persistent memory. Append new entries — don't delete old ones.
> Claude reads this at the start of every session to maintain continuity.

## Project Identity

- **Name**: [PROJECT_NAME]
- **Created**: [DATE]
- **Stack**: [STACK]

## Build Commands

```bash
install: [INSTALL_CMD]
dev:     [DEV_CMD]
test:    [TEST_CMD]
lint:    [LINT_CMD]
build:   [BUILD_CMD]
```

## Architecture Decision Records

<!-- Format: ### ADR-001: [Title] / Date / Decision / Rationale -->

## Conventions

<!-- Discovered by pattern-finder or established by the team -->
<!-- Format: - **[Convention]**: [Description] (source: [file:line]) -->

## Known Issues

<!-- Format: - **[Issue]**: [Description] — Workaround: [workaround] -->
- **hooks format bug** (resolved 2026-03-13, commit 9606336): Claude Code rejected generated `settings.json` with "hooks: Expected array, but received undefined". Root cause: hook entries used flat `{matcher, description, command}` structure instead of the required `{matcher, hooks: [{type: "command", command: "..."}]}` format. Fixed in `templates/settings.json`, `bin/install.js`, `install.sh`.
- **package.json version mismatch**: `package.json` shows `1.0.0` but v1.1.0 (auto-detect feature) and a subsequent patch fix have shipped. Version needs bumping to `1.1.1` before next publish.

## Rejected Alternatives

<!-- Things we tried and decided against — prevents revisiting dead ends -->
<!-- Format: - **[Alternative]**: [Why rejected] (date: [DATE]) -->
- **Keep `description` field in hooks**: Rejected (2026-03-13) — not in Claude Code hooks schema, causes validation error.
- **Deduplicate hooks by `matcher`**: Rejected (2026-03-13) — not unique; SessionStart/Stop have no matcher. Using `hooks[0].command` instead.
- **Deduplicate hooks by position/index**: Rejected (2026-03-13) — fragile for merge scenarios where existing file has different order.

## Topic Index

<!-- Links to detailed memory files in memory/topics/ -->
<!-- Format: - [topic-name](topics/topic-name.md) — [one-line description] -->
