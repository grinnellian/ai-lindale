#!/usr/bin/env bash
# PreToolUse hook: enforces per-role write path restrictions.
# Only roles with restricted write access need this hook (currently: TPM).
#
# Exit 0 = allow, exit 2 = block (stdout shown to agent as reason).

set -euo pipefail

ROLE="${CLAUDE_AGENT_ROLE:-}"

if [ -z "$ROLE" ]; then
  echo "BLOCKED: CLAUDE_AGENT_ROLE not set. Cannot determine write permissions."
  exit 2
fi

# Read JSON from stdin
INPUT=$(cat)

# Extract file_path from tool_input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- Security checks (all roles) ---

# Block absolute paths
if [[ "$FILE_PATH" == /* ]]; then
  echo "BLOCKED: Absolute paths are not allowed ('$FILE_PATH')"
  exit 2
fi

# Block path traversal
if [[ "$FILE_PATH" == *..* ]]; then
  echo "BLOCKED: Path traversal is not allowed ('$FILE_PATH')"
  exit 2
fi

# --- Role-specific allowlists ---

case "$ROLE" in
  tpm)
    # TPM can only write to memory/ and .claude/
    if [[ "$FILE_PATH" == memory/* ]] || [[ "$FILE_PATH" == .claude/* ]]; then
      exit 0
    fi
    echo "BLOCKED: TPM can only write to memory/ and .claude/ (attempted: '$FILE_PATH')"
    exit 2
    ;;
  *)
    # Roles without write path restrictions pass through
    # (Dev uses block-sensitive-files.sh instead; Architect/Consultant have disallowedTools)
    exit 0
    ;;
esac
