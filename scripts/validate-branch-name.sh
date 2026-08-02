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
# Exit 0: valid
# Exit 2: invalid (message on stderr)

set -uo pipefail

BRANCH="${1:-}"

fail() {
  echo "invalid branch name: $BRANCH" >&2
  echo "  reason: $1" >&2
  exit 2
}

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

# This case table is the single source of truth for the allowed type/prefix
# pairs (DX-012 review NIT-5). The regex above deliberately accepts any
# [A-Z]+ prefix so unknown types fail *here* with a specific message rather
# than the generic shape error. To add a prefix (DX-005 will eventually feed
# this from project config): add one line below AND to the tpm.md prefix
# list -- nothing else encodes the pairing.
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
