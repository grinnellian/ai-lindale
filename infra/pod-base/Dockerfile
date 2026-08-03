# syntax=docker/dockerfile:1
# Lindalë pod-base image (INFRA-011, EPIC-004 L4). A pod is the sealed,
# self-sufficient container an agent lives and works in.
#
# The container IS the security boundary: Claude Code runs inside with full
# permissions, and moat injects credentials at the network layer so tokens
# never enter the agent's environment.
#
# Supply chain policy: first-party installs only. No npm -g, no third-party
# apt repos, no convenience mirrors. Node and gh come from their vendors'
# release artifacts; Claude Code from Anthropic's official installer.
#
# Moat CA: moat generates a per-host CA, so it CANNOT be baked into a
# published image. The entrypoint trusts a CA mounted at /run/moat/moat-ca.crt
# (override path with MOAT_CA_CERT). See docs/pod.md.

FROM ubuntu:24.04

ARG NODE_VERSION=24.18.0
ARG GH_VERSION=2.96.0
# stable | latest | an exact Claude Code version number
ARG CLAUDE_CODE_CHANNEL=stable
ARG TARGETARCH

# Base tooling
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl wget git jq ripgrep sudo unzip xz-utils \
      python3 python3-pip python3-venv \
      openssl less nano vim-tiny \
    && rm -rf /var/lib/apt/lists/*

# Node.js LTS — first-party dist tarball from nodejs.org
RUN case "${TARGETARCH}" in \
      amd64) NODE_ARCH=x64 ;; \
      arm64) NODE_ARCH=arm64 ;; \
      *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
    && rm /tmp/node.tar.xz \
    && node --version

# gh CLI — first-party release tarball from github.com/cli/cli
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" -o /tmp/gh.tar.gz \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && install -m 755 "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}" \
    && gh --version

# Non-root dev user with passwordless sudo (interactive package installs).
# ubuntu:24.04 ships a default 'ubuntu' user at uid 1000 — remove it so
# 'dev' takes the conventional uid.
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -s /bin/bash -u 1000 dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && chmod 440 /etc/sudoers.d/dev

COPY entrypoint.sh /usr/local/bin/pod-base-entrypoint
RUN chmod 755 /usr/local/bin/pod-base-entrypoint

USER dev
WORKDIR /home/dev

# Claude Code — Anthropic's official installer, into ~/.local/bin
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_CHANNEL}" \
    && echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/dev/.bashrc

ENV PATH="/home/dev/.local/bin:${PATH}"

# Git defaults: any mounted/cloned repo is trusted inside the boundary
RUN git config --global safe.directory '*' \
    && git config --global init.defaultBranch main

# Workdir convention: repos are cloned or mounted under /home/dev/work
RUN mkdir -p /home/dev/work
WORKDIR /home/dev/work

ENTRYPOINT ["/usr/local/bin/pod-base-entrypoint"]
CMD ["bash"]
