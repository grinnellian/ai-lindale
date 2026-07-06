#!/usr/bin/env bash
# DX-014: Tests for per-role skills frontmatter assignment.
# Run from repo root: bash scripts/tests/test-skills-assignment.sh

set -euo pipefail

PASS=0
FAIL=0

# Capture repo root BEFORE any cd operations
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

AGENTS_DIR="$REPO_ROOT/.claude/agents"
DEV_FILE="$AGENTS_DIR/dev.md"
TPM_FILE="$AGENTS_DIR/tpm.md"
ARCHITECT_FILE="$AGENTS_DIR/architect.md"
RESEARCHER_FILE="$AGENTS_DIR/researcher.md"
AUDIT_REPO_FILE="$AGENTS_DIR/audit-repo.md"
ADOPTION_GUIDE="$REPO_ROOT/docs/adoption-guide.md"

# --- Helpers ---

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

# --- dev: simplify, claude-api, verify ---

test_dev_has_skills_key() {
  assert_file_contains "$DEV_FILE" '^skills:'
}

test_dev_has_simplify() {
  assert_file_contains "$DEV_FILE" '  - simplify'
}

test_dev_has_claude_api() {
  assert_file_contains "$DEV_FILE" '  - claude-api'
}

test_dev_has_verify() {
  assert_file_contains "$DEV_FILE" '  - verify'
}

# --- tpm: loop ---

test_tpm_has_skills_key() {
  assert_file_contains "$TPM_FILE" '^skills:'
}

test_tpm_has_loop() {
  assert_file_contains "$TPM_FILE" '  - loop'
}

# --- architect: code-review ---

test_architect_has_skills_key() {
  assert_file_contains "$ARCHITECT_FILE" '^skills:'
}

test_architect_has_code_review() {
  assert_file_contains "$ARCHITECT_FILE" '  - code-review'
}

# --- researcher: claude-api ---

test_researcher_has_skills_key() {
  assert_file_contains "$RESEARCHER_FILE" '^skills:'
}

test_researcher_has_claude_api() {
  assert_file_contains "$RESEARCHER_FILE" '  - claude-api'
}

# --- audit-repo: no skills key, but rationale documented ---

test_audit_repo_has_no_skills_key() {
  assert_file_not_contains "$AUDIT_REPO_FILE" '^skills:'
}

test_audit_repo_documents_skills_rationale() {
  assert_file_contains "$AUDIT_REPO_FILE" 'Skills (DX-014)'
}

# --- no role invocation commands assigned as skills ---

test_no_role_invocation_as_skill() {
  for f in "$DEV_FILE" "$TPM_FILE" "$ARCHITECT_FILE" "$RESEARCHER_FILE"; do
    if grep -A5 '^skills:' "$f" | grep -qE '  - (architect|dev|tpm|researcher|audit-repo)$'; then
      echo "    File $f assigns a role-invocation command as a skill"
      return 1
    fi
  done
  return 0
}

# --- adoption guide documents rationale ---

test_adoption_guide_documents_assignment() {
  assert_file_contains "$ADOPTION_GUIDE" 'Per-Role Skill Assignment'
}

# --- Run all tests ---

echo "=== DX-014 skills assignment Tests ==="
echo ""
echo "--- dev ---"
run_test "dev has skills key" test_dev_has_skills_key
run_test "dev has simplify" test_dev_has_simplify
run_test "dev has claude-api" test_dev_has_claude_api
run_test "dev has verify" test_dev_has_verify
echo ""
echo "--- tpm ---"
run_test "tpm has skills key" test_tpm_has_skills_key
run_test "tpm has loop" test_tpm_has_loop
echo ""
echo "--- architect ---"
run_test "architect has skills key" test_architect_has_skills_key
run_test "architect has code-review" test_architect_has_code_review
echo ""
echo "--- researcher ---"
run_test "researcher has skills key" test_researcher_has_skills_key
run_test "researcher has claude-api" test_researcher_has_claude_api
echo ""
echo "--- audit-repo ---"
run_test "audit-repo has no skills key" test_audit_repo_has_no_skills_key
run_test "audit-repo documents skills rationale" test_audit_repo_documents_skills_rationale
echo ""
echo "--- cross-cutting ---"
run_test "no role invocation command assigned as a skill" test_no_role_invocation_as_skill
run_test "adoption guide documents per-role assignment" test_adoption_guide_documents_assignment

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
