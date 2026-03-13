# Agent Guide

Context-mogging includes 7 specialized sub-agents. Each has a narrow mandate — it's good at one thing and deliberately prevented from doing anything outside that scope.

This document covers: what each agent does, when to spawn it manually, what to expect from its output, and how to get the most out of it.

---

## How agents work in Claude Code

Sub-agents are spawned by slash commands automatically. You don't need to call them directly during a normal pipeline run — `/research` spawns Explorer and Pattern Finder, `/draft-plan` spawns Plan Architect, `/implement` orchestrates Implementer, Security Reviewer, Test Architect, and Doc Agent.

You can also spawn any agent manually using Claude Code's agent spawning syntax:

```
Spawn an Explorer agent to map the payment processing module.
```

Claude Code will find the agent definition in `agents/explorer.md` (or `.claude/agents/explorer.md` after install) and run it with the instructions you provide.

---

## Explorer

**File**: `agents/explorer.md`
**Model**: Sonnet
**Color**: Blue

### What it does

Explorer is a read-only codebase mapping agent. It traces structure, follows data flows, and surfaces relevant file locations. It never suggests changes or modifications.

### When to spawn it manually

- You need to understand how a system works before deciding how to change it
- You want to find where a specific behavior is implemented
- You're new to a codebase area and want a map before diving in
- `/research` would be overkill (you want exploration, not a full synthesis)

### How to invoke

```
Spawn an Explorer agent to map the authentication middleware.
Give it this focus: trace every place a JWT token is validated, from the request header to the final user object.
```

### What to expect

A structured response with four sections:

```
## Files Found
- src/middleware/auth.ts:24 — validateToken function, called on all /api routes

## Key Patterns
- JWT validation: always uses jsonwebtoken.verify() — seen in auth.ts:24, session.ts:41

## Information Flow
[trace of how data moves through the relevant code]

## Raw Notes
[anything important that doesn't fit above]
```

Maximum 200 lines. Every claim has a file:line citation. No suggestions, no opinions.

### Tips

- Give Explorer a specific focus. "Explore the codebase" produces less useful output than "trace how user permissions are checked."
- Spawn multiple Explorers in parallel if the topic has multiple independent angles. `/research` does this automatically, but you can do it manually too.
- Explorer's output is designed to be fed into Plan Architect. Save it to a file if you want to use it later.

---

## Pattern Finder

**File**: `agents/pattern-finder.md`
**Model**: Sonnet
**Color**: Yellow

### What it does

Pattern Finder excavates the codebase to find how things are actually done — naming conventions, error handling style, file organization, test structure, import patterns. It produces evidence-based findings with file citations and frequency counts.

### When to spawn it manually

- You're adding a feature and want to match existing patterns exactly
- You've noticed inconsistency in the codebase and want a clear picture of what the "real" convention is
- You're onboarding to a codebase and want to understand the implicit style guide
- Before writing any new code in an area you haven't touched before

### How to invoke

```
Spawn a Pattern Finder agent to analyze error handling patterns across the entire codebase.
```

### What to expect

```
## Pattern Report: Error Handling
Files analyzed: 47 files across 8 directories
Date: 2024-01-15

## Confirmed Patterns

### Try/Catch with typed errors (seen 23 times)
All async functions use try/catch. Errors are typed as AppError | NetworkError.
Examples: src/api/users.ts:15, src/api/orders.ts:33
Rule: Never use bare catch (e). Always type-assert or use instanceof.

## Inconsistencies
- 4 files in src/legacy/ use callback-style error handling instead of try/catch

## Inferred Style Guide
- Use try/catch for all async operations
- ...
```

Maximum 150 lines. Every pattern cited with at least 2 file:line references.

### Tips

- Use Pattern Finder before writing any new code in an unfamiliar area. The Implementer agent is already instructed to do this, but you can run it manually for your own reference.
- Ask Pattern Finder about a specific category: "error handling patterns", "test file structure", "how are API routes organized."
- Its output is useful context for Plan Architect when planning changes that need to fit existing conventions.

---

## Plan Architect

**File**: `agents/plan-architect.md`
**Model**: Opus
**Color**: Purple

### What it does

Plan Architect turns a task description and research findings into a precise, executable implementation plan. It reads widely — research artifacts, existing code, CLAUDE.md, memory/core.md — but never writes anything except the plan itself.

