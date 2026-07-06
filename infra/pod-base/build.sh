#!/usr/bin/env bash
# Local build entry for the pod-base image (INFRA-011).
# Usage: bash infra/pod-base/build.sh [tag]
set -euo pipefail

TAG="${1:-ghcr.io/grinnellian/ai-lindale-pod-base:dev}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker build -t "$TAG" "$DIR"
echo ""
echo "Built $TAG"
docker image inspect "$TAG" --format 'Size: {{.Size}} bytes'
