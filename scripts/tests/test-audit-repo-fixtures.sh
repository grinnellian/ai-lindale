#!/usr/bin/env bash
# FEAT-002: Tests for the /audit-repo command and audit-repo agent fixtures.
# Run from repo root: bash scripts/tests/test-audit-repo-fixtures.sh

set -euo pipefail

PASS=0
FAIL=0

# Capture repo root BEFORE any cd operations
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

COMMAND_FILE="$REPO_ROOT/.claude/commands/audit-repo.md"
AGENT_FILE="$REPO_ROOT/.claude/agents/audit-repo.md"

# --- Helpers ---

assert_file_exists() {
  local path="$1"
  if [ -f "$path" ]; then
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

assert_file_not_contains() {
  local path="$1"
  local pattern="$2"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    echo "    File $path should NOT contain: $pattern"
    return 1
  else
    return 0
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

# --- Command file tests ---

test_command_file_exists() {
  assert_file_exists "$COMMAND_FILE"
}

test_command_calls_repos_api() {
  assert_file_contains "$COMMAND_FILE" 'gh api repos/'
}

test_command_calls_git_trees_api() {
  assert_file_contains "$COMMAND_FILE" 'git/trees'
}

test_command_calls_commits_api() {
  assert_file_contains "$COMMAND_FILE" '/commits'
}

test_command_calls_contents_api() {
  assert_file_contains "$COMMAND_FILE" '/contents'
}

test_command_validates_arguments() {
  assert_file_contains "$COMMAND_FILE" 'ARGUMENTS' &&
  assert_file_contains "$COMMAND_FILE" 'owner/repo'
}

test_command_notes_no_local_clone() {
  assert_file_contains "$COMMAND_FILE" 'NO local clone'
}

test_command_distinguishes_initial_vs_current() {
  assert_file_contains "$COMMAND_FILE" 'initial commit'
}

test_command_lists_deferred_scope() {
  assert_file_contains "$COMMAND_FILE" 'Out of scope' &&
  assert_file_contains "$COMMAND_FILE" 'DX-019'
}

# --- Agent file tests ---

test_agent_file_exists() {
  assert_file_exists "$AGENT_FILE"
}

test_agent_has_bash_tool() {
  assert_file_contains "$AGENT_FILE" '  - Bash'
}

test_agent_has_read_tool() {
  assert_file_contains "$AGENT_FILE" '  - Read'
}

test_agent_has_grep_tool() {
  assert_file_contains "$AGENT_FILE" '  - Grep'
}

test_agent_has_glob_tool() {
  assert_file_contains "$AGENT_FILE" '  - Glob'
}

test_agent_does_not_have_write() {
  assert_file_not_contains "$AGENT_FILE" '  - Write'
}

test_agent_does_not_have_edit() {
  assert_file_not_contains "$AGENT_FILE" '  - Edit'
}

test_agent_does_not_have_agent_tool() {
  assert_file_not_contains "$AGENT_FILE" '  - Agent'
}

test_agent_has_initial_prompt() {
  assert_file_contains "$AGENT_FILE" 'initialPrompt: /audit-repo'
}

# --- Run all tests ---

echo "=== FEAT-002 audit-repo Tests ==="
echo ""
echo "--- command file tests ---"
run_test "command file exists" test_command_file_exists
run_test "command calls repos/ API" test_command_calls_repos_api
run_test "command calls git/trees API" test_command_calls_git_trees_api
run_test "command calls /commits API" test_command_calls_commits_api
run_test "command calls /contents API" test_command_calls_contents_api
run_test "command validates owner/repo ARGUMENTS" test_command_validates_arguments
run_test "command notes API-only, no local clone" test_command_notes_no_local_clone
run_test "command distinguishes initial commit from current state" test_command_distinguishes_initial_vs_current
run_test "command lists deferred/out-of-scope items" test_command_lists_deferred_scope
echo ""
echo "--- agent file tests ---"
run_test "agent file exists" test_agent_file_exists
run_test "agent has Bash tool" test_agent_has_bash_tool
run_test "agent has Read tool" test_agent_has_read_tool
run_test "agent has Grep tool" test_agent_has_grep_tool
run_test "agent has Glob tool" test_agent_has_glob_tool
run_test "agent does NOT have Write tool" test_agent_does_not_have_write
run_test "agent does NOT have Edit tool" test_agent_does_not_have_edit
run_test "agent does NOT have Agent tool" test_agent_does_not_have_agent_tool
run_test "agent has initialPrompt /audit-repo" test_agent_has_initial_prompt

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
