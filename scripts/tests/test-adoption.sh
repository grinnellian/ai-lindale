#!/usr/bin/env bash
# DX-007: Tests for install.sh and adoption workflow.
# Run from repo root: bash scripts/tests/test-adoption.sh

set -euo pipefail

PASS=0
FAIL=0
TMPDIR_BASE=""
TMPDIRS=()

# Capture repo root BEFORE any cd operations
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Helpers ---

setup_project() {
  # Create a temporary "downstream project" directory with a fake framework submodule
  TMPDIR_BASE=$(mktemp -d)
  # Track every fixture dir: TMPDIR_BASE is overwritten per test, so removing
  # only the last one at EXIT leaked one temp dir per setup_project call.
  TMPDIRS+=("$TMPDIR_BASE")
  PROJECT="$TMPDIR_BASE/project"
  mkdir -p "$PROJECT"
  cd "$PROJECT"
  git init --quiet

  # Simulate the framework submodule at .ai-lindale/
  FRAMEWORK="$PROJECT/.ai-lindale"
  mkdir -p "$FRAMEWORK/.claude/agents" "$FRAMEWORK/.claude/commands" "$FRAMEWORK/scripts" "$FRAMEWORK/templates"
  for agent_file in "$REPO_ROOT"/.claude/agents/*.md; do
    cp "$agent_file" "$FRAMEWORK/.claude/agents/$(basename "$agent_file")"
  done
  for cmd_file in "$REPO_ROOT"/.claude/commands/*.md; do
    cp "$cmd_file" "$FRAMEWORK/.claude/commands/$(basename "$cmd_file")"
  done

  # Copy templates
  cp "$REPO_ROOT/templates/team-config.yml" "$FRAMEWORK/templates/team-config.yml"
  cp "$REPO_ROOT/templates/CLAUDE.md" "$FRAMEWORK/templates/CLAUDE.md"

  # Copy install.sh
  cp "$REPO_ROOT/scripts/install.sh" "$FRAMEWORK/scripts/install.sh"
  chmod +x "$FRAMEWORK/scripts/install.sh"

  # Skills directory exists on the framework side but ships empty by
  # default (FEAT-011: skills are project-owned unless the framework
  # itself ships one).
  mkdir -p "$FRAMEWORK/.claude/skills"
}

# Helper: add a fake framework-shipped skill (FEAT-011).
# Args: $1 = skill name
setup_framework_skill() {
  local name="$1"
  mkdir -p "$FRAMEWORK/.claude/skills/${name}"
  cat > "$FRAMEWORK/.claude/skills/${name}/SKILL.md" << EOF
---
name: ${name}
description: fake framework-shipped skill for testing
---
# ${name}
EOF
}

teardown() {
  local d
  for d in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do
    if [ -n "$d" ] && [ -d "$d" ]; then
      rm -rf "$d"
    fi
  done
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

test_all_framework_commands_symlinked() {
  # BUG-008: install.sh must not hardcode the command list — every *.md file
  # present in the framework's .claude/commands/ (including autodev.md and
  # any future additions) must get symlinked downstream.
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  local cmd_file base
  for cmd_file in "$FRAMEWORK"/.claude/commands/*.md; do
    base=$(basename "$cmd_file")
    assert_symlink ".claude/commands/${base}" "../../.ai-lindale/.claude/commands/${base}" || return 1
  done
  # Explicitly assert autodev.md specifically, since that's the reported bug.
  assert_symlink ".claude/commands/autodev.md" "../../.ai-lindale/.claude/commands/autodev.md"
}

test_all_framework_agents_symlinked() {
  # BUG-009: install.sh must not hardcode the agent list — every *.md file
  # present in the framework's .claude/agents/ (including researcher.md and
  # audit-repo.md) must get symlinked downstream.
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  local agent_file base
  for agent_file in "$FRAMEWORK"/.claude/agents/*.md; do
    base=$(basename "$agent_file")
    assert_symlink ".claude/agents/${base}" "../../.ai-lindale/.claude/agents/${base}" || return 1
  done
  # Explicitly assert researcher.md and audit-repo.md, since those are the
  # reported bug.
  assert_symlink ".claude/agents/researcher.md" "../../.ai-lindale/.claude/agents/researcher.md" &&
  assert_symlink ".claude/agents/audit-repo.md" "../../.ai-lindale/.claude/agents/audit-repo.md"
}

test_project_agent_override_preserved() {
  # BUG-007 skip path must apply to non-core agents too: a downstream project
  # can name its own SME the same as a framework agent (e.g. researcher.md),
  # and install.sh must not clobber it.
  setup_project
  mkdir -p .claude/agents
  echo "# Project-specific researcher SME" > .claude/agents/researcher.md
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_not_symlink ".claude/agents/researcher.md" &&
  assert_file_contains ".claude/agents/researcher.md" "Project-specific researcher SME"
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
# then replaces symlinked agent/command files with regular files to simulate the framework repo.
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
}

test_self_host_skips_symlinks() {
  setup_self_host
  bash "$FRAMEWORK/scripts/install.sh"
  # Core agent files must remain regular files — not overwritten with symlinks
  assert_file_not_symlink ".claude/agents/architect.md"
  assert_file_not_symlink ".claude/agents/tpm.md"
  assert_file_not_symlink ".claude/agents/dev.md"
  assert_file_not_symlink ".claude/commands/architect.md"
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

test_override_applies_to_commands() {
  setup_project
  setup_with_override ".claude/commands/dev.md" "# local command override"
  bash "$FRAMEWORK/scripts/install.sh"
  assert_file_not_symlink ".claude/commands/dev.md" &&
  assert_file_contains ".claude/commands/dev.md" "# local command override"
}

test_command_glob_preserves_project_owned_collision() {
  # BUG-008 (ported from PR #112): the commands glob's skip path must apply
  # to non-core names too — a project-owned command colliding with a
  # framework command outside the old hardcoded trio (e.g. autodev.md) is
  # skipped, not clobbered. Mirrors test_project_agent_override_preserved.
  setup_project
  setup_with_override ".claude/commands/autodev.md" "# project-owned autodev override"
  output=$(bash "$FRAMEWORK/scripts/install.sh" 2>&1)
  assert_file_not_symlink ".claude/commands/autodev.md" &&
  assert_file_contains ".claude/commands/autodev.md" "project-owned autodev override" &&
  echo "$output" | grep -qi "skipped .claude/commands/autodev.md"
}

test_no_superseded_model_pins() {
  # DX-041: agent frontmatter must not pin superseded model ids.
  if grep -rlE "model:[[:space:]]*(claude-opus-4-7|claude-sonnet-4-6)" "$REPO_ROOT"/.claude/agents/*.md "$REPO_ROOT"/templates/*.md 2>/dev/null; then
    echo "    Found superseded model pin(s) above"
    return 1
  fi
  return 0
}

test_tpm_agent_tool_unrestricted() {
  # DX-036 (ported from PR #114): the TPM's Agent tool must not be narrowed
  # to a closed list of framework-default subagent types — that blocks
  # dispatch to project-defined agents (SMEs, etc).
  if grep -qE '^[[:space:]]*-[[:space:]]*Agent\(' "$REPO_ROOT/.claude/agents/tpm.md"; then
    echo "    tpm.md still restricts Agent to a closed list"
    return 1
  fi
  assert_file_contains "$REPO_ROOT/.claude/agents/tpm.md" 'Agent$'
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

# --- skills tests (FEAT-011) ---

test_skills_dir_scaffolded() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  if [ ! -d ".claude/skills" ]; then
    echo "    .claude/skills/ directory was not created"
    return 1
  fi
  return 0
}

test_framework_skill_symlinked() {
  setup_project
  setup_framework_skill "autocommit"
  bash "$FRAMEWORK/scripts/install.sh"
  assert_symlink ".claude/skills/autocommit" "../../.ai-lindale/.claude/skills/autocommit"
}

test_project_skill_not_touched() {
  setup_project
  mkdir -p .claude/skills/my-skill
  echo "# project-owned skill" > .claude/skills/my-skill/SKILL.md
  bash "$FRAMEWORK/scripts/install.sh"
  if [ -L ".claude/skills/my-skill" ]; then
    echo "    Should NOT be a symlink: .claude/skills/my-skill"
    return 1
  fi
  assert_file_contains ".claude/skills/my-skill/SKILL.md" "project-owned skill"
}

test_no_framework_skills_no_crash() {
  setup_project
  # No framework skills exist (default) — install.sh must not error.
  bash "$FRAMEWORK/scripts/install.sh" > /dev/null
  if [ ! -d ".claude/skills" ]; then
    echo "    .claude/skills/ directory missing after run with no framework skills"
    return 1
  fi
  return 0
}

test_framework_skill_override_skipped() {
  setup_project
  setup_framework_skill "autocommit"
  mkdir -p .claude/skills/autocommit
  echo "# local skill override" > .claude/skills/autocommit/SKILL.md
  bash "$FRAMEWORK/scripts/install.sh"
  if [ -L ".claude/skills/autocommit" ]; then
    echo "    Should NOT be a symlink: .claude/skills/autocommit (local override present)"
    return 1
  fi
  assert_file_contains ".claude/skills/autocommit/SKILL.md" "local skill override"
}

test_skills_idempotent() {
  setup_project
  setup_framework_skill "autocommit"
  bash "$FRAMEWORK/scripts/install.sh"
  bash "$FRAMEWORK/scripts/install.sh"
  assert_symlink ".claude/skills/autocommit" "../../.ai-lindale/.claude/skills/autocommit"
}

test_guide_documents_skills() {
  assert_file_contains "$REPO_ROOT/docs/adoption-guide.md" ".claude/skills"
}

test_skill_template_exists() {
  assert_file_exists "$REPO_ROOT/templates/skill.md"
}

# FEAT-011 review finding M1: a stale symlink pointing at an *existing
# directory* (the skills case -- skills are directory symlinks, unlike the
# file symlinks used for agents/commands) must be replaced outright by the
# refresh path, not dereferenced into. `ln -sf` on such a destination
# creates the new link *inside* the stale target instead of replacing it,
# so the installer would falsely report "refreshed" while leaving the old
# (wrong) symlink in place and depositing a stray link inside the old
# target directory.
test_skill_stale_dir_symlink_refreshed_correctly() {
  setup_project
  setup_framework_skill "autocommit"
  bash "$FRAMEWORK/scripts/install.sh"

  # Replace the correct skill symlink with one pointing at a *different*,
  # still-existing directory (simulating a stale target from before a path
  # restructure -- see install.sh's INFRA-001 note).
  rm ".claude/skills/autocommit"
  mkdir -p "old-framework/.claude/skills/autocommit"
  echo "stale" > "old-framework/.claude/skills/autocommit/SKILL.md"
  ln -s "../../old-framework/.claude/skills/autocommit" ".claude/skills/autocommit"

  bash "$FRAMEWORK/scripts/install.sh" > /dev/null

  # The symlink itself must now point at the correct, current framework
  # skill -- not still resolve to the stale target.
  assert_symlink ".claude/skills/autocommit" "../../.ai-lindale/.claude/skills/autocommit" || return 1

  # The stale target directory must not have been polluted with a stray
  # symlink deposited inside it by a dereferencing `ln -sf`.
  if [ -e "old-framework/.claude/skills/autocommit/autocommit" ]; then
    echo "    Stale target directory was polluted with a stray symlink (ln -sf dereference bug)"
    return 1
  fi
  return 0
}

# Companion assertion: file symlinks (agents/commands) are not affected by
# the directory-symlink dereference bug, since `ln -sf` replaces a symlink
# pointing at an existing *file* correctly.
test_agent_stale_file_symlink_refreshed_correctly() {
  setup_project
  bash "$FRAMEWORK/scripts/install.sh"
  rm ".claude/agents/architect.md"
  echo "# stale target" > "old-target-file.md"
  ln -s "../../old-target-file.md" ".claude/agents/architect.md"
  bash "$FRAMEWORK/scripts/install.sh" > /dev/null
  assert_symlink ".claude/agents/architect.md" "../../.ai-lindale/.claude/agents/architect.md"
}

# FEAT-011 review finding m2 (test gap): the `[ -d ]` guard around the
# skills glob was never exercised, because setup_project unconditionally
# creates the fixture's framework skills directory -- which also diverges
# from the real framework repo, where .claude/skills/ does not exist at all.
test_absent_framework_skills_dir_no_crash() {
  setup_project
  rmdir "$FRAMEWORK/.claude/skills"
  bash "$FRAMEWORK/scripts/install.sh" > /dev/null
  if [ ! -d ".claude/skills" ]; then
    echo "    .claude/skills/ must still be scaffolded when the framework ships none"
    return 1
  fi
  # Agents/commands must still have been linked -- an absent skills dir is
  # not allowed to abort the run.
  assert_symlink ".claude/agents/architect.md" "../../.ai-lindale/.claude/agents/architect.md"
}

# FEAT-011 review finding m2 (test gap): --force against a project-owned
# skill *directory* colliding with a framework skill runs `rm -rf` on a real
# directory -- new territory, since before FEAT-011 only regular files ever
# reached that branch.
test_force_replaces_project_owned_skill_directory() {
  setup_project
  setup_framework_skill "autocommit"
  mkdir -p .claude/skills/autocommit/nested
  echo "# local skill override" > .claude/skills/autocommit/SKILL.md
  echo "local" > .claude/skills/autocommit/nested/extra.md

  bash "$FRAMEWORK/scripts/install.sh" --force > /dev/null

  assert_symlink ".claude/skills/autocommit" "../../.ai-lindale/.claude/skills/autocommit" || return 1
  # The framework skill must be what resolves now, not the local content.
  assert_file_contains ".claude/skills/autocommit/SKILL.md" "fake framework-shipped skill" || return 1
  if [ -e ".claude/skills/autocommit/nested" ]; then
    echo "    Local skill directory contents survived --force (rm -rf did not happen)"
    return 1
  fi
  return 0
}

# --- standardization playbook tests (DX-025) ---

test_standardization_playbook_template_exists() {
  assert_file_exists "$REPO_ROOT/templates/standardization-playbook.md"
}

test_standardization_playbook_bootstrap_exists() {
  assert_file_exists "$REPO_ROOT/templates/standardization-playbook-bootstrap.md"
}

test_standardization_playbook_has_phases() {
  local tmpl="$REPO_ROOT/templates/standardization-playbook.md"
  assert_file_contains "$tmpl" "Foundation" &&
  assert_file_contains "$tmpl" "Tests" &&
  assert_file_contains "$tmpl" "Security" &&
  assert_file_contains "$tmpl" "Code Quality" &&
  assert_file_contains "$tmpl" "Infrastructure"
}

test_standardization_playbook_has_priorities() {
  local tmpl="$REPO_ROOT/templates/standardization-playbook.md"
  assert_file_contains "$tmpl" "P0" &&
  assert_file_contains "$tmpl" "P1" &&
  assert_file_contains "$tmpl" "P2"
}

test_standardization_playbook_has_depends_on() {
  assert_file_contains "$REPO_ROOT/templates/standardization-playbook.md" "Depends on"
}

test_standardization_playbook_has_guiding_principles() {
  assert_file_contains "$REPO_ROOT/templates/standardization-playbook.md" "Guiding Principles"
}

test_standardization_bootstrap_has_gh_issue_create() {
  assert_file_contains "$REPO_ROOT/templates/standardization-playbook-bootstrap.md" "gh issue create"
}

test_standardization_bootstrap_has_brownfield() {
  assert_file_contains "$REPO_ROOT/templates/standardization-playbook-bootstrap.md" "brownfield"
}

test_tpm_references_standardization_bootstrap() {
  assert_file_contains "$REPO_ROOT/.claude/agents/tpm.md" "standardization-playbook-bootstrap.md"
}

test_guide_references_standardization_playbook_output() {
  assert_file_contains "$REPO_ROOT/docs/adoption-guide.md" "standardization-playbook.md"
}

# --- handoff procedure tests (FEAT-013) ---

test_handoff_procedure_template_exists() {
  assert_file_exists "$REPO_ROOT/templates/handoff-procedure.md"
}

test_handoff_command_exists() {
  assert_file_exists "$REPO_ROOT/.claude/commands/handoff.md"
}

test_handoff_procedure_has_buckets() {
  local tmpl="$REPO_ROOT/templates/handoff-procedure.md"
  assert_file_contains "$tmpl" "Client" &&
  assert_file_contains "$tmpl" "Successor" &&
  assert_file_contains "$tmpl" "Framework" &&
  assert_file_contains "$tmpl" "Working-copy"
}

test_handoff_procedure_has_branch_conventions() {
  local tmpl="$REPO_ROOT/templates/handoff-procedure.md"
  assert_file_contains "$tmpl" "client-handoff" &&
  assert_file_contains "$tmpl" "unmerged"
}

test_handoff_procedure_has_gitignore_guidance() {
  assert_file_contains "$REPO_ROOT/templates/handoff-procedure.md" ".gitignore"
}

test_handoff_procedure_has_signing_convention() {
  assert_file_contains "$REPO_ROOT/templates/handoff-procedure.md" "Signing convention"
}

test_handoff_command_references_procedure() {
  assert_file_contains "$REPO_ROOT/.claude/commands/handoff.md" "templates/handoff-procedure.md"
}

test_tpm_references_handoff_procedure() {
  assert_file_contains "$REPO_ROOT/.claude/agents/tpm.md" "handoff-procedure.md"
}

test_guide_references_handoff_procedure() {
  assert_file_contains "$REPO_ROOT/docs/adoption-guide.md" "handoff-procedure.md"
}

# --- Run all tests ---

echo "=== DX-007 Adoption Tests ==="
echo ""
echo "--- install.sh tests ---"
run_test "creates agent symlinks" test_agent_symlinks
run_test "creates command symlinks" test_command_symlinks
run_test "symlinks all framework commands, incl. autodev" test_all_framework_commands_symlinked
run_test "symlinks all framework agents, incl. researcher and audit-repo" test_all_framework_agents_symlinked
run_test "preserves project-owned agent at colliding name" test_project_agent_override_preserved
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
run_test "override: skip applies to commands" test_override_applies_to_commands
run_test "command glob preserves project-owned collision" test_command_glob_preserves_project_owned_collision
run_test "override: summary line reports linked/ok/skipped" test_summary_line
run_test "guide: documents local override behavior" test_guide_documents_local_override

echo ""
echo "--- role frontmatter tests (DX-036) ---"
run_test "tpm.md Agent tool is not restricted to a closed list" test_tpm_agent_tool_unrestricted

echo ""
echo "--- standardization playbook tests (DX-025) ---"
run_test "standardization playbook template exists" test_standardization_playbook_template_exists
run_test "standardization playbook bootstrap exists" test_standardization_playbook_bootstrap_exists
run_test "standardization playbook has all five phases" test_standardization_playbook_has_phases
run_test "standardization playbook has priorities P0-P2" test_standardization_playbook_has_priorities
run_test "standardization playbook has Depends on field" test_standardization_playbook_has_depends_on
run_test "standardization playbook has Guiding Principles" test_standardization_playbook_has_guiding_principles
run_test "standardization bootstrap references gh issue create" test_standardization_bootstrap_has_gh_issue_create
run_test "standardization bootstrap references brownfield" test_standardization_bootstrap_has_brownfield
run_test "tpm.md references standardization-playbook-bootstrap.md" test_tpm_references_standardization_bootstrap
run_test "adoption guide references standardization-playbook.md output" test_guide_references_standardization_playbook_output

echo ""
echo "--- skills tests (FEAT-011) ---"
run_test "skills: .claude/skills/ scaffolded" test_skills_dir_scaffolded
run_test "skills: framework-shipped skill is symlinked" test_framework_skill_symlinked
run_test "skills: project-owned skill is not touched" test_project_skill_not_touched
run_test "skills: no framework skills does not crash" test_no_framework_skills_no_crash
run_test "skills: local override of framework skill is skipped" test_framework_skill_override_skipped
run_test "skills: idempotent on re-run" test_skills_idempotent
run_test "guide: documents .claude/skills convention" test_guide_documents_skills
run_test "templates/skill.md skeleton exists" test_skill_template_exists
run_test "skills: stale dir-symlink refreshed without corrupting target" test_skill_stale_dir_symlink_refreshed_correctly
run_test "agents: stale file-symlink refreshed correctly" test_agent_stale_file_symlink_refreshed_correctly
run_test "skills: absent framework skills dir does not abort the run" test_absent_framework_skills_dir_no_crash
run_test "skills: --force replaces a project-owned skill directory" test_force_replaces_project_owned_skill_directory

echo ""
echo "--- handoff procedure tests (FEAT-013) ---"
run_test "handoff procedure template exists" test_handoff_procedure_template_exists
run_test "handoff command exists" test_handoff_command_exists
run_test "handoff procedure has all four buckets" test_handoff_procedure_has_buckets
run_test "handoff procedure has branch conventions" test_handoff_procedure_has_branch_conventions
run_test "handoff procedure has .gitignore guidance" test_handoff_procedure_has_gitignore_guidance
run_test "handoff procedure has signing convention" test_handoff_procedure_has_signing_convention
run_test "handoff command references procedure" test_handoff_command_references_procedure
run_test "tpm.md references handoff-procedure.md" test_tpm_references_handoff_procedure
run_test "adoption guide references handoff-procedure.md" test_guide_references_handoff_procedure

echo ""
echo "--- model pin freshness ---"
run_test "no superseded model ids in agent/template frontmatter" test_no_superseded_model_pins

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
