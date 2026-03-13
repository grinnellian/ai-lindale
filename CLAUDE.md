# Ainulindalë

A reusable multi-agent team framework. Defines role-based agents with lifecycle orchestration, tool scoping, and workflow automation.

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
│   ├── hooks/             # PreToolUse enforcement scripts
│   │   ├── bash-allowlist.sh
│   │   ├── block-sensitive-files.sh
│   │   ├── enforce-write-paths.sh
│   │   └── tests/
│   │       └── test-hooks.sh
│   ├── install.sh         # Downstream install via git submodule
│   ├── sync.sh            # Downstream sync/update helper
│   └── tests/
│       └── test-adoption.sh
└── templates/
    ├── sme.md             # Meta-template for TPM-generated domain SME
    └── team-config.yml    # Role overrides and project customization
```

## Enforcement Layers

1. **disallowedTools** — prompt-enforced tool restrictions (soft)
2. **PreToolUse hooks** — shell scripts that block unauthorized operations (hard, exit code 2)
3. **Sandbox mode** — session-level filesystem/network boundaries
4. **Worktree isolation** — Dev agent works in separate git worktree

## Memory

Agent memory lives in `memory/` within the repo — never in `~/.claude/` or outside the working directory.

- `MEMORY_INDEX.md` — index of all topic files (keep concise)
- Small topic files by subject (e.g., `decisions.md`, `patterns.md`)
- Agents read/write memory using `Read`/`Write`/`Edit` on `memory/` files directly
- All memory is version controlled and reviewable

**Security rule:** Agents must never read or write outside the working directory for memory or any other purpose.

## Development Workflow

This repo develops the framework itself. To test changes:
1. Modify agent definitions in `.claude/agents/`
2. Test by invoking the agent via its slash command (e.g., `/tpm`)
3. Use `/autodev` in a TPM tab to run the full ticket lifecycle end-to-end
4. Validate hook scripts work correctly with the agent's tool usage
5. Downstream testing: apply changes to aistrologer and verify

## Current Status

**Pre-alpha.** Framework is extracted from [aistrologer](https://github.com/grinnellian/aistrologer) and lives here. Agents are defined, PreToolUse hooks are implemented, and adoption tooling (`scripts/install.sh`, `scripts/sync.sh`) works. See issue tracker for ongoing work.
