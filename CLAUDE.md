# Lindalë

A reusable multi-agent team framework. Defines role-based agents with lifecycle orchestration, tool scoping, and workflow automation.

## Project Philosophy

This repo is developed transparently as a teaching artifact. The issue tracker, commit history, and wiki document not just *what* was built but *why* — including dead ends, architectural pivots, and the reasoning behind decisions. Aspiring developers can follow the trail from first principles to working system.

## Team Roles

Each role is defined in `.claude/agents/<role>.md` — that file is the source of truth for the role's description, tool access, and constraints. See agent files for details.

## Issue Conventions

### Prefixes
- **DX**: Developer experience and framework improvements
- **FEAT**: New features and functionality
- **BUG**: Bug fixes
- **EPIC**: Large initiatives spanning multiple issues
- **DOCS**: Documentation improvements
- **INFRA**: Infrastructure and tooling

### Conventions
- Issue titles use prefix format: `PREFIX-NNN: Title` (e.g., `DX-001: ...`)
- Agents sign issue comments with their role (e.g., "-Claude TPM")
- Agents do NOT sign chat responses

## File Structure

```
ai-lindale/
├── CLAUDE.md              # This file — project context for agents
├── README.md              # Public-facing project description
├── .claude/
│   ├── agents/            # Agent definitions (frontmatter + system prompts)
│   │   ├── architect.md
│   │   ├── dev.md
│   │   └── tpm.md
│   ├── commands/          # Slash commands that invoke agents
│   │   ├── architect.md
│   │   ├── autodev.md     # TPM-driven ticket lifecycle orchestration
│   │   ├── dev.md
│   │   └── tpm.md
│   └── settings.local.json
├── docs/
│   └── adoption-guide.md  # Downstream adoption guide
├── memory/
│   ├── MEMORY_INDEX.md    # Index of all topic files
│   └── *.md               # Topic-scoped memory files
├── scripts/
│   ├── install.sh         # Downstream install via git submodule
│   ├── sync.sh            # Downstream sync/update helper
│   └── tests/
│       └── test-adoption.sh
└── templates/
    ├── sme.md             # Meta-template for TPM-generated domain SME
    ├── sme-bootstrap.md   # Bootstrap procedure for SME generation
    └── team-config.yml    # Role overrides and project customization
```

## Security Boundary

**The container is the boundary** (EPIC-004). Agents run with full permissions inside an isolated container; moat injects credentials at the network layer, so tokens never enter the agent's environment. Role constraints in agent prompts are behavioral guidance, not enforcement.

Optional layers on top:
- **Sandbox mode** — session-level filesystem/network boundaries when running on bare metal
- **Worktree isolation** — Dev agent works in a separate git worktree (workspace hygiene, not security)

## Memory

Agent memory lives in `memory/` within the repo — never in `~/.claude/` or outside the working directory.

- `MEMORY_INDEX.md` — index of all topic files (keep concise)
- Small topic files by subject (e.g., `decisions.md`, `patterns.md`)
- Agents read/write memory using `Read`/`Write`/`Edit` on `memory/` files directly
- All memory is version controlled and reviewable

**Security rule:** Agents must never read or write outside the working directory for memory or any other purpose.

## Agent Behavior Principles

### Retry and Loop Detection

**Autoretry is expected behavior.** Transient failures (network errors, API rate limits, git conflicts) are normal. Agents should retry with backoff, not panic on first failure. Everything fails all the time — design for it.

**But detect insanity loops.** If the same operation fails the same way 3+ times, the agent MUST stop retrying and change approach — try an alternative method, escalate to the user, or park the work (DX-011). Repeating a failing operation identically is never the right move. Leave breadcrumbs (in task descriptions, issue comments, or memory) so you or another agent can recognize "this was already tried and failed."

The guard rails: `maxTurns` (DX-029) provides a hard ceiling, but agents should self-regulate well before hitting it.

## Development Workflow

This repo develops the framework itself. To test changes:
1. Modify agent definitions in `.claude/agents/`
2. Launch with `claude --agent tpm` (or `./lindale` when available)
3. Use `/autodev` in a TPM tab to run the full ticket lifecycle end-to-end
4. Downstream testing: apply changes to a downstream install (e.g. catalyst-build) and verify

**Note:** Slash commands (`/tpm`, `/dev`, `/architect`) load the agent's system prompt into the current session; `--agent` launches a dedicated session as that agent. Both are prompt-level role adoption — enforcement comes from the container boundary, not the invocation path.

## Current Status

**Pre-alpha.** Framework is extracted from [aistrologer](https://github.com/grinnellian/aistrologer) and lives here.
Agents are defined, adoption tooling (`scripts/install.sh`, `scripts/sync.sh`) works. See issue tracker for ongoing
work.

**Architecture:** Container-as-boundary with vendored [moat](https://github.com/majorcontext/moat) for credential
injection. Previous hook-based enforcement was retired — see [Architecture Overview](../../wiki/Architecture-Overview)
and EPIC-004 (#69) for the pivot rationale. See [ACKNOWLEDGMENTS](ACKNOWLEDGMENTS.md) for upstream attribution.