### When to spawn it manually

Normally you don't — `/draft-plan` handles this. Spawn manually if:
- You want a plan for a sub-task within a larger plan
- You want to compare two different planning approaches
- You're iterating on an existing plan and want fresh input

### How to invoke

```
Spawn a Plan Architect agent.
Task: Add rate limiting to the /api/login endpoint.
Research: thoughts/shared/research/2024-01-15-1430-auth-flow-overview.md
```

### What to expect

A plan in this format:

```
## Plan: Add Rate Limiting to Login Endpoint
Date: 2024-01-15
Research: thoughts/shared/research/...
Estimated phases: 2

## Context Summary
[2-3 sentences]

## Phases

### Phase 1: Add rate limiting middleware
Goal: Install and configure express-rate-limit for the /api/login route
Files to change:
- src/middleware/rateLimit.ts — create new middleware
- src/app.ts:47 — register middleware before auth routes
...

## Rejected Alternatives
- redis-based rate limiting: overkill for current scale

## Open Questions
- Should rate limits be per-IP or per-username?
```

### Tips

- Plan Architect uses Opus intentionally. Don't switch it to Sonnet to save cost — planning quality is worth it.
- If the plan has Open Questions, answer them before running `/implement`. Ambiguous plans produce ambiguous implementations.
- You can edit the plan file directly after it's saved. Plan Architect produces a starting point, not a sacred document.

---

## Implementer

**File**: `agents/implementer.md`
**Model**: Sonnet
**Color**: Green

### What it does

Implementer executes a single plan phase. It reads only what the phase specifies, makes only the changes the phase requires, runs tests after each change, and reports results. It does not improvise, does not scope-creep, and does not continue past a test failure.

### When to spawn it manually

Normally you don't — `/implement` orchestrates this. Spawn manually if:
- You have a specific, well-defined change you want executed precisely
- You want to run a single phase of a plan without the full `/implement` orchestration

### How to invoke

```
Spawn an Implementer agent with this phase:

Phase: Add validateToken helper
Files to change: src/auth/token.ts — add validateToken(jwt: string): User | null
Functions to add: validateToken(jwt: string): User | null — validates signature, expiry, and returns parsed user or null
Tests required:
- [ ] validateToken returns User when JWT is valid (in tests/auth/token.test.ts)
- [ ] validateToken returns null when JWT is expired
- [ ] validateToken returns null when signature is invalid
```

### What to expect

Implementer reports:
- What it changed (file by file)
- Test results after each change
- Any test failures, with output pasted verbatim
- A completion summary when the phase is done

It will stop and report if tests fail rather than attempting to fix them — that's the human's call.

### Tips

- Implementer's quality depends on plan quality. A vague phase produces vague implementation.
- Never give Implementer broad latitude ("refactor the auth module"). Give it specific, bounded tasks.
- If Implementer reports an ambiguity in the phase specification, clarify the plan and respawn rather than asking it to guess.

---

## Security Reviewer

**File**: `agents/security-reviewer.md`
**Model**: Sonnet
**Color**: Red

### What it does

Security Reviewer scans code changes for vulnerabilities using the OWASP Top 10 as a baseline checklist. It produces categorized findings with evidence. It does not implement fixes.

### When to spawn it manually

Normally you don't — `/implement` runs this automatically after each phase. Spawn manually if:
- You want a security review of existing code (not just changes)
- You're reviewing a PR from someone else
- You want a second opinion on a specific security concern

### How to invoke

```
Spawn a Security Reviewer agent.
Review these files for security issues: src/auth/token.ts, src/middleware/auth.ts
Focus on: JWT handling, session management, and any user-controlled input.
```

### What to expect

```
## Security Review
Files reviewed: src/auth/token.ts, src/middleware/auth.ts
Review date: 2024-01-15

### 🔴 Critical
(none found)

### 🟡 Warning
- **Missing expiry check** — src/auth/token.ts:42
  Token is validated for signature but expiry field is not explicitly checked.
  Risk: expired tokens may be accepted if the JWT library's strict mode is not configured.

### ✅ Passed
- A01 Broken Access Control — authorization check present on all routes
- A03 Injection — no SQL or command injection vectors found
...
```

Or, if clean:

```
## Security Review — CLEAN
All OWASP Top 10 categories reviewed. No issues found.
```

