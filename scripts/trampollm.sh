#!/usr/bin/env bash
# FEAT-018: trampollm — continuation trampoline for `claude -p` bounces,
# chained via the BATON v1 contract. See docs/baton.md for the schema.
#
# Dependencies: bash + jq + claude only.
#
# Usage:
#   trampollm.sh --prompt "<initial task prompt>" [OPTIONS]
#
# Exit codes:
#   0  status: DONE reached (clean sentinel termination)
#   1  usage/error trip: retries exhausted, unrecoverable is_error, or
#      malformed baton after one correction
#   2  status: PARK or ESCALATE
#   3  --max-bounces exceeded
#   4  loop detected (identical baton)
#   5  cumulative --max-cost-usd exceeded
set -uo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

DEFAULT_AGENT="dev"
DEFAULT_MAX_BOUNCES=10
DEFAULT_MAX_TURNS=50
DEFAULT_MAX_COST_USD="10.00"
DEFAULT_RETRIES=3

RELAY_PREAMBLE='You are participating in an automated multi-bounce relay chain (trampollm). Read the context below, do the necessary work, then hand off to your successor.

Relay rules:
- Each bounce is a fresh context window; you cannot see any prior conversation except what is provided below.
- You MUST end your final message with a complete "--- BATON v1 ---" ... "--- END BATON ---" block.
- Set status: to exactly one of CONTINUE | DONE | PARK | ESCALATE.
- status: CONTINUE means another bounce will pick up your baton verbatim as its seed context.
- status: DONE means the relay terminates successfully.
- status: PARK or ESCALATE means the relay stops here and a human is notified.
- Emit exactly ONE baton block. If more than one appears, the LAST one is used.

--- CONTEXT ---
'

MALFORMED_CORRECTION='Your previous reply had no valid BATON v1 block (or an invalid status). Re-emit ending with a complete "--- BATON v1 ---" ... "--- END BATON ---" block, with status: set to one of CONTINUE|DONE|PARK|ESCALATE.'

IDENTICAL_CORRECTION='Identical baton detected across bounces (no forward progress). Change your approach and make concrete progress, or set status: PARK if you cannot proceed.'

# ---------------------------------------------------------------------------
# Pure helpers (unit-testable by sourcing this file)
# ---------------------------------------------------------------------------

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "trampollm: jq is required (install: 'apt-get install jq' / 'brew install jq')" >&2
    return 1
  fi
  return 0
}

# require_claude — the whole point of the script is dispatching `claude`.
# Without this pre-flight, a missing/not-on-PATH CLI is indistinguishable
# from an API failure: run_claude's redirect still succeeds, bash reports
# "claude: command not found" into the per-bounce stderr log, and the loop
# burns RETRIES+1 dispatch attempts with backoff before writing a TRIPPED.md
# whose only clue is "rail: error" and an empty last-baton section.
require_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "trampollm: 'claude' not found on PATH (Claude Code CLI is required)" >&2
    return 1
  fi
  return 0
}

# log <msg> — operator-facing progress on stderr. stdout stays clean so the
# script composes into pipelines; an unattended run that prints nothing at
# all (the prior behaviour) is unauditable while it is still running.
log() {
  echo "trampollm: $*" >&2
}

# parse_baton <text> — prints the block between "--- BATON v1 ---" and
# "--- END BATON ---" (inclusive). Prints empty string if absent. If the
# text contains multiple blocks, the LAST one wins.
parse_baton() {
  local text="$1"
  printf '%s\n' "$text" | awk '
    /--- BATON v1 ---/ { inblock=1; buf="" }
    inblock            { buf = buf $0 "\n" }
    /--- END BATON ---/ { if (inblock) { block = buf; inblock = 0 } }
    END { printf "%s", block }
  '
}

# baton_field <block> <key> — prints the value after "<key>:", whitespace-trimmed.
baton_field() {
  local block="$1" key="$2"
  printf '%s\n' "$block" | awk -v k="$key" '
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      prefix = k ":"
      if (substr(line, 1, length(prefix)) == prefix) {
        val = substr(line, length(prefix) + 1)
        sub(/^[ \t]+/, "", val)
        sub(/[ \t]+$/, "", val)
        print val
        exit
      }
    }
  '
}

# baton_status <block> — baton_field block status, uppercased.
baton_status() {
  local block="$1"
  baton_field "$block" "status" | tr '[:lower:]' '[:upper:]'
}

