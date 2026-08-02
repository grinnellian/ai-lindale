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
# Usage: check-file-overlap.sh <path-list-a> <path-list-b>
#        (each list comma- and/or newline-separated; see Input contract)
# Exit 0: no overlap (or only shared-config warnings)
# Exit 1: overlapping paths (exact match or directory containment)
# Exit 2: usage error (wrong argument count)
#
# Input contract:
#   - Entries are separated by commas; newlines (and CRLF) are also accepted
#     as separators, since file lists are often pasted line-per-path. A path
#     containing a literal comma or newline therefore cannot be expressed.
#   - Paths are compared literally after normalization (whitespace trim,
#     leading "./" and "/" strip, duplicate- and trailing-slash collapse).
#     No glob expansion, no case folding (SRC/a.ts != src/a.ts even on a
#     case-insensitive filesystem), no ".." resolution (../src/a.ts !=
#     src/a.ts), and no interior "/./" collapse (src/./a.ts != src/a.ts;
#     only *leading* "./" and "/" are stripped) -- give repo-relative paths
#     as git prints them.
#   - Every entry is read as repo-root-relative, so a leading "/" is an
#     anchor, not an absolute filesystem path: "/src/a.ts" == "src/a.ts".
#   - An entry that is only root punctuation (".", "./", "/") means the repo
#     root itself and overlaps every path.

set -uo pipefail

# Both lists are required, even if empty ("" is a valid empty list). A
# dropped argument from a quoting mistake must not silently read as
# "no overlap" -- that is the fail-unsafe direction for a safety check.
if [ "$#" -ne 2 ]; then
  echo "usage: $(basename "$0") <path-list-a> <path-list-b>" >&2
  echo "  (each list comma- and/or newline-separated)" >&2
  echo "  (pass \"\" for an intentionally empty list)" >&2
  exit 2
fi

LIST_A="$1"
LIST_B="$2"

# Files commonly touched by multiple in-flight tickets (docs/config) --
# report as a warning, not a hard block. Hardcoded pending a team-config.yml
# override surface (DX-005, same deferral as the branch-name prefix table).
# Note the DX-012 review observation: this repo's demonstrated hottest shared
# files are the agent definitions (.claude/agents/*.md), which are NOT listed
# here -- deliberately, because a hard block that forces serializing two
# dispatches onto the same agent prompt is the safe default. Add entries only
# when a warn-and-rebase outcome is genuinely acceptable for that file.
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
  #   - collapse duplicate slashes ("src//a.ts" and "src/a.ts" are the same
  #     file)
  #   - strip leading "./" and "/" ("./src/a.ts", "/src/a.ts" and "src/a.ts"
  #     are the same file -- every entry is repo-root-relative, so a leading
  #     slash is an anchor, not an absolute filesystem path). Stripping
  #     interleaves the two forms so "/./src" also reduces to "src". ".." is
  #     deliberately not resolved, so "../src" stays literal.
  #   - strip trailing slashes ("docs/" and "docs" are the same directory)
  #   - an entry that was only root punctuation (".", "./", "/") normalizes
  #     to "." -- the repo root -- rather than vanishing into the blank-entry
  #     skip below, which would silently drop the broadest possible input
  local p="$1"
  p="${p#"${p%%[![:space:]]*}"}"   # leading whitespace
  p="${p%"${p##*[![:space:]]}"}"   # trailing whitespace
  local stripped="$p"
  while case "$p" in *//*) true ;; *) false ;; esac; do
    p="${p%%//*}/${p#*//}"
  done
  while :; do
    case "$p" in
      ./*) p="${p#./}" ;;
      /*)  p="${p#/}" ;;
      *)   break ;;
    esac
  done
  while [ "$p" != "${p%/}" ]; do
    p="${p%/}"
  done
  if [ -z "$p" ] && [ -n "$stripped" ]; then
    p="."                           # was "/", "./", or similar -- repo root
  fi
  # printf, not echo: a path literally named "-n"/"-e" must not be eaten as
  # an echo flag (it would normalize to empty and vanish from the check).
  printf '%s\n' "$p"
}

# Announce (never expand) glob characters: the comparison below is literal,
# and a TPM that writes "src/*" expecting expansion would otherwise get a
# silent "no overlap". Advisory NOTE only -- exit status is unchanged.
note_glob_entries() {
  local raw entry
  for raw in "$@"; do
    entry="$(normalize "$raw")"
    case "$entry" in
      *[\*\?\[]*)
        echo "NOTE: glob characters in '$entry' are compared literally, not expanded -- list real paths"
        ;;
    esac
  done
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

# Accept newlines (and CRLF) as separators alongside commas: `read` stops at
# the first newline, so without this a pasted line-per-path list would keep
# only its first line and silently report clean on everything after it.
LIST_A="${LIST_A//$'\r'/}"
LIST_B="${LIST_B//$'\r'/}"
LIST_A="${LIST_A//$'\n'/,}"
LIST_B="${LIST_B//$'\n'/,}"

IFS=',' read -r -a ARR_A <<< "$LIST_A"
IFS=',' read -r -a ARR_B <<< "$LIST_B"

note_glob_entries ${ARR_A[@]+"${ARR_A[@]}"}
note_glob_entries ${ARR_B[@]+"${ARR_B[@]}"}

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

    # The repo root contains every path. (Root-vs-root already matched as an
    # exact overlap above; the prefix patterns below can't express this case
    # because normalized paths never start with "./".)
    if [ "$a" = "." ]; then
      echo "OVERLAP: $b is inside the repo root (.)"
      OVERLAP_FOUND=1
      continue
    fi
    if [ "$b" = "." ]; then
      echo "OVERLAP: $a is inside the repo root (.)"
      OVERLAP_FOUND=1
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
