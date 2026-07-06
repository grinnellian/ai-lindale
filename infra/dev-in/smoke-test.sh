#!/usr/bin/env bash
# Smoke test for the dev-in image (INFRA-011).
# Usage: bash infra/dev-in/smoke-test.sh [tag]
set -euo pipefail

TAG="${1:-ghcr.io/grinnellian/ai-lindale-dev-in:dev}"
PASS=0
FAIL=0

check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== dev-in smoke test: $TAG ==="

# Tooling present and runnable
check "claude --version"  docker run --rm "$TAG" claude --version
check "git --version"     docker run --rm "$TAG" git --version
check "node --version"    docker run --rm "$TAG" node --version
check "python3 --version" docker run --rm "$TAG" python3 --version
check "gh --version"      docker run --rm "$TAG" gh --version
check "jq --version"      docker run --rm "$TAG" jq --version
check "rg --version"      docker run --rm "$TAG" rg --version

# Runs as non-root dev user with sudo
check "runs as dev user"  bash -c "[ \"\$(docker run --rm $TAG whoami)\" = dev ]"
check "sudo works"        docker run --rm "$TAG" sudo true

# Git defaults
check "safe.directory=*"  bash -c "docker run --rm $TAG git config --global safe.directory | grep -qx '\*'"

# Moat CA: mount a throwaway CA, entrypoint must install it into the trust store
CA_TMP=$(mktemp -d)
trap 'rm -rf "$CA_TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -keyout "$CA_TMP/ca.key" -out "$CA_TMP/ca.crt" \
  -subj "/CN=moat-smoke-test-ca" >/dev/null 2>&1
check "moat CA trusted when mounted" bash -c \
  "docker run --rm -v '$CA_TMP/ca.crt:/run/moat/moat-ca.crt:ro' $TAG \
     openssl x509 -in /usr/local/share/ca-certificates/moat-ca.crt -noout -subject \
   | grep -q moat-smoke-test-ca"
check "no CA mounted -> starts clean" bash -c \
  "docker run --rm $TAG bash -c '[ ! -f /usr/local/share/ca-certificates/moat-ca.crt ]'"

# Size budget: target <1.5GB, hard ceiling 2GB
SIZE=$(docker image inspect "$TAG" --format '{{.Size}}')
SIZE_GB=$(python3 -c "print(f'{$SIZE/1024**3:.2f}')")
if [ "$SIZE" -lt 2147483648 ]; then
  echo "  PASS: image size ${SIZE_GB}GB under 2GB hard ceiling"
  PASS=$((PASS + 1))
  [ "$SIZE" -ge 1610612736 ] && echo "  WARN: over the 1.5GB target"
else
  echo "  FAIL: image size ${SIZE_GB}GB exceeds 2GB hard ceiling"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