# normalize_baton <block> — strip per-line whitespace, drop the breadcrumbs:
# line entirely, collapse (drop) blank lines. Output feeds hash_baton.
normalize_baton() {
  local block="$1"
  printf '%s\n' "$block" | awk '
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
      if (line ~ /^breadcrumbs:/) next
      if (line == "") next
      print line
    }
  '
}

# hash_baton <block> — stable hash of the normalized block.
hash_baton() {
  local block="$1"
  normalize_baton "$block" | cksum | awk '{print $1}'
}

# build_prompt <seed> — prepend the fixed relay preamble to <seed>.
build_prompt() {
  local seed="$1"
  printf '%s\n%s' "$RELAY_PREAMBLE" "$seed"
}

# ---------------------------------------------------------------------------
# Effectful helpers
# ---------------------------------------------------------------------------

# run_claude <prompt> <agent> <out_json> — invokes claude, writes stdout JSON
# to <out_json>, returns claude's exit code. Never parses .result itself.
# Reads MAX_TURNS / MAX_BUDGET_USD / MODEL from the enclosing script's
# (non-local) variables set by main()'s argument parsing.
run_claude() {
  local prompt="$1" agent="$2" out_json="$3" err_log="$4"
  local args=(-p "$prompt" --output-format json --agent "$agent" --max-turns "${MAX_TURNS:-$DEFAULT_MAX_TURNS}")
  if [ -n "${MAX_BUDGET_USD:-}" ]; then
    args+=(--max-budget-usd "$MAX_BUDGET_USD")
  fi
  if [ -n "${MODEL:-}" ]; then
    args+=(--model "$MODEL")
  fi
  claude "${args[@]}" >"$out_json" 2>"$err_log"
  return $?
}

# is_bad_response <rc> <out_json> — true (0) when the bounce must be treated
# as an error: non-zero exit, invalid JSON, is_error:true, or empty .result.
# Gate on exit code AND .is_error — never on .subtype (stays "success" on
# API errors; the FEAT-017 spike's gotcha).
is_bad_response() {
  local rc="$1" out_json="$2"
  if [ "$rc" -ne 0 ]; then
    return 0
  fi
  if [ ! -s "$out_json" ]; then
    return 0
  fi
  if ! jq -e . "$out_json" >/dev/null 2>&1; then
    return 0
  fi
  if [ "$(jq -r '.is_error // false' "$out_json")" = "true" ]; then
    return 0
  fi
  local result
  result="$(jq -r '.result // empty' "$out_json")"
  if [ -z "$result" ]; then
    return 0
  fi
  return 1
}

# write_baton_file <run_dir> <n> <block> — writes <run_dir>/NNN-baton.md verbatim.
# A failed write (full disk, read-only mount) is announced rather than
# swallowed: the baton chain IS the audit trail, so losing a link silently
# is worse than the run failing loudly.
write_baton_file() {
  local run_dir="$1" n="$2" block="$3"
  local path
  path="$run_dir/$(printf '%03d' "$n")-baton.md"
  if ! printf '%s\n' "$block" >"$path" 2>/dev/null; then
    log "WARNING: could not write $path (disk full / read-only?)"
    return 1
  fi
  return 0
}

# write_tripped <run_dir> <rail> <bounce> <cum_cost> <last_baton>
write_tripped() {
  local run_dir="$1" rail="$2" bounce="$3" cum_cost="$4" last_baton="$5"
  if ! {
    echo "trampollm: TRIPPED"
    echo ""
    echo "rail: $rail"
    echo "bounce: $bounce"
    echo "cumulative_cost_usd: $cum_cost"
    echo ""
    echo "--- last good baton (resume by feeding this back in) ---"
    printf '%s\n' "$last_baton"
  } >"$run_dir/TRIPPED.md" 2>/dev/null; then
    log "WARNING: could not write $run_dir/TRIPPED.md (disk full / read-only?)"
    return 1
  fi
  return 0
}

