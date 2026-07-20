#!/usr/bin/env bash
# FEAT-018: Tests for scripts/trampollm.sh (the continuation trampoline).
# Run from repo root: bash scripts/tests/test-trampollm.sh
#
# Zero API spend: `claude` and `gh` are PATH shims (canned JSON fixtures /
# call loggers). The real CLIs are never invoked.

set -euo pipefail

PASS=0
FAIL=0
TMPDIR_BASE=""

# Capture REPO_ROOT before any cd operations
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRAMPOLLM="$REPO_ROOT/scripts/trampollm.sh"

PROJECT=""
STUB_DIR=""
rc=0

# --- Setup / teardown ---

setup_project() {
  TMPDIR_BASE=$(mktemp -d)
  PROJECT="$TMPDIR_BASE/project"
  mkdir -p "$PROJECT/bin" "$PROJECT/fixtures"
  cd "$PROJECT"
  STUB_DIR="$PROJECT/fixtures"
  export STUB_DIR

  cat >bin/claude <<'STUB'
#!/usr/bin/env bash
# stub claude — emits canned JSON per invocation, logs args, zero API spend.
# Args (notably --prompt) may contain embedded newlines, so each call's args
# are followed by a delimiter line -- callers must split calls.log on it
# rather than assuming "one call == one line".
n=$(cat "$STUB_DIR/counter" 2>/dev/null || echo 0); n=$((n+1))
printf '%s\n' "$n" > "$STUB_DIR/counter"
printf '%s\n' "$*" >> "$STUB_DIR/calls.log"
printf '%s\n' "---END-CALL---" >> "$STUB_DIR/calls.log"
cat "$STUB_DIR/response_${n}.json" 2>/dev/null
exit "$(cat "$STUB_DIR/response_${n}.exit" 2>/dev/null || echo 0)"
STUB
  chmod +x bin/claude

  cat >bin/gh <<'STUB'
#!/usr/bin/env bash
# stub gh — records comment/label calls, zero network.
printf '%s\n' "$*" >> "$STUB_DIR/gh.log"
exit 0
STUB
  chmod +x bin/gh
}

