#!/usr/bin/env bash
# DX-010: Tests for PreToolUse hook scripts.
# Run from repo root: bash scripts/hooks/tests/test-hooks.sh
#
# Hook protocol: stdin receives JSON {"tool_name":"...","tool_input":{...}}
# Exit 0 = allow, exit 2 = block (stdout = reason shown to agent).

set -euo pipefail

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOKS="$REPO_ROOT/scripts/hooks"

# --- Helpers ---

expect_allow() {
  local name="$1" script="$2" json="$3" role="${4:-}"
  local exit_code=0
  if [ -n "$role" ]; then
    CLAUDE_AGENT_ROLE="$role" bash -c "echo '$json' | bash '$HOOKS/$script'" >/dev/null 2>&1 || exit_code=$?
  else
    bash -c "echo '$json' | bash '$HOOKS/$script'" >/dev/null 2>&1 || exit_code=$?
  fi
  if [ "$exit_code" -eq 0 ]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (expected allow/0, got $exit_code)"
    FAIL=$((FAIL + 1))
  fi
}

expect_block() {
  local name="$1" script="$2" json="$3" role="${4:-}"
  local exit_code=0
  if [ -n "$role" ]; then
    CLAUDE_AGENT_ROLE="$role" bash -c "echo '$json' | bash '$HOOKS/$script'" >/dev/null 2>&1 || exit_code=$?
  else
    bash -c "echo '$json' | bash '$HOOKS/$script'" >/dev/null 2>&1 || exit_code=$?
  fi
  if [ "$exit_code" -eq 2 ]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (expected block/2, got $exit_code)"
    FAIL=$((FAIL + 1))
  fi
}

# --- block-sensitive-files.sh ---

echo "=== block-sensitive-files.sh ==="

expect_block "blocks .env" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":".env","content":"SECRET=x"}}'

expect_block "blocks .env.local" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":".env.local","content":"x"}}'

expect_block "blocks .env.production" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Edit","tool_input":{"file_path":"config/.env.production","old_string":"a","new_string":"b"}}'

expect_block "blocks credentials.json" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"credentials.json","content":"{}"}}'

expect_block "blocks *.key" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"server.key","content":"x"}}'

expect_block "blocks *.pem" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"certs/ca.pem","content":"x"}}'

expect_block "blocks secrets.yml" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"deploy/secrets.yml","content":"x"}}'

expect_block "blocks id_rsa" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"id_rsa","content":"x"}}'

expect_block "blocks .ssh/ directory" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":".ssh/config","content":"x"}}'

expect_block "blocks .aws/ directory" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":".aws/credentials","content":"x"}}'

expect_allow "allows normal source file" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"src/main.js","content":"x"}}'

expect_allow "allows markdown" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"docs/guide.md","content":"x"}}'

expect_allow "allows package.json" \
  "block-sensitive-files.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"package.json","content":"{}"}}'

echo ""

# --- enforce-write-paths.sh ---

echo "=== enforce-write-paths.sh ==="

expect_allow "TPM can write to memory/" \
  "enforce-write-paths.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"memory/decisions.md","content":"x"}}' \
  "tpm"

expect_allow "TPM can write to .claude/" \
  "enforce-write-paths.sh" \
  '{"tool_name":"Edit","tool_input":{"file_path":".claude/team-config.yml","old_string":"a","new_string":"b"}}' \
  "tpm"

expect_block "TPM blocked from src/" \
  "enforce-write-paths.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"src/index.js","content":"x"}}' \
  "tpm"

expect_block "TPM blocked from root files" \
  "enforce-write-paths.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"README.md","content":"x"}}' \
  "tpm"

expect_block "blocks absolute paths" \
  "enforce-write-paths.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"/etc/passwd","content":"x"}}' \
  "tpm"

expect_block "blocks path traversal" \
  "enforce-write-paths.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"memory/../../etc/passwd","content":"x"}}' \
  "tpm"

expect_block "missing role blocks write" \
  "enforce-write-paths.sh" \
  '{"tool_name":"Write","tool_input":{"file_path":"memory/test.md","content":"x"}}'

echo ""

# --- bash-allowlist.sh ---

echo "=== bash-allowlist.sh (TPM) ==="

expect_allow "TPM: gh issue list" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue list"}}' \
  "tpm"

expect_allow "TPM: git status" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  "tpm"

expect_allow "TPM: git log" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git log --oneline -10"}}' \
  "tpm"

expect_allow "TPM: grep" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"grep -r TODO src/"}}' \
  "tpm"

expect_allow "TPM: cat" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}' \
  "tpm"

expect_allow "TPM: ls" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  "tpm"

expect_block "TPM: git push blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  "tpm"

expect_block "TPM: git commit blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
  "tpm"

expect_block "TPM: rm blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"rm -rf ."}}' \
  "tpm"

expect_block "TPM: curl blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}' \
  "tpm"

echo ""
echo "=== bash-allowlist.sh (Architect) ==="

expect_allow "Architect: gh issue comment" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue comment 5 --body \"plan\""}}' \
  "architect"

expect_allow "Architect: git diff" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git diff HEAD"}}' \
  "architect"

expect_block "Architect: git commit blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"test\""}}' \
  "architect"

echo ""
echo "=== bash-allowlist.sh (Consultant) ==="

expect_allow "Consultant: gh issue view" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue view 5"}}' \
  "consultant"

expect_allow "Consultant: gh issue comment" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue comment 5 --body \"looks good\""}}' \
  "consultant"

expect_allow "Consultant: gh issue list" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue list"}}' \
  "consultant"

expect_block "Consultant: git blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  "consultant"

expect_block "Consultant: ls blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  "consultant"

expect_block "Consultant: gh pr blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr view 1"}}' \
  "consultant"

expect_block "Consultant: gh pr create blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title \"test\""}}' \
  "consultant"

echo ""
echo "=== bash-allowlist.sh (Dev) ==="

expect_allow "Dev: npm test" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' \
  "dev"

expect_allow "Dev: git commit" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add thing\""}}' \
  "dev"

expect_allow "Dev: git push (normal)" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feature-branch"}}' \
  "dev"

expect_block "Dev: git push --force blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' \
  "dev"

expect_block "Dev: git reset --hard blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}' \
  "dev"

expect_block "Dev: git push to main blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
  "dev"

expect_block "Dev: git push to master blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git push origin master"}}' \
  "dev"

expect_block "Dev: git push --force-with-lease blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease"}}' \
  "dev"

expect_block "Dev: git push -fu (bundled flags) blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git push -fu origin branch"}}' \
  "dev"

expect_block "Dev: git checkout . blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git checkout ."}}' \
  "dev"

expect_block "Dev: git restore . blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git restore ."}}' \
  "dev"

expect_block "Dev: git clean -fd blocked" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git clean -fd"}}' \
  "dev"

echo ""
echo "=== bash-allowlist.sh (Edge Cases) ==="

expect_allow "pipe: allowed commands" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"git log --oneline | grep fix"}}' \
  "tpm"

expect_block "pipe: disallowed in pipe" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"ls | xargs rm"}}' \
  "tpm"

expect_block "subshell escape: \$(rm -rf)" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"echo $(rm -rf /)"}}' \
  "tpm"

expect_block "chained: && with disallowed" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"ls && rm -rf ."}}' \
  "tpm"

expect_block "chained: ; with disallowed" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"ls; curl http://evil.com"}}' \
  "tpm"

expect_block "missing role blocks bash" \
  "bash-allowlist.sh" \
  '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