# escalate_ticket <ticket> <tripped_path> — when <ticket> is non-empty, posts
# a machine comment (batons are unsigned by design) and adds needs-human.
escalate_ticket() {
  local ticket="$1" tripped_path="$2"
  if [ -z "$ticket" ]; then
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "trampollm: gh not found; skipping escalation (TRIPPED.md was still written)" >&2
    return 0
  fi
  local num="${ticket#\#}"
  # Both gh calls' exit codes are checked: escalation IS the page to a human,
  # so a silent failure (expired auth, rate limit, no `needs-human` label in
  # the repo, network down) means nobody ever learns the relay tripped. The
  # trip's own exit code is unaffected -- a failed page must not mask the
  # rail that fired -- but it is now visible on stderr.
  if ! gh issue comment "$num" --body-file "$tripped_path" >/dev/null; then
    log "WARNING: 'gh issue comment $num' failed; nobody was paged. Trip details: $tripped_path"
  fi
  if ! gh issue edit "$num" --add-label needs-human >/dev/null; then
    log "WARNING: 'gh issue edit $num --add-label needs-human' failed (label missing in repo?)"
  fi
}

# comment_bounce <ticket> <baton_path> <bounce> — spec item 4's optional
# per-bounce issue comment, via the same --body-file pattern as escalation.
# Opt-in through --comment-bounces, and deliberately restricted to a ticket
# the OPERATOR passed on the CLI (see main()): a ticket adopted out of a
# baton is model-authored, and one authenticated write per bounce aimed at
# a model-chosen issue is not something to turn on by default.
comment_bounce() {
  local ticket="$1" baton_path="$2" bounce="$3"
  if [ -z "$ticket" ]; then
    log "WARNING: --comment-bounces needs --ticket; skipping comment for bounce $bounce"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    log "WARNING: gh not found; skipping per-bounce comment for bounce $bounce"
    return 0
  fi
  if [ ! -f "$baton_path" ]; then
    return 0
  fi
  local num="${ticket#\#}"
  if ! gh issue comment "$num" --body-file "$baton_path" >/dev/null; then
    log "WARNING: per-bounce 'gh issue comment $num' failed for bounce $bounce"
  fi
}

# accumulate_cost <out_json> — adds this dispatch's .total_cost_usd into the
# enclosing main()'s cum_cost (dynamic scope, same convention as run_claude).
#
# Called for EVERY dispatch, including ones that failed is_bad_response. A
# bounce that errors after doing work is still a billed run, so summing only
# the winning attempt let the cumulative rail under-count without bound:
# observed, two failed attempts billing $3.00 each vanished entirely under a
# --max-cost-usd 1.00 cap and the run exited 0 believing it had spent $0.01.
accumulate_cost() {
  local out_json="$1" c
  [ -s "$out_json" ] || return 0
  # Guard the type: a non-numeric or absent total_cost_usd must contribute 0
  # rather than poison cum_cost into a string and make the awk rail inert.
  c="$(jq -r 'if (.total_cost_usd | type) == "number" then .total_cost_usd else 0 end' "$out_json" 2>/dev/null)"
  case "${c:-}" in
    ''|*[!0-9.eE+-]*) return 0 ;;
  esac
  cum_cost="$(awk -v a="$cum_cost" -v b="$c" 'BEGIN { printf "%s", a + b }')"
  return 0
}

# backoff_sleep <attempt> — sleep(TRAMPOLLM_BACKOFF_BASE * attempt).
# Testability hook: TRAMPOLLM_BACKOFF_BASE=0 in tests so no real waiting.
backoff_sleep() {
  local attempt="$1"
  local base="${TRAMPOLLM_BACKOFF_BASE:-2}"
  sleep "$((base * attempt))"
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: trampollm.sh --prompt "<initial task prompt>" [OPTIONS]

Options:
  --prompt <text>          Seed prompt for bounce 1 (required)
  --agent <role>            Persona for bounce 1 (default: dev)
  --max-bounces <N>         Cross-bounce ceiling (default: 10) -> exit 3
  --max-turns <N>           Native pass-through per call (default: 50)
  --max-budget-usd <X>      Native pass-through per call (unset by default)
  --max-cost-usd <X>        Cumulative cap across bounces (default: 10.00) -> exit 5
  --retries <N>             Retries after the initial attempt (default: 3)
                            -- N+1 total dispatches per bounce on failure
  --ticket <#NNN>           Seeds ticket; trips post a comment + needs-human label
  --comment-bounces         Also post each bounce's baton as an issue comment
                            (takes no value; requires --ticket)
  --run-id <id>             Overridable run id (default: timestamp-pid)
  --model <model>           Native pass-through when set

Every option above except --comment-bounces, -h and --help requires a value;
a trailing value-taking flag with no value (e.g. "trampollm.sh --prompt") is
a usage error -> exit 1.
EOF
}

