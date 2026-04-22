#!/usr/bin/env bash
# Lindalë framework installer.
# Creates symlinks from project locations into the .ai-lindale/ submodule.
# Run from the project root after adding the submodule.
#
# Self-host detection (INFRA-005 symlink-boundary design):
#   If core agent files (.claude/agents/architect.md etc.) already exist as
#   regular files — not symlinks — this script is running inside the framework
#   repo itself.  Symlinking would destroy the source files, so the symlink
#   pass is skipped.  Scaffolding (team-config.yml, CLAUDE.md) still runs.
#
# Flags:
#   --force   Override self-host detection and force symlink creation.
#             Use when a downstream project has manually-created agent files
#             that should be replaced by framework-managed symlinks.
#
# NOTE (INFRA-001 #23): when the framework/ restructure lands and paths
# change, update only the symlink targets — is_self_host detection paths stay
# the same.

set -euo pipefail

# --- Flag parsing ---
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    *) echo "Error: unknown option: $arg"; exit 1 ;;
  esac
done

FRAMEWORK_DIR=".ai-lindale"

# --- Self-host detection (INFRA-005) ---
# Returns 0 (true) if we are inside the framework repo itself.
# Heuristic: any core agent file exists as a regular file (not a symlink).
# Regular file == source of truth == self-dev mode; symlink == downstream consumer.
is_self_host() {
  for agent in architect tpm dev; do
    local path=".claude/agents/${agent}.md"
    if [ -f "$path" ] && [ ! -L "$path" ]; then
      return 0  # regular file found — self-host
    fi
  done
  return 1  # no regular agent files found — downstream project
}

# Guard: framework submodule must exist
if [ ! -d "$FRAMEWORK_DIR" ]; then
  echo "Error: $FRAMEWORK_DIR/ not found."
  echo "Add the framework submodule first:"
  echo "  git submodule add https://github.com/grinnellian/ai-lindale.git .ai-lindale"
  exit 1
fi

# --- Self-host gate ---
SELF_HOST=false
if [ "$FORCE" = false ] && is_self_host; then
  SELF_HOST=true
  echo "Self-host mode detected: core agent files are regular files, not symlinks."
  echo "Skipping symlink creation — scaffolding config files only."
  echo "To force symlinking anyway, re-run with: install.sh --force"
fi

# Create target directories
mkdir -p .claude/agents .claude/commands scripts/hooks

# Symlink core agents, commands, and hooks — skipped in self-host mode
if [ "$SELF_HOST" = false ]; then
  # Symlink core agents (only framework-managed roles)
  for agent in architect tpm dev; do
    src="../../${FRAMEWORK_DIR}/.claude/agents/${agent}.md"
    dest=".claude/agents/${agent}.md"
    if [ -f "$FRAMEWORK_DIR/.claude/agents/${agent}.md" ]; then
      ln -sf "$src" "$dest"
      echo "  linked $dest"
    fi
  done

  # Symlink core commands
  for cmd in architect tpm dev; do
    src="../../${FRAMEWORK_DIR}/.claude/commands/${cmd}.md"
    dest=".claude/commands/${cmd}.md"
    if [ -f "$FRAMEWORK_DIR/.claude/commands/${cmd}.md" ]; then
      ln -sf "$src" "$dest"
      echo "  linked $dest"
    fi
  done

  # Symlink hook scripts
  if [ -d "$FRAMEWORK_DIR/scripts/hooks" ]; then
    for hook in "$FRAMEWORK_DIR"/scripts/hooks/*.sh; do
      [ -f "$hook" ] || continue
      basename=$(basename "$hook")
      src="../../${FRAMEWORK_DIR}/scripts/hooks/${basename}"
      dest="scripts/hooks/${basename}"
      ln -sf "$src" "$dest"
      echo "  linked $dest"
    done
  fi
fi

# Scaffold team-config.yml from template if absent
if [ ! -f .claude/team-config.yml ]; then
  if [ -f "$FRAMEWORK_DIR/templates/team-config.yml" ]; then
    cp "$FRAMEWORK_DIR/templates/team-config.yml" .claude/team-config.yml
    echo "  created .claude/team-config.yml (customize for your project)"
  fi
fi

# Scaffold CLAUDE.md from template if absent
if [ ! -f CLAUDE.md ]; then
  if [ -f "$FRAMEWORK_DIR/templates/CLAUDE.md" ]; then
    cp "$FRAMEWORK_DIR/templates/CLAUDE.md" CLAUDE.md
    echo "  created CLAUDE.md (customize for your project)"
  fi
fi

# Create linglink README
cat > .claude/README.md << 'LINGLINK'
# .claude/ structure

Core agents (architect, tpm, dev) are symlinked from the Lindalë
framework (.ai-lindale/). Do not edit them here — edit the framework repo.

Project-specific agents (e.g. <domain>-sme) are real files
owned by this project.

To update the framework:

```bash
git submodule update --remote .ai-lindale
```
LINGLINK
echo "  created .claude/README.md (linglink)"

echo ""
echo "Framework installed. Run /architect, /tpm, or /dev to start."
echo "See .ai-lindale/docs/adoption-guide.md for full documentation."
