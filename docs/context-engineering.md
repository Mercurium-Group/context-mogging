# Context Engineering — Patterns Reference

This document explains the key ideas behind how context-mogging is designed. You don't need to read this to use the system — it's here if you want to understand why it works the way it does.

---

## The Core Problem

AI coding assistants run inside a context window. Everything the model "knows" during a session is what's currently in that window: your conversation, the files it has read, the outputs of previous tool calls, and its instructions.

When the context is small and fresh, the model is accurate and focused. As the context grows — through long conversations, many file reads, and accumulated outputs — two things happen:

1. **Quality degrades.** The model has to pay attention to more things at once, and things earlier in the context get less weight.
2. **Decisions get lost.** A decision made at the start of a session is essentially forgotten by the end if it wasn't explicitly written down.

Context engineering is the practice of managing this window deliberately: what goes in, what gets written out, and when to reset.

---

## The Smart Zone

The "Smart Zone" is a heuristic for context health:

```
0%          40%        60%         100%
|-----------|==========|------------|
  too empty  sweet spot  getting heavy
```

- **Below 40%**: The model has plenty of room. Work freely.
- **40–60%**: The sweet spot. You have enough history to be coherent, not so much that quality degrades.
- **Above 60%**: Start preparing for compaction. Finish the current task, write anything important to memory, then compact.
- **Above 80%**: Quality starts to drop noticeably. Compact before starting anything new.

The `/status` command reports context health. The `/compact` command prepares you to reset safely.

---

## The Compaction Hierarchy

When context gets heavy, you need to decide what to keep and what to discard. Not everything is equally important:

### Tier 1: Always survives (written to memory or files before compaction)
- Architectural decisions (ADRs)
- Project conventions established this session
- Build/test/deploy command changes
- Known issues and their current status

### Tier 2: Survives via artifacts (files in `thoughts/shared/`)
- The active implementation plan (file path + current phase)
- Research findings (the artifact file, not the full agent outputs)
- Current working state (branch, test status, uncommitted changes)

### Tier 3: Discarded (session-specific, can be reconstructed)
- The full conversation history
- Raw agent output logs
- Files that were read during exploration
- Intermediate reasoning steps

The `/compact` command handles this hierarchy: it writes Tier 1 items to `memory/core.md`, identifies Tier 2 artifacts by path, and builds a preservation hint for Claude's built-in `/compact` command.

---

## 12-Factor Agents Principles

The [12-Factor Agents](https://github.com/humandotai/12-factor-agents) framework provides a set of design principles for building reliable LLM-based systems. Context-mogging applies several of them directly:

### 1. Own your context window

> "Don't let the framework decide what goes into context. Curate it deliberately."

Applied here: The `/implement` command explicitly loads only three things — the plan file, `CLAUDE.md`, and `memory/core.md`. It does not browse the codebase or load research artifacts. The plan is supposed to be complete enough that no additional context is needed.

### 2. Compact and consolidate regularly

> "Long contexts degrade quality. Regularly summarize and compress."

Applied here: The `/compact` command exists specifically for this. It's designed to be run between tasks, not as a recovery tool. The `/checkpoint` command also assesses context weight after committing and suggests `/compact` when appropriate.

### 3. Don't improvise — surface ambiguity

> "When an agent hits an ambiguous situation, it should stop and ask, not guess."

Applied here: The Implementer agent is explicitly instructed not to improvise. If the plan is ambiguous, it surfaces the ambiguity to the user. The `/implement` command stops if tests fail, rather than attempting self-repair. The Plan Architect is required to list Open Questions before a plan is saved.

### 4. Separate planning from execution

> "Don't let the agent plan and implement in the same pass."

Applied here: `/research`, `/plan`, and `/implement` are separate commands. The plan is saved to a file and reviewed by a human before implementation begins. This creates a natural checkpoint where wrong assumptions can be caught.

### 5. Use specialized agents for isolated tasks

> "A single agent trying to do everything is less reliable than specialized agents with narrow scope."

Applied here: Explorer (read-only), Plan Architect (planning only), Implementer (execution only), Security Reviewer (security only), Test Architect (tests only), Doc Agent (docs only), Pattern Finder (conventions only). Each agent has a specific mandate and is prevented by its instructions from doing work outside that mandate.

### 6. Structured output over prose

> "Require structured output from agents. It's easier to validate and pass between systems."

Applied here: Every agent has a required output format. Explorer always produces Files Found / Key Patterns / Information Flow / Raw Notes. Security Reviewer always produces Critical / Warning / Passed sections. This makes agent output predictable and easy for the orchestrating command to act on.

---

## The Three-Layer Memory Architecture

Context-mogging uses three layers of memory with different lifetimes and purposes:

### Layer 1: Core memory (`memory/core.md`)
**Lifetime**: Permanent (committed to git)
**Purpose**: Durable, project-wide knowledge
**Contents**: Project identity, build/test commands, architectural decisions (ADRs), established conventions, known issues, rejected alternatives

Updated by: `/checkpoint` (when architecture changes), `/compact` (before session ends)

### Layer 2: Artifacts (`thoughts/shared/`)
**Lifetime**: Session-to-session (gitignored, but persists on disk)
**Purpose**: Working memory between commands in the same pipeline run
**Contents**: Research artifacts, implementation plans, session logs

Used by: `/plan` reads the latest research artifact; `/implement` reads the plan file

### Layer 3: Session context (the conversation window)
**Lifetime**: Current session only
**Purpose**: Working through a specific task
**Contents**: The current conversation, files read this session, agent outputs

Managed by: `/compact`, Claude's built-in `/compact`

The key discipline: anything important that lives only in Layer 3 at the end of a session is lost. The pipeline is designed to push important knowledge up to Layer 1 or Layer 2 before compaction.

---

## Why Sub-Agents?

Spawning a sub-agent does more than just keep the main context clean — it creates isolation:

- **Explorer** can read hundreds of lines of code without polluting the main conversation
- **Plan Architect** can reason at length about alternatives without that reasoning cluttering the implementation phase
- **Security Reviewer** reaches isolated conclusions without being influenced by the implementer's framing
- **Test Architect** designs tests without knowledge of how the feature was implemented (which produces better behavioral tests)

The main context window should contain: instructions, decisions, and summaries. The detailed work — reading files, reasoning through options, writing code — belongs in agents.

---

## Further Reading

- [12-Factor Agents](https://github.com/humandotai/12-factor-agents) — the principles this system is built on
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) — sub-agents, slash commands, hooks, skills
- [docs/phase-guide.md](phase-guide.md) — how each pipeline phase works in detail
- [docs/agent-guide.md](agent-guide.md) — when to use which agent
