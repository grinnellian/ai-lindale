#!/usr/bin/env bash
# DX-007: Tests for install.sh and adoption workflow.
# Run from repo root: bash scripts/tests/test-adoption.sh

set -euo pipefail

PASS=0
FAIL=0
TMPDIR_BASE=""

# Capture repo root BEFORE any cd operations
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Helpers ---

setup_project() {
  # Create a temporary "downstream project" directory with a fake framework submodule
  TMPDIR_BASE=$(mktemp -d)
  PROJECT="$TMPDIR_BASE/project"
  mkdir -p "$PROJECT"
  cd "$PROJECT"
  git init --quiet

  # Simulate the framework submodule at .ai-lindale/
  FRAMEWORK="$PROJECT/.ai-lindale"
  mkdir -p "$FRAMEWORK/.claude/agents" "$FRAMEWORK/.claude/commands" "$FRAMEWORK/scripts/hooks" "$FRAMEWORK/templates"
  for agent in architect tpm dev; do
    cp "$REPO_ROOT/.claude/agents/${agent}.md" "$FRAMEWORK/.claude/agents/${agent}.md"
  done
  for cmd in architect tpm dev; do
    cp "$REPO_ROOT/.claude/commands/${cmd}.md" "$FRAMEWORK/.claude/commands/${cmd}.md"
  done

  # Create placeholder hook scripts
  echo '#!/bin/bash' > "$FRAMEWORK/scripts/hooks/bash-allowlist.sh"
  echo '#!/bin/bash' > "$FRAMEWORK/scripts/hooks/enforce-write-paths.sh"
  chmod +x "$FRAMEWORK/scripts/hooks/"*.sh

  # Copy templates
  cp "$REPO_ROOT/templates/team-config.yml" "$FRAMEWORK/templates/team-config.yml"
  cp "$REPO_ROOT/templates/CLAUDE.md" "$FRAMEWORK/templates/CLAUDE.md"

  # Copy install.sh
  cp "$REPO_ROOT/scripts/install.sh" "$FRAMEWORK/scripts/install.sh"
  chmod +x "$FRAMEWORK/scripts/install.sh"
}

teardown() {
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap teardown EXIT

assert_symlink() {
  local path="$1"
  local target="$2"
  if [ -L "$path" ]; then
    local actual
    actual=$(readlink "$path")
    if [ "$actual" = "$target" ]; then
      return 0
    else
      echo "    EXPECTED target: $target"
      echo "    ACTUAL target:   $actual"
      return 1
    fi
  else
    echo "    NOT a symlink: $path"
    return 1
  fi
}

assert_file_exists() {
  local path="$1"
  if [ -f "$path" ]; then
    return 0
  else
    echo "    File does not exist: $path"
    return 1
  fi
}

assert_file_not_symlink() {
  local path="$1"
  if [ -L "$path" ]; then
    echo "    Should NOT be a symlink: $path"
    return 1
  elif [ -f "$path" ]; then
    return 0
  else
    echo "    File does not exist: $path"
    return 1
  fi
}

assert_file_contains() {
  local path="$1"
  local pattern="$2"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    return 0
  else
    echo "    File $path does not contain: $pattern"
    return 1
  fi
}

run_test() {
  local name="$1"
  shift
  if "$@" 2>&1; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

# --- Tests ---

test_agent_symlinks() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  for agent in architect tpm dev; do
    assert_symlink ".claude/agents/${agent}.md" "../../.ai-lindale/.claude/agents/${agent}.md"
  done
}

test_command_symlinks() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  for cmd in architect tpm dev; do
    assert_symlink ".claude/commands/${cmd}.md" "../../.ai-lindale/.claude/commands/${cmd}.md"
  done
}

test_hook_symlinks() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  for hook in bash-allowlist.sh enforce-write-paths.sh; do
    assert_symlink "scripts/hooks/${hook}" "../../.ai-lindale/scripts/hooks/${hook}"
  done
}