# require_flag_value <flag> <remaining_arg_count> — exits 1 with a usage
# error if <remaining_arg_count> is less than 2, i.e. <flag> is the last
# positional and has no following value. Without this guard, "${2:-}" masks
# the missing value under `set -u` and a lone trailing flag spins the
# option-parsing loop forever ($# never decrements).
require_flag_value() {
  local flag="$1" remaining="$2"
  if [ "$remaining" -lt 2 ]; then
    echo "trampollm: missing value for $flag" >&2
    usage >&2
    exit 1
  fi
}

# validate_nonneg_int <flag> <value> — exits 1 with a usage error unless
# <value> is a bare non-negative integer. Without this guard, a non-numeric
# --max-bounces/--retries silently disables that rail: `[ "$x" -ge "$y" ]`
# fails with "integer expression expected", the surrounding `if` treats the
# shell error as false (not a trip), and under `set -uo pipefail` (no -e)
# the script sails on with the cap permanently inert -- observed to spin
# forever against a stub that always errors, once --retries is non-numeric.
validate_nonneg_int() {
  local flag="$1" value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "trampollm: $flag requires a non-negative integer, got: $value" >&2
      usage >&2
      exit 1
      ;;
  esac
}

# validate_nonneg_number <flag> <value> — exits 1 with a usage error unless
# <value> is a non-negative integer or decimal. Guards --max-cost-usd /
# --max-budget-usd, whose comparisons go through awk: a non-numeric value
# there doesn't error loudly, it silently makes the cost rail inert (awk
# falls back to string comparison, and a numeric-looking cumulative cost
# string always sorts below a letter-leading string).
validate_nonneg_number() {
  local flag="$1" value="$2"
  case "$value" in
    ''|*[!0-9.]*|*.*.*|.|*.)
      echo "trampollm: $flag requires a non-negative number, got: $value" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main() {
  require_jq || exit 1
  require_claude || exit 1

  local PROMPT=""
  AGENT="$DEFAULT_AGENT"
  local MAX_BOUNCES="$DEFAULT_MAX_BOUNCES"
  MAX_TURNS="$DEFAULT_MAX_TURNS"
  MAX_BUDGET_USD=""
  local MAX_COST_USD="$DEFAULT_MAX_COST_USD"
  local RETRIES="$DEFAULT_RETRIES"
  local TICKET=""
  # CLI_TICKET is TICKET's operator-supplied subset. TICKET may later be
  # adopted from a baton (model-authored); CLI_TICKET never is.
  local CLI_TICKET=""
  local COMMENT_BOUNCES=false
  local RUN_ID
  RUN_ID="$(date +%Y%m%dT%H%M%S)-$$"
  MODEL=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --prompt) require_flag_value "$1" "$#"; PROMPT="$2"; shift 2 ;;
      --agent) require_flag_value "$1" "$#"; AGENT="$2"; shift 2 ;;
      --max-bounces) require_flag_value "$1" "$#"; validate_nonneg_int "$1" "$2"; MAX_BOUNCES="$2"; shift 2 ;;
      --max-turns) require_flag_value "$1" "$#"; validate_nonneg_int "$1" "$2"; MAX_TURNS="$2"; shift 2 ;;
      --max-budget-usd) require_flag_value "$1" "$#"; validate_nonneg_number "$1" "$2"; MAX_BUDGET_USD="$2"; shift 2 ;;
      --max-cost-usd) require_flag_value "$1" "$#"; validate_nonneg_number "$1" "$2"; MAX_COST_USD="$2"; shift 2 ;;
      --retries) require_flag_value "$1" "$#"; validate_nonneg_int "$1" "$2"; RETRIES="$2"; shift 2 ;;
      --ticket) require_flag_value "$1" "$#"; TICKET="$2"; CLI_TICKET="$2"; shift 2 ;;
      --comment-bounces) COMMENT_BOUNCES=true; shift ;;
      --run-id) require_flag_value "$1" "$#"; RUN_ID="$2"; shift 2 ;;
      --model) require_flag_value "$1" "$#"; MODEL="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "trampollm: unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  if [ -z "$PROMPT" ]; then
    echo "trampollm: --prompt is required" >&2
    usage >&2
    exit 1
  fi

  if [ "$COMMENT_BOUNCES" = true ] && [ -z "$CLI_TICKET" ]; then
    echo "trampollm: --comment-bounces requires --ticket" >&2
    usage >&2
    exit 1
  fi

  local run_dir="memory/trampoline/${RUN_ID}"
  # An unchecked mkdir is a 3am failure mode: on a read-only mount or a full
  # disk every subsequent `>"$out_json"` redirect fails BEFORE claude is
  # execed, the loop reads that as an API error, burns RETRIES+1 attempts,
  # and then cannot write TRIPPED.md either -- so the run dies with a wall of
  # "No such file or directory" and no artifact at all. Fail here instead.
  if ! mkdir -p "$run_dir" 2>/dev/null; then
    echo "trampollm: cannot create run directory '$run_dir' (read-only, full, or bad --run-id?)" >&2
    exit 1
  fi
  if [ ! -w "$run_dir" ]; then
    echo "trampollm: run directory '$run_dir' is not writable" >&2
    exit 1
  fi
  # A stale TRIPPED.md from an earlier run reusing this --run-id would
  # outlive a subsequent clean run and make it look like it tripped.
  if [ -f "$run_dir/TRIPPED.md" ]; then
    log "run dir $run_dir already holds a TRIPPED.md from an earlier run with this --run-id; removing it"
    rm -f "$run_dir/TRIPPED.md"
  fi

  local prompt seed
  seed="$PROMPT"
  prompt="$(build_prompt "$seed")"

  local bounce=0
  local cum_cost="0"
  local last_hash=""
  local identical_count=0
  local corrected_malformed=false
  local last_good_block=""

  # Installed only here (not at source time, so the test harness can source
  # this file for its pure helpers without inheriting a trap). Every local it
  # reads is already assigned above; the :- guards are belt-and-braces
  # against `set -u` should that ever stop being true.
  trap 'log "exit $? after ${bounce:-0} bounce(s), cumulative cost \$${cum_cost:-0} -- artifacts in ${run_dir:-?}"' EXIT

  log "run ${RUN_ID}: starting, agent=$AGENT, max-bounces=$MAX_BOUNCES, max-cost-usd=$MAX_COST_USD, artifacts in $run_dir"

  while :; do
    if [ "$bounce" -ge "$MAX_BOUNCES" ]; then
      log "TRIP: --max-bounces $MAX_BOUNCES reached"
      write_tripped "$run_dir" "max-bounces" "$bounce" "$cum_cost" "$last_good_block"
      escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
      exit 3
    fi

    if awk -v c="$cum_cost" -v m="$MAX_COST_USD" 'BEGIN { exit !(c >= m) }'; then
      log "TRIP: cumulative cost \$$cum_cost reached --max-cost-usd $MAX_COST_USD"
      write_tripped "$run_dir" "max-cost-usd" "$bounce" "$cum_cost" "$last_good_block"
      escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
      exit 5
    fi

    bounce=$((bounce + 1))
    local out_json err_log padded
    padded="$(printf '%03d' "$bounce")"
    out_json="$run_dir/${padded}-response.json"
    err_log="$run_dir/${padded}-stderr.log"

    local attempt=0
    local rc
    while :; do
      run_claude "$prompt" "$AGENT" "$out_json" "$err_log"
      rc=$?
      # Bill first, judge second: a dispatch that failed still cost money.
      accumulate_cost "$out_json"
      if ! is_bad_response "$rc" "$out_json"; then
        break
      fi
      attempt=$((attempt + 1))
      log "bounce $bounce: dispatch failed (rc=$rc), attempt $attempt of $((RETRIES + 1)); see $err_log"
      # --retries N means N retries AFTER the initial attempt, i.e. N+1
      # total dispatches per bounce on continuous failure: attempt only
      # trips once it exceeds RETRIES (strictly greater than), not on
      # reaching it.
      if [ "$attempt" -gt "$RETRIES" ]; then
        write_tripped "$run_dir" "error" "$bounce" "$cum_cost" "$last_good_block"
        escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
        exit 1
      fi
      # The cost rail is checked at the top of every bounce, but retries are
      # dispatches too: without this, a bounce whose attempts each bill
      # heavily could blow clean through the cumulative cap before the loop
      # ever gets back to the top. Only reached on the retry path, so a
      # successful bounce that lands exactly on the cap still completes.
      if awk -v c="$cum_cost" -v m="$MAX_COST_USD" 'BEGIN { exit !(c >= m) }'; then
        log "cumulative cost $cum_cost reached --max-cost-usd $MAX_COST_USD mid-bounce; stopping retries"
        write_tripped "$run_dir" "max-cost-usd" "$bounce" "$cum_cost" "$last_good_block"
        escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
        exit 5
      fi
      # Keep the failed attempt's artifacts; the retry is about to clobber
      # the canonical NNN- paths. The LAST (fatal) attempt deliberately keeps
      # the canonical name, since that is the one an operator opens first.
      mv -f "$out_json" "$run_dir/${padded}-attempt${attempt}-response.json" 2>/dev/null
      mv -f "$err_log" "$run_dir/${padded}-attempt${attempt}-stderr.log" 2>/dev/null
      backoff_sleep "$attempt"
    done

    local result
    result="$(jq -r '.result // empty' "$out_json")"
    local block
    block="$(parse_baton "$result")"

    local status=""
    if [ -n "$block" ]; then
      status="$(baton_status "$block")"
    fi

    case "$status" in
      CONTINUE|DONE|PARK|ESCALATE) ;;
      *)
        if [ "$corrected_malformed" = false ]; then
          corrected_malformed=true
          log "bounce $bounce: no valid baton; re-prompting once with the correction"
          # Re-send the SEED alongside the correction. Every bounce is a fresh
          # context window -- the preamble says so explicitly -- so a bare
          # correction asks a model that has never seen the task to "re-emit"
          # something it has no knowledge of. That paid bounce could only ever
          # produce another malformed baton, turning a recoverable hiccup into
          # a guaranteed exit-1 trip.
          prompt="$(build_prompt "$seed

