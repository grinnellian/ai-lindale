# Review: EPIC-004 M1 slice (moat.yaml wiring + hard-floor verification)

- **Scope:** M1 slice of EPIC-004 (#69) on branch `orchestrate/2026-07-06` — commit `62c50e1`
  (`feat(EPIC-004): moat.yaml wiring + hard-floor verification findings`) plus the INFRA-012
  rename touch-up to the same files in `a1188f2`. This PR does NOT close the epic; this reviews
  the increment only: moat.yaml, the `memory/decisions.md` hard-floor entry, and follow-up hygiene.
- **Reviewer:** Claude Reviewer (fable)
- **Date:** 2026-07-06
- **Verdict:** REQUEST-CHANGES

The functional substance of the slice is solid and I could corroborate the headline claims
empirically on this host (which is xo-brain — the machine the claims were made on). The
request-changes is for documentation accuracy in the primary deliverable: moat.yaml carries a
justification that the same commit's own decisions.md entry refutes. In a repo whose stated
philosophy is "document not just what but why," a wrong *why* in the flagship config file is
exactly the kind of defect this review bar exists to catch. All fixes are small.

## Findings by severity

### Blocker

None.

### Major

**MAJ-1 — `dependencies: []` comment is false and self-contradictory (moat.yaml:21-24).**
The comment justifies the empty list with two claims:

> "moat must not apt-install its default dependency set (the image runs as non-root `dev`, so
> apt would fail anyway). Empty list = trust the base image."

Both clauses are contradicted by findings elsewhere in this very slice:

1. The same commit's decisions.md follow-up states plainly: "`moat.yaml` uses `dependencies: []`
   but moat still installs its own baseline apt layer + gh 2.40.0" — i.e. the empty list does
   NOT prevent moat's apt-install; it only omits *extra* deps. FEAT-015 (#95) later confirmed
   all 9 generated Dockerfile steps including the apt baseline run on every build.
2. "apt would fail anyway" is wrong for this file's own configuration: `base_image` ten lines
   below points at the ROOT shim (`ai-lindale-pod-base:moat-base`, `USER root`) — that shim
   exists precisely so apt *succeeds*. The M1 finding comment in the same file documents this.

