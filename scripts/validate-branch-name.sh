#!/usr/bin/env bash
# DX-012: Validate a branch name against Lindale's naming convention.
#
# Convention: <type>/<PREFIX>-<NNN>-<short-description>
#
#   Issue prefix | Branch type
#   -------------|------------
#   FEAT         | feat/
#   BUG          | fix/
#   DX           | dx/
#   DOCS         | docs/
#   INFRA        | infra/
#   EPIC         | (not branchable -- decompose into sub-issues first)
#
# Rules: lowercase hyphen-separated description, max 5 words, one branch
# per issue.
#
# This is an advisory script agents/CI can invoke directly -- it is NOT a
# PreToolUse hook. Hook-based enforcement was retired under EPIC-004
# (container-as-boundary); see CLAUDE.md's Security Boundary section.
#
# Usage: validate-branch-name.sh <branch-name>
#        (exactly one argument; a name containing whitespace must be quoted)
# Exit 0: valid
# Exit 2: invalid, or a usage error (message on stderr)

set -uo pipefail

fail() {
  echo "invalid branch name: ${BRANCH:-}" >&2
  echo "  reason: $1" >&2
  exit 2
}

# Exactly one name per invocation. Extra arguments used to be discarded
# silently, so `validate-branch-name.sh "$a" "$b"` validated only "$a" and
# exited 0 -- which the caller that wrote "$b" reads as "both are fine".
# Same fail-unsafe direction, and the same remedy, as the argc guard in the
# sibling script check-file-overlap.sh.
if [ "$#" -ne 1 ]; then
  echo "usage: $(basename "$0") <branch-name>" >&2
  echo "  (exactly one name per invocation; quote names containing spaces)" >&2
  exit 2
fi

BRANCH="$1"

if [ -z "$BRANCH" ]; then
  fail "no branch name provided"
fi

if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  fail "main/master are not issue branches"
fi

# Overall shape: <type>/<PREFIX>-<NNN>-<slug>
if [[ ! "$BRANCH" =~ ^([a-z]+)/([A-Z]+)-([0-9]+)-([a-z0-9]+(-[a-z0-9]+){0,4})$ ]]; then
  fail "does not match <type>/<PREFIX>-<NNN>-<short-description> (lowercase hyphenated description, max 5 words)"
fi

TYPE="${BASH_REMATCH[1]}"
PREFIX="${BASH_REMATCH[2]}"

# This case table is the only *executable* encoding of the allowed
# type/prefix pairs (DX-012 review NIT-5) -- when a prose copy disagrees with
# it, this table wins. The regex above deliberately accepts any [A-Z]+ prefix
# so unknown types fail *here* with a specific message rather than the
# generic shape error.
#
# It is not, however, the only copy. Adding or renaming a prefix means
# editing all of these together (DX-005 will eventually feed the set from
# project config, collapsing the list):
#   1. this case table
#   2. the convention table in this file's own header, lines 6-13
#   3. .claude/agents/dev.md "Branch Naming Convention (DX-012)" table
#   4. CLAUDE.md "### Prefixes" list
#   5. .claude/agents/tpm.md "Current prefixes:" line
case "$TYPE" in
  feat) EXPECTED="FEAT" ;;
  fix) EXPECTED="BUG" ;;
  dx) EXPECTED="DX" ;;
  docs) EXPECTED="DOCS" ;;
  infra) EXPECTED="INFRA" ;;
  epic) fail "EPIC issues are not branchable -- decompose into sub-issues" ;;
  *) fail "unknown branch type '$TYPE' (expected one of: feat, fix, dx, docs, infra)" ;;
esac

if [ "$PREFIX" != "$EXPECTED" ]; then
  fail "type/prefix mismatch: '$TYPE/' branches must use '$EXPECTED-NNN', got '$PREFIX'"
fi

exit 0
