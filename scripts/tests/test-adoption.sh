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

  # Copy template
  cp "$REPO_ROOT/templates/team-config.yml" "$FRAMEWORK/templates/team-config.yml"

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
  echo "# Project-specific consultant" > .claude/agents/consultant.md
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_not_symlink ".claude/agents/consultant.md"
  assert_file_contains ".claude/agents/consultant.md" "Project-specific consultant"
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
echo ""
echo "--- guide completeness tests ---"
run_test "adoption guide exists" test_guide_exists
run_test "guide references submodule commands" test_guide_references_subtree_commands
run_test "guide has file ownership table" test_guide_has_ownership_table
run_test "guide has aistrologer migration section" test_guide_has_migration_section
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
