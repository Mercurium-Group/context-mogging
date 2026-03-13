# [Project-name]

> This file is your project's governance layer for Claude Code. Fill in the placeholders and customize to match your project.

## Project Overview

- **Name**: [Project-name]
- **Description**: [SHORT_DESCRIPTION]
- **Architecture**: [ARCHITECTURE — e.g., Next.js frontend + Python FastAPI backend + PostgreSQL]
- **Repo**: [REPO_URL]

## Workflow

This project uses the **Research → Plan → Implement** pipeline.

1. **Research first**: Run `/research [topic]` before making changes to unfamiliar areas
2. **Plan before building**: Run `/plan [task]` to create a reviewed implementation plan
3. **Implement from plans**: Run `/implement` to execute plans step-by-step with tests and security review
4. **Checkpoint often**: Run `/checkpoint` after completing work to commit and update memory

Never skip straight to implementation without understanding the codebase first.

## Build & Test Commands

```bash
# Install dependencies
[INSTALL_CMD — e.g., npm install]

# Run development server
[DEV_CMD — e.g., npm run dev]

# Run tests
[TEST_CMD — e.g., npm test]

# Run linter
[LINT_CMD — e.g., npm run lint]

# Build for production
[BUILD_CMD — e.g., npm run build]
```

## Code Conventions

- [LANGUAGE/FRAMEWORK conventions — e.g., TypeScript strict mode, ESLint + Prettier]
- [NAMING conventions — e.g., camelCase for variables, PascalCase for components]
- [FILE STRUCTURE — e.g., feature-based folders under src/]
- [TEST conventions — e.g., colocated test files with .test.ts suffix]

## Memory References

Core project memory is stored in `memory/core.md`. It tracks:
- Architecture decisions (ADRs)
- Known issues and workarounds
- Rejected alternatives (so we don't revisit dead ends)
- Conventions discovered by the pattern finder

Topic-specific memory lives in `memory/topics/`. Create new topic files as the project grows.

Session memory in `memory/sessions/` is ephemeral and gitignored.

## Protected Files

These files should not be modified without explicit human approval:
- `CLAUDE.md` (this file)
- `memory/core.md` (append-only by convention)
- [ADD YOUR OWN — e.g., database migrations, CI config]

## Architecture Boundaries

- [BOUNDARY 1 — e.g., Frontend never calls database directly]
- [BOUNDARY 2 — e.g., All API calls go through src/lib/api.ts]
- [BOUNDARY 3 — e.g., No business logic in route handlers]

## Error Handling

- Maximum 3 retry attempts for any operation
- Report errors with context: what failed, what was attempted, what to try next
- Never silently catch and ignore errors
- Use project-standard error types: [ERROR_TYPES — e.g., AppError, ValidationError]
