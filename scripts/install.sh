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
# Local override protection (BUG-007):
#   For each managed path, install.sh checks the current state:
#     - Missing            → link  (new symlink created)
#     - Correct symlink    → ok    (no-op, silent)
#     - Wrong symlink      → refreshed (re-linked with message)
#     - Regular file       → skipped  (printed warning; use --force to override)
#     - Directory          → error    (skipped defensively)
#
# Flags:
#   --force   Override self-host detection AND replace any regular-file local
#             overrides with framework-managed symlinks.  Use when you want to
#             discard all local customizations and re-baseline to framework
#             defaults.
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

# --- Counters ---
LINKED=0
OK=0
REFRESHED=0
SKIPPED=0
FORCED=0

# --- Per-path symlink decision (BUG-007) ---
# Args: $1 = src (relative link target), $2 = dest (project-root-relative path)
link_managed() {
  local src="$1"
  local dest="$2"

  if [ -L "$dest" ]; then
    local current
    current=$(readlink "$dest")
    if [ "$current" = "$src" ]; then
      OK=$((OK + 1))
      return 0
    fi
    ln -sf "$src" "$dest"
    echo "  refreshed $dest (was -> $current)"
    REFRESHED=$((REFRESHED + 1))
    return 0
  fi

  if [ -e "$dest" ]; then
    # Regular file (or directory) present
    if [ "$FORCE" = true ]; then
      rm -rf "$dest"
      ln -sf "$src" "$dest"
      echo "  forced $dest (replaced local file)"
      FORCED=$((FORCED + 1))
      return 0
    fi
    echo "  skipped $dest -- local override present (delete or re-run with --force to re-link)"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  ln -sf "$src" "$dest"
  echo "  linked $dest"
  LINKED=$((LINKED + 1))
}

# --- Self-host detection (INFRA-005) ---
# Returns 0 (true) if we are inside the framework repo itself.
# Heuristic: any core agent file exists as a regular file (not a symlink).
# Regular file == source of truth == self-dev mode; symlink == downstream consumer.
is_self_host() {
  local count=0
  for agent in architect tpm dev; do
    local path=".claude/agents/${agent}.md"
    if [ -f "$path" ] && [ ! -L "$path" ]; then
      count=$((count + 1))
    fi
  done
  # All three core agent files are regular files → framework source tree (self-host).
  # A single or partial real file is a downstream local override, not self-host.
  [ "$count" -eq 3 ]
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
      link_managed "$src" "$dest"
    fi
  done

  # Symlink core commands
  for cmd in architect tpm dev; do
    src="../../${FRAMEWORK_DIR}/.claude/commands/${cmd}.md"
    dest=".claude/commands/${cmd}.md"
    if [ -f "$FRAMEWORK_DIR/.claude/commands/${cmd}.md" ]; then
      link_managed "$src" "$dest"
    fi
  done

  # Symlink hook scripts
  if [ -d "$FRAMEWORK_DIR/scripts/hooks" ]; then
    for hook in "$FRAMEWORK_DIR"/scripts/hooks/*.sh; do
      [ -f "$hook" ] || continue
      basename=$(basename "$hook")
      src="../../${FRAMEWORK_DIR}/scripts/hooks/${basename}"
      dest="scripts/hooks/${basename}"
      link_managed "$src" "$dest"
    done
  fi

  echo ""
  echo "Summary: linked: $LINKED, ok: $OK, refreshed: $REFRESHED, skipped: $SKIPPED, forced: $FORCED"
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
