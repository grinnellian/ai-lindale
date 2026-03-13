#!/usr/bin/env bash
# PreToolUse hook: enforces per-role Bash command restrictions.
#
# - TPM/Architect: allowlist approach (only safe read-only commands)
# - Consultant: very restricted (gh issue only)
# - Dev: denylist approach (block destructive git operations)
#
# Exit 0 = allow, exit 2 = block (stdout shown to agent as reason).
#
# Known limitations (acceptable given defense-in-depth with sandbox + worktree):
# - Quoted pipes: `grep "foo|bar"` may be incorrectly split on |
# - Backtick subshells: `cmd` not detected (only $(cmd) is caught)
# - Heredocs: can smuggle commands past the parser

set -euo pipefail

# Guard: jq required for JSON parsing
if ! command -v jq &>/dev/null; then
  echo "BLOCKED: jq is required but not installed"
  exit 2
fi

ROLE="${CLAUDE_AGENT_ROLE:-}"

if [ -z "$ROLE" ]; then
  echo "BLOCKED: CLAUDE_AGENT_ROLE not set. Cannot determine command permissions."
  exit 2
fi

# Read JSON from stdin
INPUT=$(cat)

# Extract command from tool_input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- Command extraction ---
# Split command on pipes, &&, ||, ; and check each segment.
# Also detect $(...) subshell escapes.

extract_commands() {
  local cmd="$1"
  # Replace pipe, &&, ||, ; with newlines to get individual commands
  echo "$cmd" | sed -E 's/\|{1,2}/\n/g; s/&&/\n/g; s/;/\n/g' | sed 's/^[[:space:]]*//'
}

check_subshell_escapes() {
  local cmd="$1"
  # Check for $(...) subshell syntax
  if echo "$cmd" | grep -qE '\$\('; then
    return 1
  fi
  return 0
}

get_base_command() {
  # Extract the first word (the actual command) from a command string
  local segment="$1"
  echo "$segment" | awk '{print $1}'
}

# --- Allowlist: read-only commands for TPM and Architect ---

READONLY_COMMANDS="gh git grep cat ls head tail wc sort uniq diff find echo printf test basename dirname"

is_readonly_git() {
  local cmd="$1"
  # Allow read-only git subcommands only
  if echo "$cmd" | grep -qE '^git\s+(status|log|diff|show|branch|remote|tag|rev-parse|ls-files|ls-tree|blame|shortlog|describe|config\s+--get|stash\s+list)'; then
    return 0
  fi
  # Block all other git operations
  if echo "$cmd" | grep -qE '^git\s+'; then
    return 1
  fi
  # Not a git command
  return 0
}

# --- Role checks ---

check_consultant() {
  local cmd="$1"
  # Consultant: only gh issue view/comment/list
  local segments
  segments=$(extract_commands "$cmd")

  # Check for subshell escapes
  if ! check_subshell_escapes "$cmd"; then
    echo "BLOCKED: Subshell expressions not allowed for consultant role"
    return 2
  fi

  while IFS= read -r segment; do
    [ -z "$segment" ] && continue
    local base
    base=$(get_base_command "$segment")

    if [ "$base" = "gh" ]; then
      # Only allow gh issue subcommands
      if echo "$segment" | grep -qE '^gh\s+issue\s+(view|comment|list)'; then
        continue
      fi
      echo "BLOCKED: Consultant can only use 'gh issue view/comment/list' (attempted: '$segment')"
      return 2
    fi

    # Everything else is blocked for consultant
    echo "BLOCKED: Consultant can only use 'gh issue' commands (attempted: '$segment')"
    return 2
  done <<< "$segments"

  return 0
}

check_allowlist_role() {
  local cmd="$1" role="$2"
  local segments
  segments=$(extract_commands "$cmd")

  # Check for subshell escapes
  if ! check_subshell_escapes "$cmd"; then
    echo "BLOCKED: Subshell expressions not allowed for $role role"
    return 2
  fi

  while IFS= read -r segment; do
    [ -z "$segment" ] && continue
    local base
    base=$(get_base_command "$segment")

    # xargs can execute arbitrary commands
    if [ "$base" = "xargs" ]; then
      echo "BLOCKED: 'xargs' not allowed for $role role"
      return 2
    fi

    # Check if base command is in the allowlist
    if ! echo " $READONLY_COMMANDS " | grep -q " $base "; then
      echo "BLOCKED: Command '$base' not allowed for $role role"
      return 2
    fi

    # If it's git, check for read-only subcommands
    if [ "$base" = "git" ]; then
      if ! is_readonly_git "$segment"; then
        echo "BLOCKED: Git write operation not allowed for $role role (attempted: '$segment')"
        return 2
      fi
    fi
  done <<< "$segments"

  return 0
}

check_dev() {
  local cmd="$1"

  # Dev denylist: block destructive operations.
  # Note: denylist is inherently incomplete — worktree isolation (enforcement
  # layer 4) limits blast radius for any gaps not caught here.

  # Force push (--force, --force-with-lease, -f, bundled -f e.g. -fu)
  if echo "$cmd" | grep -qE 'git\s+push\s+.*--force'; then
    echo "BLOCKED: Force push not allowed for dev role"
    return 2
  fi
  if echo "$cmd" | grep -qE 'git\s+push\s+.*-[a-zA-Z]*f'; then
    echo "BLOCKED: Force push not allowed for dev role"
    return 2
  fi

  # Hard reset
  if echo "$cmd" | grep -qE 'git\s+reset\s+--hard'; then
    echo "BLOCKED: Hard reset not allowed for dev role"
    return 2
  fi

  # Destructive working tree operations
  if echo "$cmd" | grep -qE 'git\s+checkout\s+\.\s*$'; then
    echo "BLOCKED: 'git checkout .' discards uncommitted changes — not allowed for dev role"
    return 2
  fi
  if echo "$cmd" | grep -qE 'git\s+restore\s+\.'; then
    echo "BLOCKED: 'git restore .' discards uncommitted changes — not allowed for dev role"
    return 2
  fi
  if echo "$cmd" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
    echo "BLOCKED: 'git clean -f' deletes untracked files — not allowed for dev role"
    return 2
  fi

  # Push to main/master
  if echo "$cmd" | grep -qE 'git\s+push\s+\S+\s+(main|master)(\s|$)'; then
    echo "BLOCKED: Pushing directly to main/master not allowed for dev role"
    return 2
  fi

  return 0
}

# --- Dispatch by role ---

case "$ROLE" in
  tpm|architect)
    check_allowlist_role "$COMMAND" "$ROLE"
    exit $?
    ;;
  *-consultant|consultant)
    # Matches 'consultant' or any role ending in -consultant.
    # Intentionally broad — fails toward more restrictive (safe direction).
    check_consultant "$COMMAND"
    exit $?
    ;;
  dev)
    check_dev "$COMMAND"
    exit $?
    ;;
  *)
    # Unknown role — fail closed
    echo "BLOCKED: Unknown role '$ROLE'"
    exit 2
    ;;
esac
