---
name: git-workflow
description: Branch naming, commit conventions, and workflow steps for clean git history. Triggers on: commit, branch, merge, git, PR, pull request.
version: 1.0.0
---

# Git Workflow

## Branch Naming

Use a type prefix followed by a short slug:

```
feature/add-user-auth
fix/null-pointer-on-logout
chore/upgrade-dependencies
docs/update-api-reference
```

Types: `feature` (new functionality), `fix` (bug fixes), `chore` (maintenance, no behavior change), `docs` (documentation only), `refactor` (restructure without behavior change).

Slugs are lowercase, hyphen-separated, 3–5 words max.

## Commit Message Format

Follow Conventional Commits:

```
type(scope): short description

Optional longer body explaining WHY, not WHAT.
Wrap at 72 characters.

Closes #123
```

- **type**: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`
- **scope**: the module or area affected (optional but helpful)
- **description**: imperative mood, lowercase, no period — "add retry logic" not "Added retry logic."

Examples:
```
feat(auth): add JWT refresh token rotation
fix(api): handle null response from upstream service
chore: upgrade eslint to v9
docs(readme): add curl install method
```

## Workflow Steps

1. **Branch** — Always work on a branch, never directly on `main`
   ```bash
   git checkout -b feature/my-thing
   ```

2. **Small commits** — Commit logical units of work, not entire features in one shot. If you can't summarize the change in one line, split it.

3. **Before committing** — Run tests and linting. Don't commit broken code.
   ```bash
   npm test && npm run lint
   ```

4. **Commit** — Stage intentionally (avoid `git add -A` for sensitive repos)
   ```bash
   git add src/specific-file.ts
   git commit -m "feat(module): add thing"
   ```

5. **Push and PR** — Push to origin, open a PR with a clear title matching your commit style. Include: what changed, why, how to test it.

6. **Merge strategy** — Prefer squash-merge for feature branches to keep `main` history clean. Use merge commits only for long-lived branches where history matters.

## Anti-Patterns to Avoid

- `git add .` when sensitive files (env, credentials) could be staged
- `git push --force` on shared branches — rebase locally instead
- `git reset --hard` without confirming what you're discarding
- Committing commented-out code, debug logs, or TODO-only commits
- Merge commits from `main` into your feature branch (rebase instead)

## Checkpoint Before Ending a Session

Always run `/checkpoint` before wrapping up:
```
/checkpoint "describe what was done"
```
This runs tests, commits staged changes, and updates memory.
