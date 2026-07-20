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
  local prompt="$1" agent="$2" out_json="$3"
  local args=(-p "$prompt" --output-format json --agent "$agent" --max-turns "${MAX_TURNS:-$DEFAULT_MAX_TURNS}")
  if [ -n "${MAX_BUDGET_USD:-}" ]; then
    args+=(--max-budget-usd "$MAX_BUDGET_USD")
  fi
  if [ -n "${MODEL:-}" ]; then
    args+=(--model "$MODEL")
  fi
  claude "${args[@]}" >"$out_json" 2>/dev/null
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
write_baton_file() {
  local run_dir="$1" n="$2" block="$3"
  printf '%s\n' "$block" >"$run_dir/$(printf '%03d' "$n")-baton.md"
}

# write_tripped <run_dir> <rail> <bounce> <cum_cost> <last_baton>
write_tripped() {
  local run_dir="$1" rail="$2" bounce="$3" cum_cost="$4" last_baton="$5"
  {
    echo "trampollm: TRIPPED"
    echo ""
    echo "rail: $rail"
    echo "bounce: $bounce"
    echo "cumulative_cost_usd: $cum_cost"
    echo ""
    echo "--- last good baton (resume by feeding this back in) ---"
    printf '%s\n' "$last_baton"
  } >"$run_dir/TRIPPED.md"
}

# escalate_ticket <ticket> <tripped_path> — when <ticket> is non-empty, posts
# a machine comment (batons are unsigned by design) and adds needs-human.
escalate_ticket() {
  local ticket="$1" tripped_path="$2"
  if [ -z "$ticket" ]; then
    return 0
  fi
  local num="${ticket#\#}"
  gh issue comment "$num" --body-file "$tripped_path" >/dev/null
  gh issue edit "$num" --add-label needs-human >/dev/null
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
  --retries <N>             Error retries per bounce (default: 3)
  --ticket <#NNN>           Seeds ticket; trips post a comment + needs-human label
  --run-id <id>             Overridable run id (default: timestamp-pid)
  --model <model>           Native pass-through when set
EOF
}

main() {
  require_jq || exit 1

  local PROMPT=""
  AGENT="$DEFAULT_AGENT"
  local MAX_BOUNCES="$DEFAULT_MAX_BOUNCES"
  MAX_TURNS="$DEFAULT_MAX_TURNS"
  MAX_BUDGET_USD=""
  local MAX_COST_USD="$DEFAULT_MAX_COST_USD"
  local RETRIES="$DEFAULT_RETRIES"
  local TICKET=""
  local RUN_ID
  RUN_ID="$(date +%Y%m%dT%H%M%S)-$$"
  MODEL=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --prompt) PROMPT="${2:-}"; shift 2 ;;
      --agent) AGENT="${2:-}"; shift 2 ;;
      --max-bounces) MAX_BOUNCES="${2:-}"; shift 2 ;;
      --max-turns) MAX_TURNS="${2:-}"; shift 2 ;;
      --max-budget-usd) MAX_BUDGET_USD="${2:-}"; shift 2 ;;
      --max-cost-usd) MAX_COST_USD="${2:-}"; shift 2 ;;
      --retries) RETRIES="${2:-}"; shift 2 ;;
      --ticket) TICKET="${2:-}"; shift 2 ;;
      --run-id) RUN_ID="${2:-}"; shift 2 ;;
      --model) MODEL="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "trampollm: unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  if [ -z "$PROMPT" ]; then
    echo "trampollm: --prompt is required" >&2
    usage >&2
    exit 1
  fi

  local run_dir="memory/trampoline/${RUN_ID}"
  mkdir -p "$run_dir"

  local prompt
  prompt="$(build_prompt "$PROMPT")"

  local bounce=0
  local cum_cost="0"
  local last_hash=""
  local identical_count=0
  local corrected_malformed=false
  local last_good_block=""

  while :; do
    if [ "$bounce" -ge "$MAX_BOUNCES" ]; then
      write_tripped "$run_dir" "max-bounces" "$bounce" "$cum_cost" "$last_good_block"
      escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
      exit 3
    fi

    if awk -v c="$cum_cost" -v m="$MAX_COST_USD" 'BEGIN { exit !(c >= m) }'; then
      write_tripped "$run_dir" "max-cost-usd" "$bounce" "$cum_cost" "$last_good_block"
      escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
      exit 5
    fi

    bounce=$((bounce + 1))
    local out_json="$run_dir/$(printf '%03d' "$bounce")-response.json"

    local attempt=0
    local rc
    while :; do
      run_claude "$prompt" "$AGENT" "$out_json"
      rc=$?
      if ! is_bad_response "$rc" "$out_json"; then
        break
      fi
      attempt=$((attempt + 1))
      if [ "$attempt" -ge "$RETRIES" ]; then
        write_tripped "$run_dir" "error" "$bounce" "$cum_cost" "$last_good_block"
        escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
        exit 1
      fi
      backoff_sleep "$attempt"
    done

    local bounce_cost
    bounce_cost="$(jq -r '.total_cost_usd // 0' "$out_json")"
    cum_cost="$(awk -v a="$cum_cost" -v b="$bounce_cost" 'BEGIN { printf "%s", a + b }')"

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
          prompt="$(build_prompt "$MALFORMED_CORRECTION")"
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
      prompt="$(build_prompt "$IDENTICAL_CORRECTION")"
      continue
    fi
    if [ "$identical_count" -ge 3 ]; then
      write_tripped "$run_dir" "loop-detected" "$bounce" "$cum_cost" "$last_good_block"
      escalate_ticket "$TICKET" "$run_dir/TRIPPED.md"
      exit 4
    fi

    case "$status" in
      DONE)
        exit 0
        ;;
      PARK|ESCALATE)
        local rail
        rail="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
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
        prompt="$(build_prompt "$block")"
        ;;
    esac
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
