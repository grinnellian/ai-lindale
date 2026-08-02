# Lindalë

A reusable multi-agent team framework. Define role-based agents with lifecycle orchestration, tool scoping, and workflow automation — then instantiate them toward any project.

## Vision

Most software teams have specialized roles: architects who plan, PMs who track, developers who build, domain experts who advise. This framework brings that structure to AI coding agents, giving each role:

- **Isolated context** — agents don't bleed into each other
- **Scoped permissions** — architects can't edit code, developers can't create issues
- **Lifecycle orchestration** — tickets flow through a state machine (review → plan → implement → verify)
- **Parallel execution** — multiple agents work simultaneously on independent tasks

## Status

**Pre-alpha.** Framework is extracted and lives here. Agents are defined and adoption tooling works. The security model is container-as-boundary (EPIC-004): agents run with full permissions inside an isolated container, with credentials injected at the network layer via [moat](https://github.com/majorcontext/moat). Active development ongoing.

## Architecture

```
ai-lindale/
├── .claude/
│   ├── agents/                      # Role definitions (frontmatter + system prompts)
│   │   ├── architect.md
│   │   ├── audit-repo.md
│   │   ├── dev.md
│   │   ├── researcher.md
│   │   └── tpm.md
│   ├── commands/                    # Slash commands that invoke agents
│   │   ├── architect.md
│   │   ├── audit-repo.md
│   │   ├── autodev.md               # TPM-driven ticket lifecycle orchestration
│   │   ├── dev.md
│   │   ├── handoff.md               # Engagement handoff walkthrough
│   │   ├── pr-refresh.md            # Open-PR queue reconciliation and rebase
│   │   ├── researcher.md
│   │   └── tpm.md
│   └── settings.local.json
├── docs/
│   ├── adoption-guide.md
│   ├── faq.md
│   ├── pod.md                        # Pod (the container agents live and work in) image docs
│   └── roadmap.md
├── infra/
│   └── pod-base/                     # Dockerfile + build assets for the pod container image
├── memory/
│   ├── MEMORY_INDEX.md
│   └── decisions.md
├── scripts/
│   ├── install.sh
│   ├── sync.sh
│   ├── validate-branch-name.sh
│   ├── check-file-overlap.sh
│   └── tests/*.sh
├── templates/
│   ├── sme.md                         # Meta-template for TPM-generated domain SME
│   ├── sme-bootstrap.md               # Bootstrap procedure for SME generation
│   ├── handoff-procedure.md
│   ├── standardization-playbook.md
│   └── team-config.yml
├── moat.yaml                         # moat run configuration (EPIC-004 credential injection)
├── CLAUDE.md
└── README.md
```

## Key Design Decisions

### Direct & Orchestrated Modes
Each agent works in two modes:
- **Direct:** User opens a tab, runs `/architect` — that tab *is* the Architect
- **Orchestrated:** User runs `/autodev` in a TPM tab — the TPM drives the full ticket lifecycle, spawning Architect and Dev as subagents via its `Agent` tool

### Security Boundary
The container is the boundary. Agents run with full permissions inside an isolated container; [moat](https://github.com/majorcontext/moat) injects credentials at the network layer, so tokens never enter the agent's environment. Role constraints in agent prompts are behavioral guidance, not enforcement. Sandbox mode and worktree isolation remain available as optional layers for bare-metal use.

### Ticket Lifecycle State Machine
```
OPEN → NEEDS_REVIEW → ARCH_PLANNED → IN_PROGRESS → READY_FOR_REVIEW → (human) ACCEPTED
         │                                              │
         └──── blocker? ──→ BLOCKED (comment on issue, move to next ticket)
```

### Escalation Protocol (User AFK)
When an agent hits a blocker and the user is unavailable:
1. Agent comments the blocker on the GitHub issue with full context
2. Agent labels the issue `blocked`
3. Orchestrator moves to the next ticket
4. Orchestrator surfaces a summary of all blocked items when user returns
5. Future: webhook/notification integration for urgent blockers

## Adoption

Any project can adopt this framework via git submodule:

```bash
# Add the framework as a submodule
git submodule add https://github.com/grinnellian/ai-lindale.git .ai-lindale

# Install symlinks into .claude/
bash .ai-lindale/scripts/install.sh

# Customize for your project
$EDITOR .claude/team-config.yml
```

Core agents and commands are symlinked from `.ai-lindale/` into their expected locations. Project-specific files (domain SME, `team-config.yml`, `CLAUDE.md`) are real files owned by the downstream project and never overwritten.

Updates are a single command: `git submodule update --remote .ai-lindale`

See [docs/adoption-guide.md](docs/adoption-guide.md) for the full guide including aistrologer migration steps.

## Roadmap

Project direction, milestones, and decisions live on the [wiki](https://github.com/grinnellian/ai-lindale/wiki):

- [Roadmap](https://github.com/grinnellian/ai-lindale/wiki/Roadmap) — milestones (M0–M3), current state, and where we're headed
- [Vision](https://github.com/grinnellian/ai-lindale/wiki/Vision) — what Lindalë is for
- [Architecture Overview](https://github.com/grinnellian/ai-lindale/wiki/Architecture-Overview) — the stack and how the pieces fit
- [Architecture Decisions](https://github.com/grinnellian/ai-lindale/wiki/Architecture-Decisions) — ADRs and the reasoning behind them
- [Operator's Guide](https://github.com/grinnellian/ai-lindale/wiki/Operators-Guide) — for humans driving the agent team

Active work is tracked in [GitHub milestones](https://github.com/grinnellian/ai-lindale/milestones) and the [Issue Map](https://github.com/grinnellian/ai-lindale/wiki/Issue-Map).

## Related

- Originally prototyped in: [aistrologer](https://github.com/grinnellian/aistrologer)
- Claude Code docs: [Subagents](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- Future: [Claude Agent SDK](https://docs.anthropic.com/en/docs/agents/agent-sdk) for persistent multi-agent systems

## License

MIT