$MALFORMED_CORRECTION")"
          continue
        else
          write_tripped "$run_dir" "malformed-baton" "$bounce" "$cum_cost" "$last_good_block"
          escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
          exit 1
        fi
        ;;
    esac
    corrected_malformed=false

    write_baton_file "$run_dir" "$bounce" "$block"
    last_good_block="$block"
    log "bounce $bounce: status=$status agent=$AGENT cumulative cost \$$cum_cost"

    if [ "$COMMENT_BOUNCES" = true ]; then
      comment_bounce "$CLI_TICKET" "$run_dir/${padded}-baton.md" "$bounce"
    fi

    if [ -z "$TICKET" ]; then
      local baton_ticket
      baton_ticket="$(baton_field "$block" "ticket")"
      if [ -n "$baton_ticket" ]; then
        TICKET="$baton_ticket"
      fi
    fi

    local h
    h="$(hash_baton "$block")"
    if [ "$h" = "$last_hash" ]; then
      identical_count=$((identical_count + 1))
    else
      identical_count=1
      last_hash="$h"
    fi

    if [ "$identical_count" -eq 2 ]; then
      log "bounce $bounce: identical baton; re-prompting once with the correction"
      # Same fresh-context reasoning as the malformed path: the repeated
      # baton has to travel WITH the scolding, or the corrective bounce is
      # told to "change your approach" with no idea what the approach was.
      prompt="$(build_prompt "$block

$IDENTICAL_CORRECTION")"
      continue
    fi
    if [ "$identical_count" -ge 3 ]; then
      log "TRIP: identical baton $identical_count times running (insanity loop)"
      write_tripped "$run_dir" "loop-detected" "$bounce" "$cum_cost" "$last_good_block"
      escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
      exit 4
    fi

    case "$status" in
      DONE)
        log "DONE: relay terminated cleanly at bounce $bounce"
        exit 0
        ;;
      PARK|ESCALATE)
        local rail
        rail="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
        log "TRIP: relay stopped by status: $status"
        write_tripped "$run_dir" "$rail" "$bounce" "$cum_cost" "$last_good_block"
        escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
        exit 2
        ;;
      CONTINUE)
        local next_agent
        next_agent="$(baton_field "$block" "next-agent")"
        if [ -n "$next_agent" ] && [ "$next_agent" != "<same>" ]; then
          AGENT="$next_agent"
        fi
        seed="$block"
        prompt="$(build_prompt "$seed")"
        ;;
    esac
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
