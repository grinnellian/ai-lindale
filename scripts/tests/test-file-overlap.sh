#!/usr/bin/env bash
# DX-012: Tests for parallel-worktree file-overlap detection.
# Run from repo root: bash scripts/tests/test-file-overlap.sh

set -uo pipefail

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-file-overlap.sh"

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

test_no_overlap() {
  local out rc
  out=$(bash "$CHECKER" "src/a.ts,src/b.ts" "src/c.ts,src/d.ts")
  rc=$?
  [ "$rc" -eq 0 ]
}

test_exact_overlap() {
  local rc
  bash "$CHECKER" "src/a.ts,src/b.ts" "src/b.ts,src/e.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_directory_containment() {
  local rc
  bash "$CHECKER" "src/feature/,src/other.ts" "src/feature/handler.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_directory_containment_no_trailing_slash() {
  # DX-012 review finding MAJOR-1: the checker's own comment claims a
  # slash-less directory prefix (e.g. "src/feature") is detected as
  # containing "src/feature/handler.ts", but only the trailing-slash form
  # was implemented. Exact reproduction from the review.
  local rc
  bash "$CHECKER" "src/feature" "src/feature/handler.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_comma_space_separated_input() {
  # DX-012 review finding MINOR-1: a natural TPM dispatch list written with
  # a space after the comma made " src/b.ts" != "src/b.ts", so a real
  # overlap silently reported clean.
  local rc
  bash "$CHECKER" "src/a.ts, src/b.ts" "src/b.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_dot_slash_prefix_input() {
  # DX-012 review finding MINOR-1: "./src/a.ts" and "src/a.ts" name the same
  # file but compared unequal.
  local rc
  bash "$CHECKER" "./src/a.ts" "src/a.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_dot_slash_directory_containment() {
  # Normalization must compose with containment, not just exact match.
  local rc
  bash "$CHECKER" "./src/feature/" "src/feature/handler.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_empty_lists() {
  local rc
  bash "$CHECKER" "" "" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ]
}

test_whitespace_only_entry_is_ignored() {
  # A trailing comma or a stray space between commas must not become an
  # empty-string path that matches everything.
  local rc
  bash "$CHECKER" "src/a.ts, ,"  "src/b.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ]
}

test_one_empty_list() {
  local rc
  bash "$CHECKER" "src/a.ts" "" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ]
}

test_missing_second_argument_is_usage_error() {
  # DX-012 review NIT-4: a TPM quoting mistake that drops the second list
  # must not read as "no overlap". Exit 2 (matching validate-branch-name.sh's
  # non-zero convention) so a caller testing for 0 fails safe.
  local rc
  bash "$CHECKER" "src/a.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ]
}

test_no_arguments_is_usage_error() {
  local rc
  bash "$CHECKER" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ]
}

test_shared_config_warns_not_blocks() {
  local out rc
  out=$(bash "$CHECKER" "CLAUDE.md,src/a.ts" "CLAUDE.md,src/b.ts")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "    Expected exit 0 (warning only), got $rc"
    return 1
  fi
  if ! echo "$out" | grep -qi "warning"; then
    echo "    Expected a WARNING for shared config file, got:"
    echo "$out"
    return 1
  fi
}

test_shared_team_config_warns() {
  local out
  out=$(bash "$CHECKER" "templates/team-config.yml" "templates/team-config.yml")
  echo "$out" | grep -qi "warning"
}

echo "=== DX-012 File Overlap Tests ==="
echo ""
run_test "no overlap between disjoint lists -> exit 0" test_no_overlap
run_test "exact file overlap -> exit 1" test_exact_overlap
run_test "directory containment -> exit 1" test_directory_containment
run_test "directory containment without trailing slash -> exit 1" test_directory_containment_no_trailing_slash
run_test "comma-space separated input -> exit 1" test_comma_space_separated_input
run_test "./ prefixed path matches bare path -> exit 1" test_dot_slash_prefix_input
run_test "./ prefixed directory containment -> exit 1" test_dot_slash_directory_containment
run_test "empty lists -> exit 0" test_empty_lists
run_test "whitespace-only list entry is ignored -> exit 0" test_whitespace_only_entry_is_ignored
run_test "one empty list -> exit 0" test_one_empty_list
run_test "missing second argument -> usage error, exit 2" test_missing_second_argument_is_usage_error
run_test "no arguments -> usage error, exit 2" test_no_arguments_is_usage_error
run_test "shared config file -> warning, exit 0" test_shared_config_warns_not_blocks
run_test "team-config.yml overlap -> warning" test_shared_team_config_warns

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
