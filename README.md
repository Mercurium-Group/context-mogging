# context-mogging

A context engineering system for [Claude Code](https://claude.ai/claude-code). It gives Claude a structured pipeline — Research → Plan → Implement → Checkpoint — so complex coding tasks stay on track across long sessions.

---

## What is this?

When you ask an AI coding assistant to build something non-trivial, a few things tend to go wrong: it forgets decisions made earlier in the conversation, it starts implementing before fully understanding the problem, and it loses track of what was agreed when the context gets long.

Context mogging is a set of slash commands, sub-agents, and memory templates that address these problems. Install it into any project and Claude Code gets a structured workflow baked in — one that keeps knowledge in the right place, delegates focused tasks to specialized agents, and checkpoints progress so nothing is lost.

---

## Why does it exist?

AI assistants are powerful but they work best when they operate within structure. Without it:

- Claude starts coding immediately, before understanding the full picture
- Decisions made at the start of a session are forgotten by the end
- The assistant improvises when it hits an ambiguous situation, sometimes wrong
- Long sessions become slow and unreliable as the context fills up

Context mogging solves this by making the workflow explicit. Research happens before planning. Planning happens before implementation. Implementation checks in with tests and a security scan after every phase. When the context gets heavy, there's a safe path to compact it without losing what matters.

---

## How it works

```
/research [topic]
      │
      ▼
  Explorer agents read the codebase and synthesize findings
  → saves artifact to thoughts/shared/research/
      │
      ▼
/plan [task]
      │
      ▼
  Plan Architect turns research into a phase-by-phase plan
  → saves to thoughts/shared/plans/, presents for review
      │
      ▼
/implement [plan-path]
      │
      ▼
  Implementer executes one phase at a time
  → tests run after each phase
  → Security Reviewer scans each phase
  → Test Architect + Doc Agent run at the end
      │
      ▼
/checkpoint
      │
      ▼
  Tests pass → commit → update memory → ready for next task
```

Each step is a checkpoint. Nothing moves forward until the previous step is clean.

---

## Install

**Method 1: npm/npx** (Node.js 18+)

```bash
npx context-mogging init
```

**Method 2: curl** (any system with bash)

```bash
curl -fsSL https://raw.githubusercontent.com/Mercurium-Group/context-mogging/main/install.sh | bash
```

**Method 3: git clone**

```bash
git clone https://github.com/Mercurium-Group/context-mogging.git
cd context-mogging
bash install.sh
```

All three methods install the same files. The installer auto-detects your project name, description, repo URL, package manager, and build commands from `package.json`, `Cargo.toml`, `go.mod`, or `pyproject.toml`. It then writes a pre-filled `CLAUDE.md` — search for `TODO:` to finish any fields it couldn't detect automatically.

---

## Quick start

After installing, open Claude Code in your project directory.

**1. Review your CLAUDE.md**

The installer auto-detects your project name, repo URL, package manager, and build commands. Open `CLAUDE.md` and search for `TODO:` — those are the fields it couldn't auto-detect (typically naming conventions, architecture boundaries, and error types). For most projects you'll only need to fill in 2–4 items.

**2. Check your setup**

```
/status
```

This shows your current branch, recent commits, active artifacts, and context health.

**3. Research before you build**

```
/research authentication flow
```

Claude spawns read-only Explorer agents that map the relevant code. Findings are saved to `thoughts/shared/research/`.

**4. Turn research into a plan**

```
/plan add OAuth login
```

The Plan Architect (running on Opus for better planning quality) produces a phase-by-phase plan. It gets saved and presented for your review. You edit it if anything is off.

**5. Execute the plan**

```
/implement thoughts/shared/plans/add-oauth-login.md
```

Claude works through the plan one phase at a time. Tests run after each phase. A security scan happens automatically. If anything fails, it stops and tells you exactly what broke.

**6. Commit clean work**

```
/checkpoint
```

Tests run one more time. If they pass, changes are committed and memory is updated. If they fail, nothing is committed.

**When things get slow**

```
/save-session
```

This prepares a preservation list (active plan state, unresolved issues, key decisions), writes anything important to memory, then guides you through Claude's built-in `/compact` so nothing critical is lost.

---

## Commands

| Command | What it does |
|---|---|
| `/research [topic]` | Explores the codebase, synthesizes findings into a research artifact |
| `/plan [task]` | Creates a phase-by-phase implementation plan for human review |
| `/implement [path]` | Executes a plan phase by phase, with tests and security review at each step |
| `/checkpoint [message]` | Runs tests, commits passing changes, updates memory |
| `/status` | Reports pipeline state, active artifacts, git status, context health |
| `/save-session` | Prepares for context compaction — writes memory, builds preservation list |
| `/metrics [--since Nd]` | Displays pipeline health dashboard from event logs and git history |

---

## What gets installed

```
your-project/
├── CLAUDE.md                        ← governance template (auto-filled; search TODO: for remaining items)
├── .claude/
│   ├── CLAUDE.md                    ← local overrides (gitignored)
│   ├── commands/                    ← the 7 slash commands above
│   ├── agents/                      ← 7 specialized sub-agents
│   ├── skills/                      ← 3 skills (git workflow, testing patterns, error handling)
│   └── settings.json                ← hooks configuration (merged with existing settings)
├── memory/
│   └── core.md                      ← persistent memory: ADRs, conventions, known issues
└── thoughts/
    └── shared/
        ├── research/                ← timestamped research artifacts
        ├── plans/                   ← implementation plans
        └── logs/                    ← session logs (events.jsonl written by hooks)
```

The `memory/` and `thoughts/` directories are gitignored by default. They're for Claude's working memory and session artifacts, not for committing.

---

## How this was built

Context mogging was built using Claude Code itself, guided by research into context engineering for AI agents.

The key ideas come from:

- **[12-Factor Agents](https://github.com/humandotai/12-factor-agents)** by Dario Amodei / the Anthropic team — a set of principles for building reliable LLM-powered agents, including "own your context window", "compact/consolidate context regularly", and "don't let agents go off-script"
- **Claude Code's native capabilities** — sub-agents, slash commands, skills, and hooks are all first-class features of Claude Code. This project wires them together into a pipeline rather than inventing new infrastructure.

The build itself followed the same pipeline described here: each phase was researched before being planned, each plan was reviewed before being implemented, and each session was kept within 40-60% context to avoid degradation. Four sessions, one phase pair each, with a fresh context for every session.

The system is intentionally transparent about this. If you're curious about context engineering principles, see [docs/context-engineering.md](docs/context-engineering.md).

---

## Contributing

The project is structured so each component is easy to modify:

- **Commands** live in `commands/` — plain markdown files with YAML frontmatter
- **Agents** live in `agents/` — same format, richer instructions
- **Skills** live in `skills/{name}/SKILL.md`
- **Templates** live in `templates/` — copied into new projects by the installer

To change how a command works, edit its `.md` file. The changes take effect immediately in Claude Code (no rebuild step).

To contribute:

1. Fork the repo
2. Make your changes
3. Test by running `node bin/install.js` in a clean directory
4. Open a PR with a description of what changed and why

Issues and discussion welcome at [github.com/Mercurium-Group/context-mogging/issues](https://github.com/Mercurium-Group/context-mogging/issues).