test_preserves_project_files() {
  setup_project
  mkdir -p .claude/agents
  echo "# Project-specific SME" > .claude/agents/astrologer.md
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_not_symlink ".claude/agents/astrologer.md"
  assert_file_contains ".claude/agents/astrologer.md" "Project-specific SME"
}

test_creates_team_config_template() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_exists ".claude/team-config.yml"
  assert_file_not_symlink ".claude/team-config.yml"
}

test_does_not_overwrite_existing_config() {
  setup_project
  mkdir -p .claude
  echo "custom: true" > .claude/team-config.yml
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_contains ".claude/team-config.yml" "custom: true"
}

test_creates_linglink_readme() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_exists ".claude/README.md"
  assert_file_contains ".claude/README.md" "symlinked"
}

test_idempotent() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  bash "$FRAMEWORK/scripts/install.sh"
  # Should still work — no errors, symlinks valid
  for agent in architect tpm dev; do
    assert_symlink ".claude/agents/${agent}.md" "../../.ai-lindale/.claude/agents/${agent}.md"
  done
  assert_file_exists ".claude/team-config.yml"
}

test_missing_framework_dir() {
  local tmpdir
  tmpdir=$(mktemp -d)
  cd "$tmpdir"
  git init --quiet
  # No .ai-lindale/ exists — install.sh should fail

  if bash "$REPO_ROOT/scripts/install.sh" 2>/dev/null; then
    echo "    Should have exited with error"
    rm -rf "$tmpdir"
    return 1
  fi
  rm -rf "$tmpdir"
  return 0
}

test_symlinks_resolve() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  # Symlinks should resolve to readable files
  for agent in architect tpm dev; do
    if [ ! -r ".claude/agents/${agent}.md" ]; then
      echo "    Symlink does not resolve: .claude/agents/${agent}.md"
      return 1
    fi
  done
}

test_creates_starter_claude_md() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_exists "CLAUDE.md"
  assert_file_not_symlink "CLAUDE.md"
  assert_file_contains "CLAUDE.md" "Scaffolded by ai-lindale"
}

test_does_not_overwrite_existing_claude_md() {
  setup_project
  echo "# My existing project" > CLAUDE.md
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_contains "CLAUDE.md" "My existing project"
}

# --- self-host tests ---

# Helper: set up a self-host scenario.
# Requires setup_project + an initial install.sh run to have already happened (so symlinks exist),
# then replaces symlinked agent/command/hook files with regular files to simulate the framework repo.
setup_self_host() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  # Replace symlinks with regular files — this is the "framework source" state
  for agent in architect tpm dev; do
    rm -f ".claude/agents/${agent}.md"
    echo "# Self-host agent: ${agent}" > ".claude/agents/${agent}.md"
  done
  for cmd in architect tpm dev; do
    rm -f ".claude/commands/${cmd}.md"
    echo "# Self-host command: ${cmd}" > ".claude/commands/${cmd}.md"
  done
  if [ -L "scripts/hooks/bash-allowlist.sh" ]; then
    rm -f "scripts/hooks/bash-allowlist.sh"
    echo '#!/bin/bash' > "scripts/hooks/bash-allowlist.sh"
  fi
}

test_self_host_skips_symlinks() {
  setup_self_host
  bash "$FRAMEWORK/scripts/install.sh"
  # Core agent files must remain regular files — not overwritten with symlinks
  assert_file_not_symlink ".claude/agents/architect.md"
  assert_file_not_symlink ".claude/agents/tpm.md"
  assert_file_not_symlink ".claude/agents/dev.md"
  assert_file_not_symlink ".claude/commands/architect.md"
  assert_file_not_symlink "scripts/hooks/bash-allowlist.sh"
}

