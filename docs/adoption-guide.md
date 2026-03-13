# Adoption Guide

How to adopt the Ainulindale agent framework in a downstream project.

## Prerequisites

- Git 2.20+
- [Claude Code](https://claude.com/claude-code) CLI installed
- The framework repo: `https://github.com/grinnellian/ai-lindale.git`

## Initial Adoption

Five commands to get started:

```bash
# 1. Add the framework as a git submodule
git submodule add https://github.com/grinnellian/ai-lindale.git .ai-lindale

# 2. Run the install script to create symlinks
bash .ai-lindale/scripts/install.sh

# 3. Customize the project config (scaffolded by install.sh)
$EDITOR .claude/team-config.yml

# 4. Create your project CLAUDE.md if you don't have one
# (See the framework's CLAUDE.md for an example)

# 5. Commit everything
git add .ai-lindale .claude scripts/hooks .gitmodules
git commit -m "chore: adopt ai-lindale agent framework"
```

After this, `/architect`, `/tpm`, and `/dev` commands are available in Claude Code.

## Ongoing Sync

When the framework is updated upstream:

```bash
# Pull latest framework
git submodule update --remote .ai-lindale

# Symlinks already point into the submodule — no reinstall needed.
# If new agents or hooks were added upstream, re-run install:
bash .ai-lindale/scripts/install.sh

# Commit the submodule pointer update
git add .ai-lindale
git commit -m "chore: update ai-lindale framework"
```

Or use the convenience script:

```bash
bash scripts/sync.sh
```

## File Ownership

| Category | Owner | Sync | Location |
|----------|-------|------|----------|
| Core agents (architect, tpm, dev) | Framework | Symlink into submodule | `.claude/agents/` |
| Core commands | Framework | Symlink into submodule | `.claude/commands/` |
| Hook scripts | Framework | Symlink into submodule | `scripts/hooks/` |
| Domain SME | Project | Manual, never overwritten | `.claude/agents/` |
| team-config.yml | Project | Scaffolded once, never overwritten | `.claude/` |
| settings.local.json | Project | Manual | `.claude/` |
| CLAUDE.md | Project | Manual | repo root |
| Linglink README | Framework | Created by install.sh | `.claude/README.md` |
| Framework docs | Framework | Not exposed downstream | `.ai-lindale/docs/` |
| Framework memory | Framework | Not exposed downstream | `.ai-lindale/memory/` |

**Key insight:** The install boundary IS the context boundary. Only files symlinked into `.claude/` are visible to Claude Code at runtime. Framework internals (docs, memory, CLAUDE.md) stay in `.ai-lindale/` and don't bleed into your project's agent context.

## Adding a Project-Specific SME

1. Create `.claude/agents/<domain>-sme.md` as a real file (not a symlink)
2. Create `.claude/commands/<domain>-sme.md`
3. Set `sme.role_name` and `sme.domain_hint` in `team-config.yml`

This file is project-owned and will never be overwritten by framework updates.

## aistrologer-Specific Migration

For the [aistrologer](https://github.com/grinnellian/aistrologer) project:

### Files to Remove (replaced by framework symlinks)

- `.claude/agents/architect.md` — replaced by symlink
- `.claude/agents/tpm.md` — replaced by symlink
- `.claude/agents/dev.md` — replaced by symlink
- `.claude/commands/architect.md` — replaced by symlink
- `.claude/commands/tpm.md` — replaced by symlink
- `.claude/commands/dev.md` — replaced by symlink
- `scripts/hooks/*.sh` — replaced by symlinks

### Files to Keep (project-owned)

- `.claude/agents/sme.md` — project-specific domain SME (auto-specializes via boot loop)
- `.claude/commands/sme.md` — project-specific command
- `.claude/settings.local.json` — project-specific settings
- `memory/` — project-specific agent memory (not synced)
- `CLAUDE.md` — project-specific context

### Migration Steps

```bash
# 1. Remove framework-managed files (will be replaced by symlinks)
git rm .claude/agents/{architect,tpm,dev}.md
git rm .claude/commands/{architect,tpm,dev}.md
git rm -r scripts/hooks/ 2>/dev/null || true

# 2. Add framework submodule
git submodule add https://github.com/grinnellian/ai-lindale.git .ai-lindale

# 3. Install symlinks
bash .ai-lindale/scripts/install.sh

# 4. Update CLAUDE.md to reference the framework
# Add a note that core agents come from .ai-lindale/

# 5. Commit
git add -A
git commit -m "chore: migrate to ai-lindale framework"
```

### Issue Cross-References

aistrologer DX issues that were migrated to ai-lindale should reference the new issue numbers. Update any aistrologer issue comments that reference the old numbering.

## Troubleshooting

**Symlink target not found:**
Run `bash .ai-lindale/scripts/install.sh` after any submodule operation. Ensure `.ai-lindale/` is populated (`git submodule update --init`).

**Agent not loading in Claude Code:**
Verify `.claude/agents/*.md` symlinks resolve: `ls -la .claude/agents/`. Broken symlinks appear in red.

**Merge conflicts on submodule update:**
Only the submodule pointer (`.ai-lindale` entry in `.gitmodules`) should conflict. Accept the upstream version.

**Cloning a project that uses the framework:**
```bash
git clone --recurse-submodules <repo-url>
# or, if already cloned:
git submodule update --init
bash .ai-lindale/scripts/install.sh
```

## Future: npm Migration Path

When ready, the framework can be published as an npm package. The `postinstall` script does what `install.sh` does — symlinks from `node_modules/ai-lindale/` into `.claude/`. The linglink and ownership model don't change.
