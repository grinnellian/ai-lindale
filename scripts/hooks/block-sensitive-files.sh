#!/usr/bin/env bash
# PreToolUse hook: blocks writes to sensitive files regardless of agent role.
# Applies to Write and Edit tool calls.
#
# Exit 0 = allow, exit 2 = block (stdout shown to agent as reason).

set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract file_path from tool_input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  # No file_path in input — not a Write/Edit call, allow
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")
# Lowercase for case-insensitive matching
BASENAME_LOWER=$(echo "$BASENAME" | tr '[:upper:]' '[:lower:]')

# --- Sensitive basename patterns ---

# .env files
if [[ "$BASENAME_LOWER" == .env* ]]; then
  echo "BLOCKED: Writing to sensitive file '$FILE_PATH' (.env* pattern)"
  exit 2
fi

# credentials files
if [[ "$BASENAME_LOWER" == credentials* ]]; then
  echo "BLOCKED: Writing to sensitive file '$FILE_PATH' (credentials* pattern)"
  exit 2
fi

# Private keys and certificates
if [[ "$BASENAME_LOWER" == *.key ]] || [[ "$BASENAME_LOWER" == *.pem ]]; then
  echo "BLOCKED: Writing to sensitive file '$FILE_PATH' (key/certificate pattern)"
  exit 2
fi

# Secrets files
if [[ "$BASENAME_LOWER" == secrets.* ]] || [[ "$BASENAME_LOWER" == secrets ]]; then
  echo "BLOCKED: Writing to sensitive file '$FILE_PATH' (secrets pattern)"
  exit 2
fi

# SSH keys
if [[ "$BASENAME_LOWER" == id_rsa* ]] || [[ "$BASENAME_LOWER" == id_ed25519* ]] || [[ "$BASENAME_LOWER" == id_ecdsa* ]]; then
  echo "BLOCKED: Writing to sensitive file '$FILE_PATH' (SSH key pattern)"
  exit 2
fi

# --- Sensitive directory patterns ---

if [[ "$FILE_PATH" == *.ssh/* ]] || [[ "$FILE_PATH" == .ssh/* ]]; then
  echo "BLOCKED: Writing to sensitive directory '$FILE_PATH' (.ssh/)"
  exit 2
fi

if [[ "$FILE_PATH" == *.gnupg/* ]] || [[ "$FILE_PATH" == .gnupg/* ]]; then
  echo "BLOCKED: Writing to sensitive directory '$FILE_PATH' (.gnupg/)"
  exit 2
fi

if [[ "$FILE_PATH" == *.aws/* ]] || [[ "$FILE_PATH" == .aws/* ]]; then
  echo "BLOCKED: Writing to sensitive directory '$FILE_PATH' (.aws/)"
  exit 2
fi

# All checks passed — allow
exit 0
