#!/usr/bin/env bash
# DX-013: Tests for the /researcher command and researcher agent fixtures.
# Run from repo root: bash scripts/tests/test-researcher-fixtures.sh

set -euo pipefail

PASS=0
FAIL=0

# Capture repo root BEFORE any cd operations
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

COMMAND_FILE="$REPO_ROOT/.claude/commands/researcher.md"
AGENT_FILE="$REPO_ROOT/.claude/agents/researcher.md"

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

test_command_activates_researcher() {
  assert_file_contains "$COMMAND_FILE" 'researcher'
}

test_command_reviews_claude_md_and_memory() {
  assert_file_contains "$COMMAND_FILE" 'CLAUDE.md' &&
  assert_file_contains "$COMMAND_FILE" 'memory'
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

test_agent_has_websearch_tool() {
  assert_file_contains "$AGENT_FILE" '  - WebSearch'
}

test_agent_has_webfetch_tool() {
  assert_file_contains "$AGENT_FILE" '  - WebFetch'
}

test_agent_does_not_have_write() {
  assert_file_not_contains "$AGENT_FILE" '  - Write'
}

test_agent_does_not_have_edit() {
  assert_file_not_contains "$AGENT_FILE" '  - Edit'
}

test_agent_does_not_have_notebookedit() {
  assert_file_not_contains "$AGENT_FILE" '  - NotebookEdit'
}

test_agent_does_not_have_agent_tool() {
  assert_file_not_contains "$AGENT_FILE" '  - Agent'
}

test_agent_has_initial_prompt() {
  assert_file_contains "$AGENT_FILE" 'initialPrompt: /researcher'
}

test_agent_has_max_turns() {
  assert_file_contains "$AGENT_FILE" 'maxTurns:'
}

test_agent_signs_as_researcher() {
  assert_file_contains "$AGENT_FILE" '\-Claude Researcher'
}

test_agent_has_self_orientation() {
  assert_file_contains "$AGENT_FILE" 'Self-Orientation'
}

# --- Run all tests ---

echo "=== DX-013 researcher Tests ==="
echo ""
echo "--- command file tests ---"
run_test "command file exists" test_command_file_exists
run_test "command activates researcher" test_command_activates_researcher
run_test "command reviews CLAUDE.md and memory" test_command_reviews_claude_md_and_memory
echo ""
echo "--- agent file tests ---"
run_test "agent file exists" test_agent_file_exists
run_test "agent has Bash tool" test_agent_has_bash_tool
run_test "agent has Read tool" test_agent_has_read_tool
run_test "agent has Grep tool" test_agent_has_grep_tool
run_test "agent has Glob tool" test_agent_has_glob_tool
run_test "agent has WebSearch tool" test_agent_has_websearch_tool
run_test "agent has WebFetch tool" test_agent_has_webfetch_tool
run_test "agent does NOT have Write tool" test_agent_does_not_have_write
run_test "agent does NOT have Edit tool" test_agent_does_not_have_edit
run_test "agent does NOT have NotebookEdit tool" test_agent_does_not_have_notebookedit
run_test "agent does NOT have Agent tool" test_agent_does_not_have_agent_tool
run_test "agent has initialPrompt /researcher" test_agent_has_initial_prompt
run_test "agent has maxTurns set" test_agent_has_max_turns
run_test "agent signs as -Claude Researcher" test_agent_signs_as_researcher
run_test "agent has Self-Orientation section" test_agent_has_self_orientation

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
