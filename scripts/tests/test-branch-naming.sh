#!/usr/bin/env bash
# DX-012: Tests for branch naming convention validation.
# Run from repo root: bash scripts/tests/test-branch-naming.sh

set -uo pipefail

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-branch-name.sh"

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

assert_valid() {
  local branch="$1"
  if bash "$VALIDATOR" "$branch" >/dev/null 2>&1; then
    return 0
  else
    echo "    Expected VALID, got rejected: $branch"
    return 1
  fi
}

assert_invalid() {
  local branch="$1"
  local rc
  bash "$VALIDATOR" "$branch" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 2 ]; then
    return 0
  else
    echo "    Expected INVALID (exit 2), got exit $rc: $branch"
    return 1
  fi
}

# --- Valid names ---

test_valid_feat() { assert_valid "feat/FEAT-042-chart-rendering"; }
test_valid_dx() { assert_valid "dx/DX-012-branch-naming"; }
test_valid_fix() { assert_valid "fix/BUG-017-null-transit"; }
test_valid_docs() { assert_valid "docs/DOCS-003-api-reference"; }
test_valid_infra() { assert_valid "infra/INFRA-008-ci-pipeline"; }
test_valid_single_word_slug() { assert_valid "dx/DX-005-config"; }
test_valid_five_word_slug() { assert_valid "feat/FEAT-001-one-two-three-four-five"; }

# --- Invalid names ---

test_invalid_no_type_prefix() { assert_invalid "FEAT-042-chart-rendering"; }
test_invalid_type_prefix_mismatch() { assert_invalid "feat/BUG-017-null-transit"; }
test_invalid_uppercase_description() { assert_invalid "feat/FEAT-042-ChartRendering"; }
test_invalid_main() { assert_invalid "main"; }
test_invalid_master() { assert_invalid "master"; }
test_invalid_too_many_words() { assert_invalid "feat/FEAT-001-one-two-three-four-five-six"; }
test_invalid_epic_not_branchable() { assert_invalid "epic/EPIC-004-container-boundary"; }
test_invalid_missing_ticket_number() { assert_invalid "dx/DX-branch-naming"; }

# --- Usage errors ---

# Sibling of test_missing_second_argument_is_usage_error in
# test-file-overlap.sh (DX-012 review NIT-4): a caller that passes more
# names than the script reads must not get a verdict that covers only the
# first one. `validate-branch-name.sh "feat/FEAT-001-slug" "bogus-branch"`
# used to exit 0 -- silently validating $1 and discarding $2, which reads as
# "both are fine" to the caller that wrote the second name.
test_extra_arguments_is_usage_error() {
  local rc
  bash "$VALIDATOR" "feat/FEAT-001-slug" "orchestrate/2026-07-06" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 2 ]; then
    return 0
  fi
  echo "    Expected usage error (exit 2) for 2 arguments, got exit $rc"
  return 1
}

echo "=== DX-012 Branch Naming Tests ==="
echo ""
run_test "valid: feat/FEAT-042-chart-rendering" test_valid_feat
run_test "valid: dx/DX-012-branch-naming" test_valid_dx
run_test "valid: fix/BUG-017-null-transit" test_valid_fix
run_test "valid: docs/DOCS-003-api-reference" test_valid_docs
run_test "valid: infra/INFRA-008-ci-pipeline" test_valid_infra
run_test "valid: single-word slug" test_valid_single_word_slug
run_test "valid: five-word slug (at limit)" test_valid_five_word_slug
run_test "invalid: no type prefix" test_invalid_no_type_prefix
run_test "invalid: type/prefix mismatch" test_invalid_type_prefix_mismatch
run_test "invalid: uppercase description" test_invalid_uppercase_description
run_test "invalid: main" test_invalid_main
run_test "invalid: master" test_invalid_master
run_test "invalid: more than five words" test_invalid_too_many_words
run_test "invalid: EPIC not branchable" test_invalid_epic_not_branchable
run_test "invalid: missing ticket number" test_invalid_missing_ticket_number
run_test "usage error: extra arguments -> exit 2" test_extra_arguments_is_usage_error

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
