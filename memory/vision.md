# Vision

## End-state: Manfred Macx pattern

The user's north star: mutter ideas into a phone → they're captured as issues → a virtualized development team picks them up in near-real-time → user reviews results asynchronously. Latency between "thought" and "in progress" approaches zero.

Reference: Manfred Macx from Charles Stross's *Accelerando* — a character who outsources cognition to AI agents, feeding them ideas on the go.

## Meta TPM

A TPM instance whose "project" is the user's entire portfolio. It watches all repos, reads all issue boards, knows which project-specific agent teams are idle, and dispatches work based on priority and dependency. Each downstream project has its own agent team via submodule; the Meta TPM orchestrates across them.

## Home lab plans (as of 2026-03-22)

The user plans to set up dedicated machines for agent work in a DMZ:
- Mac mini — agent execution (Claude Code sessions)
- Possibly a b100 machine — local model inference (GPU)
- Personal machines stay clean — no agent work on daily drivers

This maps to the k10s concept (FEAT-005): machines as nodes, agents as pods, GitHub as the control plane.

## Incremental path

1. `/loop`-based polling with label state machine (today's primitives)
2. CLI bounce across machines (FEAT-003/FEAT-005)
3. Meta TPM dispatching across project teams
