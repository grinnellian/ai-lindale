# dev-in: the Lindalë base container image

The dev-in image is the L4 foundation of the container-as-boundary architecture
(EPIC-004, #69). Claude Code runs inside the container with full permissions —
no hooks, no sandbox — because the container IS the security boundary.
Credentials are injected at the network layer by [moat](https://github.com/majorcontext/moat),
so tokens never enter the agent's environment.

## What's in the image

| Component | Source | Pinning |
|-----------|--------|---------|
| Ubuntu 24.04 | Docker Hub official | base tag |
| Claude Code | `claude.ai/install.sh` (Anthropic first-party) | `CLAUDE_CODE_CHANNEL` build arg (default `stable`) |
| Node.js LTS | nodejs.org dist tarball | `NODE_VERSION` build arg |
| gh CLI | github.com/cli/cli release tarball | `GH_VERSION` build arg |
| git, python3, jq, ripgrep, curl, sudo | Ubuntu archive | apt |

Supply chain policy: **first-party installs only** — no npm -g, no third-party
apt repos. Runs as non-root user `dev` (uid 1000) with passwordless sudo;
repos live under `/home/dev/work`.

## Pull and run standalone

```bash
docker pull ghcr.io/grinnellian/ai-lindale-dev-in:edge

# Interactive shell
docker run -it ghcr.io/grinnellian/ai-lindale-dev-in:edge

# Straight into Claude Code (log in via browser OAuth on first run)
docker run -it ghcr.io/grinnellian/ai-lindale-dev-in:edge claude
```

Phase-0-style bootstrap (no moat yet — token as env var, acceptable only for
local single-user use):

```bash
docker run -it -e GH_TOKEN="$(gh auth token)" \
  ghcr.io/grinnellian/ai-lindale-dev-in:edge
```

## Running under moat

Moat generates a **per-host CA** for its TLS-intercepting proxy, so the cert
is not baked into the published image. The entrypoint trusts whatever is
mounted at `/run/moat/moat-ca.crt` (override the path with `MOAT_CA_CERT`):

```bash
docker run -it \
  -v "$HOME/.moat/certs/ca.crt:/run/moat/moat-ca.crt:ro" \
  -e HTTPS_PROXY=http://host.docker.internal:8080 \
  ghcr.io/grinnellian/ai-lindale-dev-in:edge
```

(The exact mount path and proxy port depend on your moat configuration; when
the `lindale` CLI lands in M2 it wires this automatically via `moat run`.)

With no CA mounted the entrypoint is a no-op, so the image works identically
with or without moat.

## Build locally

```bash
bash infra/dev-in/build.sh                # → ghcr.io/grinnellian/ai-lindale-dev-in:dev
bash infra/dev-in/smoke-test.sh           # verify the build
```

Version overrides:

```bash
docker build \
  --build-arg NODE_VERSION=24.18.0 \
  --build-arg GH_VERSION=2.96.0 \
  --build-arg CLAUDE_CODE_CHANNEL=stable \
  -t ai-lindale-dev-in:custom infra/dev-in
```

## Publishing and versioning

CI (`.github/workflows/dev-in-image.yml`) builds on every main-branch change
to `infra/dev-in/`, smoke-tests, and pushes multi-arch (amd64 + arm64) to
`ghcr.io/grinnellian/ai-lindale-dev-in`:

- `:sha-<short>` — every build (immutable)
- `:edge` — latest main build
- `:<semver>` + `:latest` — on `dev-in-v*` tags

## Size budget

Target **<1.5GB**, hard ceiling **2GB** (smoke test enforces the ceiling and
warns over target).