The directive itself (`dependencies: []`) is correct; the recorded rationale will actively
mislead the next agent that touches dependencies or the shim. Fix: rewrite the comment to say
the base image already ships the toolchain, note that moat's baseline layer runs regardless
(cross-ref the upstream nit on #95), and drop the "apt would fail" clause.

### Minor

**MIN-1 — `runtime: docker` rationale is stale given FEAT-015's (#95) outcome (moat.yaml:37-39).**
"the pod-base image is validated against Docker; pin the runtime for predictability" was true at
commit time; since then #95 (closed) verified the full stack under podman — hard floor holds,
independently re-verified by a second session, upstream PR majorcontext/moat#435 open, and this
host's podman store contains the shim image and successful run logs. The pin itself remains
defensible (stock brew moat has no podman support until #435 merges; engine decision is FEAT-014
#94, still open), but the comment now implies docker is the only validated path, which the
project's own evidence contradicts. Fix: keep the pin, cite #94/#95 as the revisit trigger.

**MIN-2 — the root-shim `printf | docker build` instruction is not reproducible on a fresh host
(moat.yaml:32-34).** The FROM line pulls `ghcr.io/grinnellian/ai-lindale-pod-base:edge`, but the
GHCR package is private — anonymous pulls fail. That gap is known: the #69 status comment lists
it as a follow-up and INFRA-016 (#100) tracks it, yet the shim instruction carries no
`docker login ghcr.io` note and no cross-ref. The stated local-build fallback also has a tag
mismatch: the header comment says local builds via `infra/pod-base/build.sh` produce `:dev`,
while the shim FROM hardcodes `:edge` — a local-build user must know to edit the FROM line.
(The instruction's *syntax* is fine: Dockerfile-from-stdin via `docker build -` is valid, and
the produced tag matches `base_image`.) Fix: add the GHCR-visibility caveat (ref #100) and the
`:dev` adaptation for local builds.

**MIN-3 — follow-up lists diverge, and one finding has no live tracking.** decisions.md lists
follow-ups {git-407, strict network policy, dependencies-duplication}; the #69 status comment
lists {git-407, network policy, GHCR-private}. Union coverage: git-407 → INFRA-013 (#96, filed,
description matches the finding exactly, incl. the gh-works/git-fails asymmetry); strict policy
→ INFRA-014 (#97, matches, correctly notes `curl example.com` succeeded); GHCR-private →
INFRA-016 (#100, filed, needs-human). But the dependencies-duplication nit ("worth an upstream
issue" per decisions.md) has no repo ticket and no confirmed upstream issue — its only
breadcrumb is a nit-list comment on #95, which is now CLOSED. Under the project's own
breadcrumb rule this finding is at risk of being silently lost. Fix: either file the upstream
issue (or a small INFRA ticket to do so) or record explicitly where it is parked.

**MIN-4 — decisions.md hard-floor entry lacks ticket cross-references.** The entry's follow-ups
section still reads "(not yet done)" with prose descriptions only, although INFRA-013/-014/-015/
-016 were filed hours later and a later commit (a1188f2) touched this very entry's heading
without adding the pointers. The root-shim "long-term options" paragraph likewise doesn't
mention INFRA-015 (#98), whose description matches it well (both resolution options carried
over faithfully). An agent reading memory alone cannot tell these items are tracked. Fix: append
issue numbers to the entry (append-only edit is fine — one line per follow-up).

### Nit

**NIT-1 — "Apple containers can't run docker-in-docker" (moat.yaml:37) is an opaque rationale.**
Nothing in the file, docs/pod.md, or the decisions entry explains why the pod would need
docker-in-docker; the justifications that actually held up are validation coverage and moat
runtime maturity. Either explain the DinD requirement or drop the clause.

**NIT-2 — two different rename policies applied to the same finding text (INFRA-012).** moat.yaml
was fully renamed dev-in→pod-base, but the decisions.md entry body still says "dev-in" throughout
with only a heading annotation "(dev-in renamed to pod-base, INFRA-012)". Defensible as an
append-only historical record — but as a result the shim description in decisions.md
(`FROM dev-in` → `ai-lindale-dev-in:moat-base`) no longer matches the actual instruction in
moat.yaml (`FROM ghcr.io/grinnellian/ai-lindale-pod-base:edge` → `ai-lindale-pod-base:moat-base`).
Pick one policy; at minimum the heading annotation carries the load, so this is a nit.

**NIT-3 — `moat grant claude` usage comment omits the durability caveat.** The #69 status comment
itself says the imported local OAuth is not durable ("still needs an interactive
`claude setup-token`"), and the #95 verification noted a credential-store key rotation
invalidated prior grants once. moat.yaml's "once per host" claim oversells; a parenthetical
would do.

**NIT-4 — docs/pod.md's "Running under moat" section predates the working `moat run` path.** It
documents the manual `docker run` + CA-mount flow but never mentions moat.yaml or `moat run`,
while moat.yaml points readers at docs/pod.md as the reference for the model. One-way cross-ref;
add a sentence pointing at moat.yaml now that `moat run` works.

## Staleness flags

- moat.yaml `runtime: docker` rationale — stale vs #95's podman verification and upstream PR
  moat#435 (MIN-1).
- moat.yaml `dependencies: []` rationale — stale-at-birth: refuted by the same commit's
  decisions.md (MAJ-1).
- decisions.md hard-floor entry body — pre-rename "dev-in" terminology and a shim description
  that no longer matches moat.yaml's instruction (NIT-2).
- docs/pod.md "Running under moat" — written for the pre-moat.yaml manual flow (NIT-4).
- decisions.md "Follow-ups (not yet done)" — now partially done/ticketed; no cross-refs (MIN-4).

## Verified by running vs by reading

**Verified by running (on this host, which is xobrain.local — the machine named in the claims):**

- moat.yaml parses as valid YAML; keys/values exactly as the #69 status comment describes
  (agent claude, interactive, dependencies [], base_image `ai-lindale-pod-base:moat-base`,
  runtime docker, grants claude+github). Ruby YAML load.
- `moat list`: a `lindale-dev` run (the moat.yaml `name`) exists, runtime docker, stopped —
  the wiring was actually exercised, not just committed.
- **Hard floor, docker engine:** `moat logs run_b95f6ecd521c` shows
  `GH_TOKEN=ghp_moatProxyInjectedPlaceholder000000000000` in the container env and `grinnellian`
  returned by the authenticated gh call — placeholder-only env with working proxy injection,
  exactly as decisions.md claims.
- **Hard floor, podman engine:** `moat logs run_05e374bd8f02` shows `engine: podman`, the same
  placeholder, and `grinnellian` — corroborates the #95 re-verification.
- **INFRA-013 accuracy:** `moat logs run_397febb85815` shows
  `fatal: unable to access 'https://github.com/grinnellian/ai-lindale.git/': CONNECT tunnel
  failed, response 407` — the git-vs-gh asymmetry in the ticket reproduces verbatim in the
  preserved run logs.
- Root shim exists where claimed: `ai-lindale-pod-base:moat-base` present in the docker image
  store AND in podman's separate store (`localhost/ai-lindale-pod-base:moat-base`), alongside
  the pre-rename `ai-lindale-dev-in:moat-base`.
- CI publishes the `:edge` tag the shim FROM references (`.github/workflows/pod-base-image.yml`,
  `type=raw,value=edge` on default branch) — the tag name is real, the access problem (MIN-2)
  is visibility, not existence.

**Verified by reading only:**

- Issue bodies/comments: #69 (plan + both 2026-07-06 M1 status comments), #95, #96, #97, #98,
  #100; commits 62c50e1 and a1188f2; decisions.md; docs/pod.md.
- "moat grant claude / github stored on xo-brain" — grant subcommands exist and runs
  authenticated successfully (which implies grants), but I did not enumerate the credential
  store.
- I did NOT execute a fresh `moat run` end-to-end; the running-verification above rests on
  persisted run logs from 1–4 hours before this review.
- The strong-form claim "real tokens exist only on the proxy side" — I verified the
  container-visible half (placeholder env + successful injection). Confirming absence of real
  tokens anywhere inside the container (filesystem/memory) was not attempted; that residual
  rests on moat's architecture, and decisions.md's wording is honest about what was observed.

**Claims in the #69 status comments the branch doesn't contain:** none found. Every repo-side
claim (moat.yaml with the stated directives, shim documented in-file, findings + follow-ups in
decisions.md) is present on the branch; every host-side claim I could check checked out.

## Summary

0 blocker, 1 major, 4 minor, 4 nit. The wiring works and the hard-floor verification is real —
I could replay its evidence from preserved run logs on both engines. The changes requested are
all documentation-accuracy fixes, led by MAJ-1: moat.yaml must not ship a justification that
the same commit's own findings disprove.
