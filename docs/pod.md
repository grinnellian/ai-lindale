# pod: the Lindalë base container image

A **pod** is the sealed, self-sufficient container an agent lives and works
in — the L4 foundation of the container-as-boundary architecture (EPIC-004,
#69). Claude Code runs inside the container with full permissions — no
hooks, no sandbox — because the container IS the security boundary.
Credentials are injected at the network layer by [moat](https://github.com/majorcontext/moat),
so tokens never enter the agent's environment.

"Pod" names the enclosure-plus-self-sufficiency property directly, and lines
up with the k10s roadmap vocabulary (machines as nodes, agents as pods,
GitHub as the control plane) — see `memory/decisions.md` for the naming
decision (INFRA-012).

This image, `ai-lindale-pod-base`, is the base image for a pod — it ships the
tooling; a running pod is this image plus moat's credential injection and
whatever repos/resources are mounted at runtime. See [docs/faq.md](faq.md)
for how a pod differs from a devcontainer.

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
docker pull ghcr.io/grinnellian/ai-lindale-pod-base:edge

# Interactive shell
docker run -it ghcr.io/grinnellian/ai-lindale-pod-base:edge

# Straight into Claude Code (log in via browser OAuth on first run)
docker run -it ghcr.io/grinnellian/ai-lindale-pod-base:edge claude
```

Phase-0-style bootstrap (no moat yet — token as env var, acceptable only for
local single-user use):

```bash
docker run -it -e GH_TOKEN="$(gh auth token)" \
  ghcr.io/grinnellian/ai-lindale-pod-base:edge
```

## Running under moat

Moat generates a **per-host CA** for its TLS-intercepting proxy, so the cert
is not baked into the published image. The entrypoint trusts whatever is
mounted at `/run/moat/moat-ca.crt` (override the path with `MOAT_CA_CERT`):

```bash
docker run -it \
  -v "$HOME/.moat/certs/ca.crt:/run/moat/moat-ca.crt:ro" \
  -e HTTPS_PROXY=http://host.docker.internal:8080 \
  ghcr.io/grinnellian/ai-lindale-pod-base:edge
```

(The exact mount path and proxy port depend on your moat configuration. For
this repo the manual flow above is already wired: the root-level `moat.yaml`
configures the agent, base image, and grants, so `moat run` from the repo
root does all of this automatically — the `docker run` form remains the
reference for what happens underneath, and the no-moat path. When the
`lindale` CLI lands in M2 it will wrap the same `moat run` flow.)

With no CA mounted the entrypoint is a no-op, so the image works identically
with or without moat.

## Build locally

```bash
bash infra/pod-base/build.sh                # → ghcr.io/grinnellian/ai-lindale-pod-base:dev
bash infra/pod-base/smoke-test.sh           # verify the build
```

Version overrides:

```bash
docker build \
  --build-arg NODE_VERSION=24.18.0 \
  --build-arg GH_VERSION=2.96.0 \
  --build-arg CLAUDE_CODE_CHANNEL=stable \
  -t ai-lindale-pod-base:custom infra/pod-base
```

## Publishing and versioning

CI (`.github/workflows/pod-base-image.yml`) builds on every main-branch change
to `infra/pod-base/`, smoke-tests, and pushes multi-arch (amd64 + arm64) to
`ghcr.io/grinnellian/ai-lindale-pod-base`:

- `:sha-<short>` — every build (immutable)
- `:edge` — latest main build
- `:<semver>` + `:latest` — on `pod-base-v*` tags

**The old GHCR package (`ai-lindale-dev-in`) is deprecated** — it was published
under the pre-rename name (INFRA-012) and will not receive further updates.
New publishes go to `ai-lindale-pod-base` starting with the next main-branch
CI run after the rename lands.

## Size budget

Target **<1.5GB**, hard ceiling **2GB** (smoke test enforces the ceiling and
warns over target).
