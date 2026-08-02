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

test_leading_slash_path_matches_bare_path() {
  # Round-10 review: the header contract says "/" names the repo root, but
  # only an entry that was *only* root punctuation was anchored there --
  # "/scripts/install.sh" stayed literal and compared unequal to
  # "scripts/install.sh", so a real overlap reported clean. Root-anchored
  # is the natural reading of a leading slash for a repo-relative tool, and
  # a false negative is the fail-unsafe direction for a safety check.
  local rc
  bash "$CHECKER" "/src/a.ts" "src/a.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_leading_slash_directory_containment() {
  # Same normalization must compose with containment, not just exact match.
  local rc
  bash "$CHECKER" "/src/feature" "src/feature/handler.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_leading_slash_dot_mixed() {
  # "/./src/a.ts" mixes both anchoring forms; stripping must interleave
  # rather than run one pass of each.
  local rc
  bash "$CHECKER" "/./src/a.ts" "src/a.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_dotdot_still_not_resolved() {
  # Guard against over-normalizing: ".." resolution is explicitly out of
  # contract and must stay that way, so "../src/a.ts" keeps comparing
  # literally rather than being anchored to the root.
  local rc
  bash "$CHECKER" "../src/a.ts" "src/a.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ]
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

test_newline_separated_list_detects_overlap() {
  # Round-3 review: `read -r -a` stops at the first newline, so a list
  # pasted with newline separators (the natural shape of a file list)
  # silently dropped every entry after line 1 -- a real overlap on line 2
  # reported clean. Newlines must be treated as separators like commas.
  local rc
  bash "$CHECKER" $'src/a.ts\nsrc/b.ts' "src/b.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_crlf_separated_list_detects_overlap() {
  # A list pasted from CRLF content must not carry \r into path comparison.
  local rc
  bash "$CHECKER" $'src/a.ts\r\nsrc/b.ts' "src/b.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_repo_root_dot_contains_everything() {
  # "." names the repo root, which contains every path. Before this fix it
  # compared literally against nothing and read as "no overlap" -- the
  # fail-unsafe direction for a safety check.
  local rc
  bash "$CHECKER" "." "src/a.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_repo_root_dot_slash_contains_everything() {
  # "./" normalized to the empty string and was skipped as a blank entry.
  local rc
  bash "$CHECKER" "./" "src/a.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_root_slash_contains_everything() {
  # "/" also normalized to empty and vanished. Treat any all-slash entry as
  # the root: overlap-everything is the safe reading of an input that broad.
  local rc
  bash "$CHECKER" "/" "src/a.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_double_slash_normalized() {
  # "src//a.ts" and "src/a.ts" name the same file.
  local rc
  bash "$CHECKER" "src//a.ts" "src/a.ts" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_dash_named_path_not_swallowed() {
  # normalize() used `echo`, whose bash builtin eats "-n"/"-e"/"-E" as
  # flags -- a path literally named "-n" normalized to empty and vanished,
  # so "-n" vs "-n" reported no overlap.
  local rc
  bash "$CHECKER" "-n" "-n" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ]
}

test_glob_entry_prints_note() {
  # Glob characters are compared literally, never expanded. That contract
  # must be announced, not silent: "src/*" vs "src/a.ts" stays exit 0 (the
  # checker is advisory and cannot know the glob's intent), but the output
  # must carry a NOTE so the caller sees the entry was not expanded.
  local out rc
  out=$(bash "$CHECKER" "src/*" "src/a.ts")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "    Expected exit 0 (literal comparison), got $rc"
    return 1
  fi
  echo "$out" | grep -q "NOTE"
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
run_test "/ prefixed path matches bare path -> exit 1" test_leading_slash_path_matches_bare_path
run_test "/ prefixed directory containment -> exit 1" test_leading_slash_directory_containment
run_test "/./ mixed anchoring normalized -> exit 1" test_leading_slash_dot_mixed
run_test ".. is still not resolved -> exit 0" test_dotdot_still_not_resolved
run_test "empty lists -> exit 0" test_empty_lists
run_test "whitespace-only list entry is ignored -> exit 0" test_whitespace_only_entry_is_ignored
run_test "one empty list -> exit 0" test_one_empty_list
run_test "newline-separated list -> overlap detected, exit 1" test_newline_separated_list_detects_overlap
run_test "CRLF-separated list -> overlap detected, exit 1" test_crlf_separated_list_detects_overlap
run_test "repo root '.' contains everything -> exit 1" test_repo_root_dot_contains_everything
run_test "repo root './' contains everything -> exit 1" test_repo_root_dot_slash_contains_everything
run_test "root '/' contains everything -> exit 1" test_root_slash_contains_everything
run_test "double slash normalized -> exit 1" test_double_slash_normalized
run_test "path named '-n' is not swallowed -> exit 1" test_dash_named_path_not_swallowed
run_test "glob entry prints a NOTE, stays advisory -> exit 0" test_glob_entry_prints_note
run_test "missing second argument -> usage error, exit 2" test_missing_second_argument_is_usage_error
run_test "no arguments -> usage error, exit 2" test_no_arguments_is_usage_error
run_test "shared config file -> warning, exit 0" test_shared_config_warns_not_blocks
run_test "team-config.yml overlap -> warning" test_shared_team_config_warns

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
