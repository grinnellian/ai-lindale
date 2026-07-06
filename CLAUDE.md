# Lindalë

A reusable multi-agent team framework. Defines role-based agents with lifecycle orchestration, tool scoping, and workflow automation.

## Project Philosophy

This repo is developed transparently as a teaching artifact. The issue tracker, commit history, and wiki document not just *what* was built but *why* — including dead ends, architectural pivots, and the reasoning behind decisions. Aspiring developers can follow the trail from first principles to working system.

### Teaching factory, not dark factory

Agent-driven development spans a spectrum: vibe coding (prompt, accept, ship, understand little) at one end, the "dark factory" (lights-out automation nobody reads) at the other. Lindalë sits deliberately between — a *teaching factory*. Agents plan, implement, and review real tickets, but the walls are glass: every decision lands in an issue, a signed comment, or a memory file that a human or the next agent can audit.

The operator model assumes an experienced engineer who *could* review every line and chooses when to — management, not vibes. The trap to avoid is the Zoolander fallacy: output that *looks* almost-finished is not the same as work that is understood, integrated, and owned.

Design principle: **observable by default, autonomous when desired.** The downstream [catalyst-build](https://github.com/Glurby/catalyst-build) history shows the transition in practice — from vibe-coded beginnings to disciplined ticket-lifecycle development.

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

### Branch Naming (DX-012)

Issue branches follow `<type>/<PREFIX>-<NNN>-<short-description>` (e.g.
`dx/DX-012-branch-naming`, `feat/FEAT-042-chart-rendering`,
`fix/BUG-017-null-transit`). EPIC issues are not branchable — decompose
into sub-issues first. See `.claude/agents/dev.md` for the full
convention, `scripts/validate-branch-name.sh` for validation, and
`scripts/check-file-overlap.sh` plus the Merge Ordering Strategy in
`dev.md` for coordinating parallel worktree dispatches. These are
advisory scripts, not PreToolUse hooks — see Security Boundary above.

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

**Architecture:** Container-as-boundary with [moat](https://github.com/majorcontext/moat) (pinned binary, vendoring
deferred to M3) for credential injection. Previous hook-based enforcement was retired — see
[Architecture Overview](../../wiki/Architecture-Overview) and EPIC-004 (#69) for the pivot rationale. See
[ACKNOWLEDGMENTS](ACKNOWLEDGMENTS.md) for upstream attribution.

## Where project state lives

**Milestones (GitHub):** [M0 Housekeeping](https://github.com/grinnellian/ai-lindale/milestone/1),
[M1 Moat Foundation](https://github.com/grinnellian/ai-lindale/milestone/2),
[M2 lindale CLI](https://github.com/grinnellian/ai-lindale/milestone/3),
[M3 k10s MVP](https://github.com/grinnellian/ai-lindale/milestone/4). M1 is the current critical path;
M0 runs in parallel.

**Wiki (authoritative for narrative state):**
- [Roadmap](../../wiki/Roadmap) — milestone breakdown and sequencing
- [Vision](../../wiki/Vision) — what Lindalë is for ("safe for the native vibecoder")
- [Architecture Overview](../../wiki/Architecture-Overview) — the stack
- [Architecture Decisions](../../wiki/Architecture-Decisions) — ADRs (numbered, append-only)
- [Operator's Guide](../../wiki/Operators-Guide) — for humans driving the team (intentionally not in `docs/`)
- [Tech Tree](../../wiki/Tech-Tree), [Issue Map](../../wiki/Issue-Map) — dependency graph and grouped backlog

**In-repo (authoritative for working state):** `memory/decisions.md`, `memory/patterns.md`, `memory/vision.md` —
agent-readable. New architectural decisions land in `memory/decisions.md` first; promote to a wiki ADR when stable.

**TPMs: when status questions arise, check milestones and the wiki Roadmap first.** Don't recreate roadmap content
in-repo — keep `docs/` for adoption-facing material (install, troubleshooting), wiki for direction and reasoning.