test_self_host_still_scaffolds() {
  setup_self_host
  # Remove scaffolded files to test re-scaffold
  rm -f .claude/team-config.yml CLAUDE.md
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_exists ".claude/team-config.yml"
  assert_file_exists "CLAUDE.md"
  assert_file_exists ".claude/README.md"
  # Agent files must still be regular files
  assert_file_not_symlink ".claude/agents/architect.md"
}

test_self_host_message() {
  setup_self_host
  output=$(bash "$FRAMEWORK/scripts/install.sh" 2>&1)
  if ! echo "$output" | grep -qi "self-host"; then
    echo "    Expected output to contain 'self-host', got:"
    echo "$output"
    return 1
  fi
  return 0
}

test_force_overrides_self_host() {
  setup_self_host
  bash "$FRAMEWORK/scripts/install.sh" --force
  # With --force, symlinks should have been (re)created even though regular files existed
  assert_symlink ".claude/agents/architect.md" "../../.ai-lindale/.claude/agents/architect.md"
}

# --- Guide completeness tests ---

test_guide_exists() {
  assert_file_exists "$REPO_ROOT/docs/adoption-guide.md"
}

test_guide_references_subtree_commands() {

  local guide="$REPO_ROOT/docs/adoption-guide.md"
  assert_file_contains "$guide" "git submodule"
  assert_file_contains "$guide" "install.sh"
}

test_guide_has_ownership_table() {

  assert_file_contains "$REPO_ROOT/docs/adoption-guide.md" "Owner"
}

test_guide_has_migration_section() {

  assert_file_contains "$REPO_ROOT/docs/adoption-guide.md" "aistrologer"
}

# --- local-override tests ---

# Helper: create a regular file at a managed path before install.sh runs.
# Args: $1 = path relative to PROJECT, $2 = content
setup_with_override() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  echo "$content" > "$path"
}

test_override_regular_file_skipped() {
  setup_project
  setup_with_override ".claude/agents/architect.md" "# local override"
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_not_symlink ".claude/agents/architect.md" &&
  assert_file_contains ".claude/agents/architect.md" "# local override" &&
  assert_symlink ".claude/agents/tpm.md" "../../.ai-lindale/.claude/agents/tpm.md" &&
  assert_symlink ".claude/agents/dev.md" "../../.ai-lindale/.claude/agents/dev.md"
}

test_override_skip_message() {
  setup_project
  setup_with_override ".claude/agents/architect.md" "# local override"
  output=$(bash "$FRAMEWORK/scripts/install.sh" 2>&1)
  if ! echo "$output" | grep -qi "skipped"; then
    echo "    Expected output to contain 'skipped', got:"
    echo "$output"
    return 1
  fi
  if ! echo "$output" | grep -q ".claude/agents/architect.md"; then
    echo "    Expected output to mention the skipped path, got:"
    echo "$output"
    return 1
  fi
}

test_correct_symlink_is_noop() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  # Second run — correct symlinks should not print "linked" again
  output=$(bash "$FRAMEWORK/scripts/install.sh" 2>&1)
  if echo "$output" | grep -q "  linked .claude/agents/architect.md"; then
    echo "    Second run should not re-link an already-correct symlink"
    echo "$output"
    return 1
  fi
  # Symlinks still correct
  assert_symlink ".claude/agents/architect.md" "../../.ai-lindale/.claude/agents/architect.md"
}

test_wrong_symlink_refreshed() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  # Replace correct symlink with a stale/wrong one
  rm ".claude/agents/architect.md"
  ln -s "../../some-other-target" ".claude/agents/architect.md"
  bash "$FRAMEWORK/scripts/install.sh"
  assert_symlink ".claude/agents/architect.md" "../../.ai-lindale/.claude/agents/architect.md"
}

test_force_overrides_regular_file() {
  setup_project
  setup_with_override ".claude/agents/architect.md" "# local override"
  bash "$FRAMEWORK/scripts/install.sh" --force
  assert_symlink ".claude/agents/architect.md" "../../.ai-lindale/.claude/agents/architect.md"
}