### Tips

- Security Reviewer scopes to the diff by default. If you want it to review pre-existing code too, say so explicitly.
- It will not guess at vulnerabilities — every finding needs a concrete file:line reference. If it's uncertain, it marks something Warning, not Critical.
- Never skip security review on changes that touch auth, input handling, external APIs, or data persistence.

---

## Test Architect

**File**: `agents/test-architect.md`
**Model**: Sonnet
**Color**: Orange

### What it does

Test Architect designs and writes comprehensive test suites. It surveys existing tests first to match the project's framework and style, then writes tests that verify behavior — not implementation details.

### When to spawn it manually

Normally `/implement` runs this at the end of a full implementation. Spawn manually if:
- You want tests for existing code that was never properly tested
- You're writing tests for someone else's implementation
- You want a test plan before writing implementation (TDD)

### How to invoke

```
Spawn a Test Architect agent.
Write tests for: src/auth/token.ts — specifically the validateToken and refreshToken functions.
The project uses Jest. Existing tests are in tests/auth/.
```

### What to expect

First, a test plan:

```
## Test Plan: Token Validation
Framework: Jest
Test files to create/modify:
- tests/auth/token.test.ts — validateToken and refreshToken coverage
Coverage targets:
- [ ] Happy path: valid JWT returns user object
- [ ] Edge case: expired JWT returns null
- [ ] Error case: malformed JWT returns null, does not throw
...
```

Then, the actual test file is written. Then a summary:

```
## Tests Written
- tests/auth/token.test.ts — 12 tests added
Coverage estimate: High — all public API surface covered
Not covered: concurrent refresh token scenarios (would require redis mock setup)
```

### Tips

- Test Architect matches existing test style. Give it the path to nearby test files if the style isn't obvious.
- "Test behavior, not implementation" is its core rule. Don't ask it to test private methods or internal state.
- It requires edge cases — null inputs, empty collections, boundary values — not just the happy path.

---

## Doc Agent

**File**: `agents/doc-agent.md`
**Model**: Haiku
**Color**: Cyan

### What it does

Doc Agent updates documentation to match code changes. It makes minimal, targeted updates — it does not rewrite docs, add unnecessary comments, or document things that don't need documentation. It also flags contradictions between docs and code.

### When to spawn it manually

Normally `/implement` runs this at the end of an implementation. Spawn manually if:
- You've made changes and want to ensure docs are consistent
- You suspect existing docs are out of date
- You've changed a public API and need the README updated

### How to invoke

```
Spawn a Doc Agent.
The following files changed: src/auth/token.ts (added refreshToken function), src/middleware/auth.ts (added token rotation logic).
Update any docs that reference token handling. Check README.md and docs/.
```

### What to expect

First, a plan:

```
## Doc Update Plan
Changed code: src/auth/token.ts, src/middleware/auth.ts
Docs to update:
- README.md — update Authentication section to mention token rotation
- docs/api.md — add refreshToken to the token management API docs
No update needed: CLAUDE.md (no build command changes)
```

Then, changes are made. Then a summary:

```
## Docs Updated
- README.md — updated Authentication section: added note about refresh token rotation
- docs/api.md — added refreshToken endpoint documentation
Contradictions found: docs/api.md:103 said tokens never expire — corrected
Memory updated: no
```

### Tips

- Doc Agent uses Haiku — it's a lightweight task and Haiku handles it well.
- Give it the list of changed files and the relevant doc directories. It will find what needs updating.
- It will not document internal implementation details. If you ask it to add JSDoc to every function, it will decline and document only non-obvious behavior.
- Pay attention to the "Contradictions found" section — it often surfaces docs that were silently wrong before your changes.

---

## Summary table

| Agent | Model | Spawned by | Manual use |
|---|---|---|---|
| Explorer | Sonnet | `/research` | Exploring unfamiliar code areas |
| Pattern Finder | Sonnet | `/research` | Finding project conventions |
| Plan Architect | Opus | `/draft-plan` | Planning sub-tasks |
| Implementer | Sonnet | `/implement` | Executing bounded changes |
| Security Reviewer | Sonnet | `/implement` | Reviewing existing code, PRs |
| Test Architect | Sonnet | `/implement` | Writing tests for existing code |
| Doc Agent | Haiku | `/implement` | Updating docs after changes |
