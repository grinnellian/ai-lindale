#!/usr/bin/env bash
# DX-012: Pre-dispatch file-overlap detection for parallel worktree safety.
#
# Given two comma-separated lists of files/directories that two agent
# dispatches intend to touch, checks for overlap so a TPM does not fan out
# two Dev agents onto conflicting paths.
#
# This is an advisory script agents/TPM can invoke directly -- it is NOT a
# PreToolUse hook. Hook-based enforcement was retired under EPIC-004
# (container-as-boundary); see CLAUDE.md's Security Boundary section.
#
# Usage: check-file-overlap.sh <comma-separated-list-a> <comma-separated-list-b>
# Exit 0: no overlap (or only shared-config warnings)
# Exit 1: overlapping paths (exact match or directory containment)

set -uo pipefail

LIST_A="${1:-}"
LIST_B="${2:-}"

# Files commonly touched by multiple in-flight tickets (docs/config) --
# report as a warning, not a hard block.
SHARED_CONFIG_FILES=(
  "CLAUDE.md"
  "templates/team-config.yml"
  "package.json"
)

normalize() {
  # Reduce a path to its comparison form. Directory-ness is not tracked
  # separately -- containment below is a pure prefix test, so a directory
  # written with or without a trailing slash compares identically.
  #   - strip surrounding whitespace (a list written "a.ts, b.ts" must not
  #     compare " b.ts" against "b.ts")
  #   - strip a leading "./" ("./src/a.ts" and "src/a.ts" are the same file)
  #   - strip trailing slashes ("docs/" and "docs" are the same directory)
  local p="$1"
  p="${p#"${p%%[![:space:]]*}"}"   # leading whitespace
  p="${p%"${p##*[![:space:]]}"}"   # trailing whitespace
  while [ "$p" != "${p#./}" ]; do
    p="${p#./}"
  done
  while [ "$p" != "${p%/}" ]; do
    p="${p%/}"
  done
  echo "$p"
}

is_shared_config() {
  local path="$1"
  local cfg
  for cfg in "${SHARED_CONFIG_FILES[@]}"; do
    if [ "$path" = "$cfg" ]; then
      return 0
    fi
  done
  return 1
}

IFS=',' read -r -a ARR_A <<< "$LIST_A"
IFS=',' read -r -a ARR_B <<< "$LIST_B"

OVERLAP_FOUND=0

for raw_a in ${ARR_A[@]+"${ARR_A[@]}"}; do
  a="$(normalize "$raw_a")"
  # Skip blank entries *after* normalization -- a trailing comma or a stray
  # space between commas would otherwise yield an empty path that prefixes
  # everything.
  [ -z "$a" ] && continue
  for raw_b in ${ARR_B[@]+"${ARR_B[@]}"}; do
    b="$(normalize "$raw_b")"
    [ -z "$b" ] && continue

    if [ "$a" = "$b" ]; then
      if is_shared_config "$a"; then
        echo "WARNING: shared config file touched by both dispatches: $a"
      else
        echo "OVERLAP: exact file match: $a"
        OVERLAP_FOUND=1
      fi
      continue
    fi

    # Directory containment: one path is a prefix directory of the other,
    # whether or not it was written with a trailing slash (e.g. "src/feature"
    # containing "src/feature/handler.ts").
    case "$b" in
      "$a"/*)
        echo "OVERLAP: $b is inside directory $a"
        OVERLAP_FOUND=1
        ;;
    esac
    case "$a" in
      "$b"/*)
        echo "OVERLAP: $a is inside directory $b"
        OVERLAP_FOUND=1
        ;;
    esac
  done
done

if [ "$OVERLAP_FOUND" -eq 1 ]; then
  exit 1
fi

# Shared-config warnings are advisory only: they are printed above but never
# change the exit status (see the SHARED_CONFIG_FILES comment).
exit 0