test_override_applies_to_commands_and_hooks() {
  setup_project
  setup_with_override ".claude/commands/dev.md" "# local command override"
  setup_with_override "scripts/hooks/bash-allowlist.sh" "#!/bin/bash\n# local hook override"
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_not_symlink ".claude/commands/dev.md" &&
  assert_file_contains ".claude/commands/dev.md" "# local command override" &&
  assert_file_not_symlink "scripts/hooks/bash-allowlist.sh"
}

test_summary_line() {
  setup_project
  # Pre-create one correct symlink for architect agent (will be ok after install)
  mkdir -p .claude/agents
  ln -s "../../.ai-lindale/.claude/agents/architect.md" ".claude/agents/architect.md"
  # Create a real-file override for tpm command (will be skipped)
  setup_with_override ".claude/commands/tpm.md" "# local tpm override"
  # Let dev agent and others be fresh-linked
  output=$(bash "$FRAMEWORK/scripts/install.sh" 2>&1)
  if ! echo "$output" | grep -qi "linked:"; then
    echo "    Expected summary line with 'linked:', got:"
    echo "$output"
    return 1
  fi
  if ! echo "$output" | grep -qi "skipped:"; then
    echo "    Expected summary line with 'skipped:', got:"
    echo "$output"
    return 1
  fi
  if ! echo "$output" | grep -qi "ok:"; then
    echo "    Expected summary line with 'ok:', got:"
    echo "$output"
    return 1
  fi
}

test_guide_documents_local_override() {
  assert_file_contains "$REPO_ROOT/docs/adoption-guide.md" "local override"
}

# --- Run all tests ---

echo "=== DX-007 Adoption Tests ==="
echo ""
echo "--- install.sh tests ---"
run_test "creates agent symlinks" test_agent_symlinks
run_test "creates command symlinks" test_command_symlinks
run_test "creates hook symlinks" test_hook_symlinks
run_test "preserves project-owned files" test_preserves_project_files
run_test "creates team-config.yml template" test_creates_team_config_template
run_test "does not overwrite existing config" test_does_not_overwrite_existing_config
run_test "creates linglink README" test_creates_linglink_readme
run_test "idempotent on re-run" test_idempotent
run_test "fails when framework dir missing" test_missing_framework_dir
run_test "symlinks resolve to readable files" test_symlinks_resolve
run_test "creates starter CLAUDE.md" test_creates_starter_claude_md
run_test "does not overwrite existing CLAUDE.md" test_does_not_overwrite_existing_claude_md
echo ""
echo "--- self-host tests ---"
run_test "self-host: skips symlinking core files" test_self_host_skips_symlinks
run_test "self-host: still scaffolds config files" test_self_host_still_scaffolds
run_test "self-host: prints detection message" test_self_host_message
run_test "self-host: --force overrides detection" test_force_overrides_self_host
echo ""
echo "--- guide completeness tests ---"
run_test "adoption guide exists" test_guide_exists
run_test "guide references submodule commands" test_guide_references_subtree_commands
run_test "guide has file ownership table" test_guide_has_ownership_table
run_test "guide has aistrologer migration section" test_guide_has_migration_section
echo ""
echo "--- local-override tests ---"
run_test "override: regular file is skipped, not clobbered" test_override_regular_file_skipped
run_test "override: skip prints path and 'skipped'" test_override_skip_message
run_test "override: correct symlink is no-op on re-run" test_correct_symlink_is_noop
run_test "override: wrong symlink is refreshed" test_wrong_symlink_refreshed
run_test "override: --force replaces regular file override" test_force_overrides_regular_file
run_test "override: skip applies to commands and hooks" test_override_applies_to_commands_and_hooks
run_test "override: summary line reports linked/ok/skipped" test_summary_line
run_test "guide: documents local override behavior" test_guide_documents_local_override
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