teardown() {
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap teardown EXIT

# --- Fixture builders ---

# baton_block <status> <next_step> [next_agent] [ticket] [breadcrumbs]
baton_block() {
  local status="$1" next_step="$2" next_agent="${3:-<same>}" ticket="${4-#108}" breadcrumbs="${5:-none}"
  printf -- '--- BATON v1 ---\nstatus: %s\ngoal: relay test goal\nticket: %s\nnext-agent: %s\ndone-criteria: counter reaches threshold\nstate: in progress\nnext-step: %s\nbreadcrumbs: %s\n--- END BATON ---' \
    "$status" "$ticket" "$next_agent" "$next_step" "$breadcrumbs"
}

# fixture_ok <n> <result_text> [cost]
fixture_ok() {
  local n="$1" result_text="$2" cost="${3:-0.01}"
  jq -n --arg result "$result_text" --argjson cost "$cost" \
    '{result: $result, session_id: "sess-test", total_cost_usd: $cost, is_error: false, subtype: "success", terminal_reason: "stop", num_turns: 3}' \
    >"$STUB_DIR/response_${n}.json"
}

# fixture_error <n> [result_text] [exit_code] [cost]
fixture_error() {
  local n="$1" result_text="${2:-API error: bogus model}" exit_code="${3:-1}" cost="${4:-0}"
  jq -n --arg result "$result_text" --argjson cost "$cost" \
    '{result: $result, session_id: "sess-test", total_cost_usd: $cost, is_error: true, subtype: "success", terminal_reason: "api_error", num_turns: 1}' \
    >"$STUB_DIR/response_${n}.json"
  printf '%s\n' "$exit_code" >"$STUB_DIR/response_${n}.exit"
}

# --- Assertions ---

assert_eq() {
  local expected="$1" actual="$2" label="${3:-value}"
  if [ "$expected" = "$actual" ]; then
    return 0
  else
    echo "    $label: expected [$expected], got [$actual]"
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

assert_file_not_exists() {
  local path="$1"
  if [ -f "$path" ]; then
    echo "    File should NOT exist: $path"
    return 1
  fi
  return 0
}

assert_file_contains() {
  local path="$1" pattern="$2"
  if grep -qF -- "$pattern" "$path" 2>/dev/null; then
    return 0
  else
    echo "    File $path does not contain: $pattern"
    return 1
  fi
}

# calls.log entries are delimited by "---END-CALL---" (args can contain
# embedded newlines, e.g. --prompt text, so raw line numbers don't map to
# call numbers).

# call_block <path> <n> — prints the raw args text for call N.
call_block() {
  local path="$1" n="$2"
  awk -v RS='---END-CALL---\n' -v n="$n" 'NR==n { print; exit }' "$path" 2>/dev/null
}

assert_call_contains() {
  local path="$1" n="$2" pattern="$3"
  local block
  block="$(call_block "$path" "$n")"
  if printf '%s' "$block" | grep -qF -- "$pattern"; then
    return 0
  else
    echo "    Call $n in $path does not contain: $pattern"
    echo "    Actual call $n: $block"
    return 1
  fi
}

assert_call_count() {
  local path="$1" expected="$2"
  local actual
  actual="$(grep -c '^---END-CALL---$' "$path" 2>/dev/null || true)"
  actual="${actual:-0}"
  assert_eq "$expected" "$actual" "call count of $path"
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

# call_fn <fn> [args...] — run a pure helper from trampollm.sh in an
# isolated subshell (source-guard prevents main() from firing).
call_fn() {
  ( source "$TRAMPOLLM"; "$@" )
}

# run_trampollm [args...] — invoke trampollm.sh against the current
# PROJECT's stubs, deterministic run-id, zero backoff. Sets $rc.
run_trampollm() {
  set +e
  PATH="$PROJECT/bin:$PATH" TRAMPOLLM_BACKOFF_BASE=0 \
    bash "$TRAMPOLLM" "$@" --run-id test-run >"$PROJECT/stdout.log" 2>"$PROJECT/stderr.log"
  rc=$?
  set -e
}

RUN_DIR="memory/trampoline/test-run"

# ===========================================================================
# Phase 1 — helpers & guards
# ===========================================================================

test_require_jq_fails_without_jq() {
  local out fnrc
  set +e
  out=$(
    (
      PATH="/nonexistent-only-dir-$$"
      source "$TRAMPOLLM"
      require_jq
    ) 2>&1
  )
  fnrc=$?
  set -e
  [ "$fnrc" -eq 1 ] || { echo "    expected rc=1, got $fnrc"; return 1; }
  echo "$out" | grep -qi "jq is required" || { echo "    missing 'jq is required' hint: $out"; return 1; }
  echo "$out" | grep -qi "install" || { echo "    missing install hint: $out"; return 1; }
}

test_parse_baton_extracts_from_prose() {
  local text block
  text="Some prose before.

$(baton_block CONTINUE step1)

Some prose after."
  block="$(call_fn parse_baton "$text")"
  printf '%s' "$block" | grep -qF -- '--- BATON v1 ---' || { echo "    missing start fence: $block"; return 1; }
  printf '%s' "$block" | grep -qF -- '--- END BATON ---' || { echo "    missing end fence: $block"; return 1; }
  printf '%s' "$block" | grep -qF 'status: CONTINUE' || { echo "    missing status line: $block"; return 1; }
}

test_parse_baton_empty_when_no_fence() {
  local block
  block="$(call_fn parse_baton "just plain prose, no baton block here at all")"
  assert_eq "" "$block" "parse_baton with no fence"
}

test_parse_baton_returns_last_block() {
  local text block
  text="$(baton_block CONTINUE first-step)

some interstitial prose

$(baton_block CONTINUE second-step)"
  block="$(call_fn parse_baton "$text")"
  printf '%s' "$block" | grep -qF 'next-step: second-step' || { echo "    expected last block (second-step): $block"; return 1; }
  if printf '%s' "$block" | grep -qF 'next-step: first-step'; then
    echo "    block unexpectedly contains the first block's next-step: $block"
    return 1
  fi
}

test_baton_field_whitespace_tolerant() {
  local block status next_agent ticket
  block="$(printf -- '--- BATON v1 ---\nstatus:   continue  \ngoal: g\nticket:  #108 \nnext-agent:  architect \ndone-criteria: c\nstate: s\nnext-step: n\nbreadcrumbs: none\n--- END BATON ---')"
  status="$(call_fn baton_status "$block")"
  next_agent="$(call_fn baton_field "$block" "next-agent")"
  ticket="$(call_fn baton_field "$block" "ticket")"
  assert_eq "CONTINUE" "$status" "baton_status" &&
  assert_eq "architect" "$next_agent" "next-agent field" &&
  assert_eq "#108" "$ticket" "ticket field"
}

test_normalize_hash_stable_across_breadcrumbs() {
  local block_a block_b hash_a hash_b
  block_a="$(baton_block CONTINUE step1 architect '#108' 'none')"
  block_b="$(baton_block CONTINUE step1 architect '#108' 'tried X, failed with Y')"
  hash_a="$(call_fn hash_baton "$block_a")"
  hash_b="$(call_fn hash_baton "$block_b")"
  assert_eq "$hash_a" "$hash_b" "hash stable across breadcrumbs-only diff"
}

test_hash_differs_on_next_step_change() {
  local block_a block_c hash_a hash_c
  block_a="$(baton_block CONTINUE step1 architect '#108' 'none')"
  block_c="$(baton_block CONTINUE step2 architect '#108' 'none')"
  hash_a="$(call_fn hash_baton "$block_a")"
  hash_c="$(call_fn hash_baton "$block_c")"
  if [ "$hash_a" = "$hash_c" ]; then
    echo "    hash should differ when next-step changes"
    return 1
  fi
  return 0
}

# ===========================================================================
# Phase 2 — single bounce & the is_error gotcha
# ===========================================================================

test_clean_single_bounce_done() {
  setup_project
  fixture_ok 1 "work done.

$(baton_block DONE final)" 0.01
  run_trampollm --prompt "do the thing"
  assert_eq 0 "$rc" "exit code" &&
  assert_file_exists "$RUN_DIR/001-baton.md" &&
  assert_file_contains "$RUN_DIR/001-baton.md" "status: DONE"
}

test_is_error_gates_before_result() {
  setup_project
  fixture_error 1 "malicious prose that must never be dispatched" 1 0
  fixture_error 2 "malicious prose that must never be dispatched" 1 0
  fixture_error 3 "malicious prose that must never be dispatched" 1 0
  run_trampollm --prompt "do the thing"
  assert_eq 1 "$rc" "exit code" &&
  assert_file_exists "$RUN_DIR/TRIPPED.md" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: error" &&
  assert_file_not_exists "$RUN_DIR/001-baton.md"
}

test_is_error_gotcha_ignores_subtype_success() {
  setup_project
  # exit 1, is_error:true, but subtype stays "success" — the FEAT-017 gotcha.
  fixture_error 1 "misleading prose" 1 0
  run_trampollm --prompt "do the thing" --retries 1
  assert_eq 1 "$rc" "exit code" &&
  assert_file_exists "$RUN_DIR/TRIPPED.md" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: error" &&
  assert_call_count "$STUB_DIR/calls.log" 1
}

# ===========================================================================
# Phase 3 — multi-bounce loop
# ===========================================================================

test_sentinel_termination_three_continue_then_done() {
  setup_project
  fixture_ok 1 "step one.

$(baton_block CONTINUE step1)" 0.01
  fixture_ok 2 "step two.

$(baton_block CONTINUE step2)" 0.01
  fixture_ok 3 "step three.

$(baton_block CONTINUE step3)" 0.01
  fixture_ok 4 "step four, done.

$(baton_block DONE step4)" 0.01
  run_trampollm --prompt "start the relay"
  assert_eq 0 "$rc" "exit code" &&
  assert_file_exists "$RUN_DIR/001-baton.md" &&
  assert_file_exists "$RUN_DIR/002-baton.md" &&
  assert_file_exists "$RUN_DIR/003-baton.md" &&
  assert_file_exists "$RUN_DIR/004-baton.md"
}

test_next_agent_routing() {
  setup_project
  fixture_ok 1 "bounce one.

$(baton_block CONTINUE step1 architect)" 0.01
  fixture_ok 2 "bounce two, done.

$(baton_block DONE step2)" 0.01
  run_trampollm --prompt "start" --agent dev
  assert_eq 0 "$rc" "exit code" &&
  assert_call_contains "$STUB_DIR/calls.log" 1 "--agent dev" &&
  assert_call_contains "$STUB_DIR/calls.log" 2 "--agent architect"
}

test_baton_audit_trail_verbatim() {
  setup_project
  fixture_ok 1 "bounce one.

$(baton_block CONTINUE unique-marker-abc)" 0.01
  fixture_ok 2 "bounce two, done.

$(baton_block DONE unique-marker-xyz)" 0.01
  run_trampollm --prompt "start"
  assert_eq 0 "$rc" "exit code" &&
  assert_file_contains "$RUN_DIR/001-baton.md" "unique-marker-abc" &&
  assert_file_contains "$RUN_DIR/002-baton.md" "unique-marker-xyz"
}

test_pass_through_flags_every_call() {
  setup_project
  fixture_ok 1 "bounce one.

$(baton_block CONTINUE step1)" 0.01
  fixture_ok 2 "bounce two, done.

$(baton_block DONE step2)" 0.01
  run_trampollm --prompt "start" --max-turns 7 --max-budget-usd 0.5
  assert_eq 0 "$rc" "exit code" &&
  assert_call_contains "$STUB_DIR/calls.log" 1 "--max-turns 7" &&
  assert_call_contains "$STUB_DIR/calls.log" 1 "--max-budget-usd 0.5" &&
  assert_call_contains "$STUB_DIR/calls.log" 2 "--max-turns 7" &&
  assert_call_contains "$STUB_DIR/calls.log" 2 "--max-budget-usd 0.5"
}

# ===========================================================================
# Phase 4 — rails
# ===========================================================================

test_max_bounces_trip() {
  setup_project
  fixture_ok 1 "bounce one.

$(baton_block CONTINUE step1)" 0.01
  fixture_ok 2 "bounce two.

$(baton_block CONTINUE step2)" 0.01
  run_trampollm --prompt "start" --max-bounces 2
  assert_eq 3 "$rc" "exit code" &&
  assert_file_exists "$RUN_DIR/TRIPPED.md" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: max-bounces"
}

test_cumulative_cost_trip_before_dispatch() {
  setup_project
  fixture_ok 1 "bounce one.

$(baton_block CONTINUE step1)" 0.015
  fixture_ok 2 "bounce two.

$(baton_block CONTINUE step2)" 0.015
  fixture_ok 3 "bounce three -- should never be dispatched.

$(baton_block CONTINUE step3)" 0.015
  run_trampollm --prompt "start" --max-cost-usd 0.02
  assert_eq 5 "$rc" "exit code" &&
  assert_file_exists "$RUN_DIR/TRIPPED.md" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: max-cost-usd" &&
  assert_call_count "$STUB_DIR/calls.log" 2
}

test_identical_baton_loop_detection() {
  setup_project
  fixture_ok 1 "bounce one.

$(baton_block CONTINUE same-step)" 0.01
  fixture_ok 2 "bounce two, identical.

$(baton_block CONTINUE same-step)" 0.01
  fixture_ok 3 "bounce three, identical again.

$(baton_block CONTINUE same-step)" 0.01
  run_trampollm --prompt "start"
  assert_eq 4 "$rc" "exit code" &&
  assert_call_contains "$STUB_DIR/calls.log" 3 "Identical baton detected" &&
  assert_file_exists "$RUN_DIR/TRIPPED.md" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: loop-detected"
}

test_error_retry_with_backoff_then_success() {
  setup_project
  fixture_error 1 "transient error" 1 0
  fixture_error 2 "transient error" 1 0
  fixture_ok 3 "recovered, done.

$(baton_block DONE recovered)" 0.01
  run_trampollm --prompt "start" --retries 3
  assert_eq 0 "$rc" "exit code" &&
  assert_call_count "$STUB_DIR/calls.log" 3
}

test_error_retries_exhausted_trips() {
  setup_project
  fixture_error 1 "transient error" 1 0
  fixture_error 2 "transient error" 1 0
  fixture_error 3 "transient error" 1 0
  run_trampollm --prompt "start" --retries 3
  assert_eq 1 "$rc" "exit code" &&
  assert_call_count "$STUB_DIR/calls.log" 3 &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: error"
}

test_malformed_baton_one_correction_then_trip() {
  setup_project
  fixture_ok 1 "no baton block in this reply at all." 0.01
  fixture_ok 2 "still no baton block in this reply either." 0.01
  run_trampollm --prompt "start"
  assert_eq 1 "$rc" "exit code" &&
  assert_call_contains "$STUB_DIR/calls.log" 2 "no valid BATON v1 block" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: malformed-baton"
}

test_status_park_trips() {
  setup_project
  fixture_ok 1 "parking.

$(baton_block PARK blocked-on-human)" 0.01
  run_trampollm --prompt "start"
  assert_eq 2 "$rc" "exit code" &&
  assert_file_exists "$RUN_DIR/TRIPPED.md" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: park"
}

test_status_escalate_trips() {
  setup_project
  fixture_ok 1 "escalating.

$(baton_block ESCALATE needs-human-call)" 0.01
  run_trampollm --prompt "start"
  assert_eq 2 "$rc" "exit code" &&
  assert_file_exists "$RUN_DIR/TRIPPED.md" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: escalate"
}

# ===========================================================================
# Phase 5 — trip observability & escalation
# ===========================================================================

test_tripped_md_content() {
  setup_project
  fixture_ok 1 "bounce one.

$(baton_block CONTINUE marker-content-check)" 0.01
  fixture_ok 2 "bounce two.

$(baton_block CONTINUE step2)" 0.01
  run_trampollm --prompt "start" --max-bounces 2
  assert_eq 3 "$rc" "exit code" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "rail: max-bounces" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "bounce: 2" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "cumulative_cost_usd:" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "--- BATON v1 ---" &&
  assert_file_contains "$RUN_DIR/TRIPPED.md" "step2"
}

test_escalation_with_ticket() {
  setup_project
  fixture_ok 1 "bounce one.

$(baton_block CONTINUE step1)" 0.01
  run_trampollm --prompt "start" --max-bounces 1 --ticket 108
  assert_eq 3 "$rc" "exit code" &&
  assert_file_exists "$STUB_DIR/gh.log" &&
  assert_file_contains "$STUB_DIR/gh.log" "issue comment 108" &&
  assert_file_contains "$STUB_DIR/gh.log" "issue edit 108 --add-label needs-human"
}

test_no_escalation_without_ticket() {
  setup_project
  # baton_block's ticket arg is set empty here — otherwise the baton's own
  # "ticket:" field would be picked up by the "baton can supply it" rule and
  # this would no longer be testing the no-ticket path.
  fixture_ok 1 "bounce one.

$(baton_block CONTINUE step1 '<same>' '')" 0.01
  run_trampollm --prompt "start" --max-bounces 1
  assert_eq 3 "$rc" "exit code" &&
  assert_file_not_exists "$STUB_DIR/gh.log"
}

# --- Run all tests ---

echo "=== FEAT-018 trampollm Tests ==="
echo ""
echo "--- phase 1: helpers & guards ---"
run_test "require_jq fails with install hint when jq absent" test_require_jq_fails_without_jq
run_test "parse_baton extracts block from surrounding prose" test_parse_baton_extracts_from_prose
run_test "parse_baton returns empty when no fence" test_parse_baton_empty_when_no_fence
run_test "parse_baton returns the last block when two present" test_parse_baton_returns_last_block
run_test "baton_field/baton_status whitespace-tolerant" test_baton_field_whitespace_tolerant
run_test "hash_baton stable across breadcrumbs-only diff" test_normalize_hash_stable_across_breadcrumbs
run_test "hash_baton differs on next-step change" test_hash_differs_on_next_step_change
echo ""
echo "--- phase 2: single bounce & is_error gotcha ---"
run_test "clean single bounce DONE -> exit 0, writes 001-baton.md" test_clean_single_bounce_done
run_test "is_error gates before .result is dispatched" test_is_error_gates_before_result
run_test "gotcha: is_error true + subtype success still trips as error" test_is_error_gotcha_ignores_subtype_success
echo ""
echo "--- phase 3: multi-bounce loop ---"
run_test "sentinel termination: 3 CONTINUE then DONE -> exit 0" test_sentinel_termination_three_continue_then_done
run_test "next-agent routing switches --agent on later bounces" test_next_agent_routing
run_test "baton audit trail written verbatim per bounce" test_baton_audit_trail_verbatim
run_test "pass-through flags appear on every call" test_pass_through_flags_every_call
echo ""
echo "--- phase 4: rails ---"
run_test "--max-bounces trip -> exit 3" test_max_bounces_trip
run_test "cumulative cost trip checked before dispatch -> exit 5" test_cumulative_cost_trip_before_dispatch
run_test "identical-baton loop detection -> exit 4" test_identical_baton_loop_detection
run_test "error retry with backoff then success -> exit 0" test_error_retry_with_backoff_then_success
run_test "error retries exhausted -> exit 1" test_error_retries_exhausted_trips
run_test "malformed baton: one correction then trip -> exit 1" test_malformed_baton_one_correction_then_trip
run_test "status PARK trips -> exit 2" test_status_park_trips
run_test "status ESCALATE trips -> exit 2" test_status_escalate_trips
echo ""
echo "--- phase 5: trip observability & escalation ---"
run_test "TRIPPED.md contains rail/bounce/cost/last-baton" test_tripped_md_content
run_test "escalation posts gh comment + needs-human label when ticket set" test_escalation_with_ticket
run_test "no gh calls when ticket unset" test_no_escalation_without_ticket
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
