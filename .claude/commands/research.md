---
description: Research a topic by exploring the codebase. Spawns Explorer and Pattern Finder agents in parallel, then synthesizes findings into a timestamped artifact.
allowed-tools: Agent, Read, Glob, Grep, Bash, Write
model: claude-sonnet-4-6
argument-hint: "[topic or question to research]"
---

## /research $ARGUMENTS

You are running the **Research** phase of the context engineering pipeline.

### Step 1: Parse the request

Extract the research topic from `$ARGUMENTS`. If no argument was given, ask: "What should I research?"

### Step 2: Spawn Explorer agents

Spawn 2-3 Explorer agents in parallel, each focused on a different angle of the topic:
- One to map file structure and entry points
- One to trace data flow and key functions
- One for cross-cutting concerns (config, tests, types) — only if the topic warrants it

Also spawn Pattern Finder if this is an unfamiliar area of the codebase or the user is asking "how do we do X."

### Step 3: Synthesize findings

Collect all agent outputs. Synthesize into a research artifact — do not just concatenate the outputs. Identify the key insights, contradictions, and open questions.

Save the artifact to:
```
thoughts/shared/research/YYYY-MM-DD-HHmm-[slug].md
```
Where `[slug]` is a 3-5 word kebab-case summary of the topic (e.g., `auth-flow-overview`).

Create the directory if it doesn't exist: `mkdir -p thoughts/shared/research/`

### Step 4: Present summary

Print a brief summary (≤10 lines) of the key findings. Print the artifact path.

Then say:
> Research complete. Run `/plan [task description]` to create an implementation plan, or `/plan --from [artifact path]` to use this research directly.

### Context discipline

This command should use ≤40% of context when complete. If you find yourself loading many files directly, delegate to Explorer agents instead. The artifact is the output — keep the main context clean.

### Artifact format

```markdown
# Research: [Topic]
**Date**: YYYY-MM-DD HH:mm
**Scope**: [what was explored]

## Key Findings
[Numbered list of the most important discoveries]

## Relevant Files
[File paths with brief descriptions]

## Patterns Observed
[Any coding patterns relevant to this topic]

## Open Questions
[Things that need clarification or deeper investigation]

## Raw Agent Outputs
[Append full Explorer/Pattern Finder outputs here, separated by ---]
```
