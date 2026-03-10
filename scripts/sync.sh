#!/usr/bin/env bash
# Pulls the latest framework changes via git submodule and re-runs install.
# Usage: bash scripts/sync.sh

set -euo pipefail

FRAMEWORK_DIR=".ai-lindale"

if [ ! -d "$FRAMEWORK_DIR" ]; then
  echo "Error: $FRAMEWORK_DIR/ not found. Is the submodule set up?"
  exit 1
fi

echo "Pulling latest framework..."
git submodule update --remote "$FRAMEWORK_DIR"

echo ""
echo "Symlinks point into the submodule — no reinstall needed."
echo "If new agents or hooks were added, re-run: bash .ai-lindale/scripts/install.sh"
