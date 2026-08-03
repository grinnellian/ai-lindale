# Orchestration state — 2026-07-06 session (handoff)

Session role: orchestrator on branch `orchestrate/2026-07-06`. All work merged to the branch,
pushed, consolidated in **draft PR #101** (23 closes, CI green on the PR). This file is the
pickup point for the next session, per the DX-038 tracker convention.

## Gate

Everything below waits on the operator reviewing/merging **PR #101**. Merge effects: 23 issues
auto-close; CI on main goes green (it had been red since 2026-05-21 — dead hook-test step, fixed
in the sweep); first CI publish of `ghcr.io/grinnellian/ai-lindale-pod-base` fires, which
triggers the INFRA-016 visibility decision.

## Running independently

- **Moat fork** (`~/claude/moat`, separate Fable session): podman support mission. Reports to
  #95. Upstream nits it may also fix: #95 comment of 2026-07-06 (baseline apt layer,
  root-base contract → INFRA-015, git 407 → INFRA-013). Check #95 before working either ticket.

## Waiting on human (labeled needs-human)

- INFRA-016 (#100) GHCR visibility — one click after first publish
- DOCS-003 (#99) wiki Vision/Roadmap editorial pass — operator's voice, agents keep out
- Durable claude grant on xo-brain (`moat grant claude` → option 1; imported token expires ~6h)
- BUG-002 (#52) — pre-existing needs-human, untouched this session

## Recommended next wave (post-merge), in order

1. **Downstream validation** — run `scripts/sync.sh` against a real downstream (catalyst-build)
   to prove BUG-008/BUG-009/FEAT-011 install fixes in the wild. Cheap, high-signal, exercises
   the adoption story end to end.
2. **BUG-006 (#77) retest** — likely stale: this session ran ~15 dev agents in isolated
   worktrees that all committed via Bash without issue, contradicting the "dev subagents
   blocked on Bash in worktrees" premise. If confirmed fixed upstream, retire the
   stage-and-return workaround section in tpm.md (and its patterns.md lore) — it's now
   dead weight in every TPM context.
3. **INFRA-014 (#97) strict network policy** — self-contained M1 finisher, agent-doable on
   this host (moat + docker working; see gotchas). Closes EPIC-004 L3.
4. **INFRA-013 (#96) git-over-proxy 407** — check #95 first; the fork may solve it upstream.
   If not, try git proxy-auth config injected via moat's claude provider.
5. **INFRA-003 (#38) triage** — PAT provisioning likely superseded by moat grants; recommend
   TPM assessment and probable close-as-obsolete rather than implementation.
6. **M0 block, dependency-ordered**: DX-005 (#5, team-config system — DX-039 routing landed a
   slice of it; scope what remains), then DX-019 (#22, bootstrap interview — its brownfield
   branch should invoke the DX-025 playbook procedure), then EPIC-002's first quality gate
   (DX-023 #30, post-merge doc staleness — today's CI/doc-drift find is the motivating example).
7. **M2 kickoff** (after M1 closes): architect ticket for the lindale CLI wrapping `moat run`,
   spec inputs = FEAT-014 report (#94: docker default, LINDALE_RUNTIME abstraction, $DOCKER_HOST
   respect) + FEAT-015/#95 podman outcome.

## Host gotchas (xo-brain)

- Docker Desktop daemon hangs on ALL registry pulls (survived restarts); container networking
  and builds work. Route around via local builds/cached images. Podman install may leapfrog it.
- Local images: `ai-lindale-pod-base:{dev,edge}` + root shim `:moat-base` (moat requires
  root-user base images — INFRA-015).
- GHCR package private until INFRA-016 resolves; `docker pull` fails anonymously.

## Session lore worth keeping

- Harness agent-worktrees branch from `main`, not the current branch — dispatch prompts must
  include an explicit `git rebase <branch>` first step.
- Issue numbering is TPM/orchestrator authority: one dev agent self-assigned FEAT-016 for
  untitled #62; corrected to FEAT-013 before merge. Watch for this in agent output.
- Operator preferences (recorded 2026-07-06): grounded docs only — no visionary prose in
  wiki/narrative surfaces; no session-URL trailers in commits.
