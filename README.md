# claude-team

A reusable multi-agent team framework for Claude Code. Define role-based agents with lifecycle orchestration, tool scoping, and workflow automation — then instantiate them toward any project.

## Vision

Most software teams have specialized roles: architects who plan, PMs who track, developers who build, domain experts who advise. This framework brings that structure to Claude Code, giving each role:

- **Isolated context** — agents don't bleed into each other
- **Scoped permissions** — architects can't edit code, developers can't create issues
- **Lifecycle orchestration** — tickets flow through a state machine (review → plan → implement → verify)
- **Parallel execution** — multiple agents work simultaneously on independent tasks

## Status

**Pre-alpha.** Currently being prototyped inside [aistrologer](https://github.com/grinnellian/aistrologer) (see [DX-015](https://github.com/grinnellian/aistrologer/issues/88)). Will be extracted into this repo once patterns stabilize.

## Planned Architecture

```
claude-team/
├── agents/              # Role definitions (.claude/agents/*.md format)
│   ├── architect.md     # Read-only, creates implementation plans
│   ├── tpm.md           # Issue management, requirements, tracking
│   ├── dev.md           # Full write access, worktree isolation, TDD
│   ├── consultant.md    # Domain SME, read-only + GH comments
│   └── orchestrator.md  # Lifecycle state machine, dispatches to roles
├── hooks/               # PreToolUse enforcement scripts
│   ├── enforce-write-paths.sh
│   ├── bash-allowlist.sh
│   └── block-sensitive-files.sh
├── templates/           # Project-specific customization templates
│   └── team-config.yml  # Role overrides, domain expert specialization, etc.
└── docs/
    └── lifecycle.md     # Ticket state machine documentation
```

## Key Design Decisions

### Direct & Orchestrated Modes
Each agent works in two modes:
- **Direct:** User opens a tab, runs `/architect` — that tab *is* the Architect
- **Orchestrated:** User tells an orchestrator "work on these 5 tickets" — orchestrator spawns agents as subagents

### Enforcement Layers
1. `disallowedTools` — prompt-enforced tool restrictions (soft)
2. PreToolUse hooks — shell scripts that block unauthorized operations (hard, exit code 2)
3. Sandbox mode — session-level filesystem/network boundaries
4. MCP server scoping — per-agent external service access

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

## Instantiation

The goal is that any project can adopt this framework by:
1. Copying `agents/` and `hooks/` into their `.claude/` directory
2. Customizing `team-config.yml` for project-specific roles (e.g., replacing "Astrology Consultant" with "Security Reviewer")
3. Running `/orchestrator` or individual role commands

## Related

- Prototyped in: [aistrologer](https://github.com/grinnellian/aistrologer)
- Claude Code docs: [Subagents](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- Future: [Claude Agent SDK](https://docs.anthropic.com/en/docs/agents/agent-sdk) for persistent multi-agent systems

## License

MIT
