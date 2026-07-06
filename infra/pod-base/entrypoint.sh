#!/usr/bin/env bash
# pod-base entrypoint: trust the moat CA if one is mounted, then exec the command.
#
# Moat generates a per-host CA for its TLS-intercepting proxy, so the cert
# cannot be baked into a published image. Mount it read-only at
# /run/moat/moat-ca.crt (or point MOAT_CA_CERT at another path):
#
#   docker run -v "$HOME/.moat/certs/ca.crt:/run/moat/moat-ca.crt:ro" ...
#
# Running without moat (e.g. Phase-0-style GH_TOKEN bootstrap) is fine —
# the CA step is skipped silently.
set -euo pipefail

CA_SRC="${MOAT_CA_CERT:-/run/moat/moat-ca.crt}"
if [ -f "$CA_SRC" ]; then
  sudo install -m 644 "$CA_SRC" /usr/local/share/ca-certificates/moat-ca.crt
  sudo update-ca-certificates >/dev/null
  # Node-based tools keep their own trust store
  export NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/moat-ca.crt
fi

exec "$@"
