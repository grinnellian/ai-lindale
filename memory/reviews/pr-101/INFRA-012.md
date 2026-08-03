# Review: INFRA-012 — Rename dev-in to pod (concept, image, docs, FAQ)

- **Ticket:** INFRA-012
- **Issue:** #93
- **Commit under review:** a1188f2 `refactor(INFRA-012): rename dev-in to pod / ai-lindale-pod-base (#93)` (plus related sweep in 9672c16 on this branch)
- **Reviewer:** Claude Reviewer (fable)
- **Date:** 2026-07-06
- **Verdict:** APPROVE-WITH-NITS

## Acceptance criteria

| AC | Status | Evidence |
|---|---|---|
| `infra/dev-in/` -> `infra/pod-base/` with image refs updated inside | Satisfied | `infra/` contains only `pod-base/`; Dockerfile, build.sh, entrypoint.sh, smoke-test.sh all reference `ghcr.io/grinnellian/ai-lindale-pod-base`; no `dev-in` string anywhere under `infra/` |
| Workflow rename + tag scheme + publish target | Satisfied | `.github/workflows/pod-base-image.yml` exists, old `dev-in-image.yml` deleted; `paths` trigger matches `infra/pod-base/**` and the workflow file itself; tag trigger `pod-base-v*`; metadata-action `type=match,pattern=pod-base-v(.*)` and `:latest` gated on `refs/tags/pod-base-v`; `IMAGE=ghcr.io/.../ai-lindale-pod-base`. Old `dev-in-v*` tags: none exist locally or on origin (`git tag -l` and `git ls-remote --tags origin` both empty), so dropping the old trigger loses nothing |
| `docs/dev-in.md` -> `docs/pod.md`, concept introduced, operational content kept | Satisfied | `docs/pod.md` opens with the pod concept (sealed, self-sufficient, L4 of container-as-boundary), cites the naming decision, keeps pull/run/moat/build/publish/size-budget sections |
| New `docs/faq.md` with devcontainer disambiguation | Satisfied | Entry "Is a pod a devcontainer?" covers no-spec, no-editor-coupling, and moat-at-the-network-boundary — matches the issue's required framing. One wording nit (N4) |
| `moat.yaml` base_image + comments | Satisfied | `base_image: ai-lindale-pod-base:moat-base`; header, shim recipe, and all comments use pod-base names; points at `pod-base-image.yml` and `docs/pod.md`. Timing nit (N3) |
| CLAUDE.md / README / adoption-guide mentions | Satisfied (nothing to rename) | At a1188f2^ none of the three contained "dev-in"; current CLAUDE.md/README file trees list `pod.md` / `pod-base/` (added in sweep 9672c16). Wording nit (N1) |
| `memory/decisions.md`: naming decision + parked alternatives | Satisfied | "Pod naming decision (INFRA-012, 2026-07-06)" entry records the k10s-vocabulary rationale, the Devin/Windsurf collision, **devcon rejected** (devcontainer.json collision + false compatibility assumptions + DEF CON adjacency), and **cell/workcell parked** (lean-manufacturing framing, future-branding option) — exactly per issue |
| No remaining "dev-in" references except historical citations | Satisfied with accepted deviation | See residual-reference table. Historical decisions.md entries cite the old name more than "once" (the AC's literal wording), but each entry's header carries a "(renamed to pod-base, INFRA-012)" annotation and rewriting verification history would be worse — accepted as within the AC's intent |
| Smoke test passes against locally built pod-base | Corroborated, not re-run | Orchestrator ran it per task brief. I verified `smoke-test.sh` defaults to `ghcr.io/grinnellian/ai-lindale-pod-base:dev`, and that image (plus `:edge` and the `:moat-base` shim) exists locally at 1.02GB — consistent with a completed run. Did not rebuild or re-execute per instructions |
| Old GHCR package deprecation noted in docs | Satisfied | `docs/pod.md` lines 100-103: `ai-lindale-dev-in` deprecated, no further updates, new publishes to `ai-lindale-pod-base` on next main CI run |

## Findings by severity

### Blockers
None.

### Major
None.

### Minor
None.

### Nits

- **N1 — "dev container" gloss contradicts the FAQ's own distinction.** `CLAUDE.md:73` and `README.md:42` describe `docs/pod.md` as "Pod (dev container) image docs". The FAQ's headline claim is that a pod is *not* a devcontainer; glossing it as "dev container" in the two most-read files invites exactly the confusion `docs/faq.md` was written to prevent. Suggest "Pod (agent container) image docs" or similar. (Introduced in sweep commit 9672c16, same branch.)
- **N2 — Commit message claims a change that is not in the commit.** a1188f2's message says `.claude/settings.local.json` was updated, but that file is globally git-ignored (`~/.config/git/ignore`) and appears in no commit. The local copy still carries the stale allow rule `Bash(IMAGE=ghcr.io/grinnellian/ai-lindale-dev-in:dev bash infra/dev-in/smoke-test.sh)` and has no pod-base equivalent. Not a repo defect (untracked, machine-local), but the commit message overstates the diff, and the operator's local allowlist will re-prompt on the renamed smoke-test invocation.
- **N3 — moat.yaml shim recipe depends on a not-yet-published tag.** The documented shim (`FROM ghcr.io/grinnellian/ai-lindale-pod-base:edge`) cannot be built from GHCR until the first post-merge main CI run publishes the renamed package (docs/pod.md acknowledges the timing). The header comment does document the local-build fallback (`build.sh` -> `:dev`), and a local `:edge` exists on this machine, so this only bites a fresh host during the transition window. Consider showing the shim `FROM` a local tag until first publish.
- **N4 — FAQ slightly oversimplifies the devcontainer spec.** "devcontainer is an editor-integration spec" — containers.dev positions itself editor-agnostically (devcontainers/cli, Codespaces, CI usage). The FAQ's bullet already hedges correctly ("VS Code Remote-Containers being the canonical case"); only the closing one-liner overreaches. "Editor/environment-integration spec" would be airtight. The core distinction (spec + lifecycle vs. network-layer credential boundary) is technically correct.

## Residual-reference audit

`grep -rn "dev-in" --include="*.md" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" . | grep -v .git/` (worktrees excluded), plus a case-insensitive full-repo sweep for `dev-in|dev_in`:

| Location | Hit | Classification |
|---|---|---|
| `memory/decisions.md:48,108,115,171` | Historical entries with explicit "(renamed to pod-base, INFRA-012)" annotations | Deliberate-historical |
| `memory/decisions.md:173-193` | In-body mentions inside the hard-floor verification entry (incl. `ai-lindale-dev-in:moat-base` shim tag as it existed at verification time) | Deliberate-historical — covered by the entry-header annotation at line 171 |
| `memory/decisions.md:198,207` | Pod naming decision entry citing the old name being renamed | Deliberate — the rename record itself |
| `docs/pod.md:100` | Old GHCR package deprecation notice | Deliberate — required by AC |
| `memory/reviews/pr-101/DOCS-002.md:57,73` | Sibling review artifact quoting its own rename-check grep | Deliberate-historical (review record) |
| `.claude/settings.local.json:58` | Stale local allowlist rule for the old smoke-test command | Local-only, untracked/git-ignored — not shipped; see N2 |

No missed references. `infra/`, `.github/workflows/`, `moat.yaml`, `docs/adoption-guide.md`, `CLAUDE.md`, `README.md`, `memory/patterns.md`, `templates/`, `scripts/` are all clean. Entrypoint binary rename is consistent: `pod-base-entrypoint` in Dockerfile COPY, chmod, and ENTRYPOINT; no `dev-in-entrypoint` anywhere.

## Verified by running vs. by reading

**By running:**
- `bash -n` on all three renamed shell scripts (`build.sh`, `entrypoint.sh`, `smoke-test.sh`) — all pass
- Residual-reference greps (targeted extensions + case-insensitive full-repo sweep)
- `git show a1188f2` (full diff + stat); `git show a1188f2^:...` greps to confirm CLAUDE.md/README/adoption-guide had no dev-in mentions pre-rename
- `git tag -l` and `git ls-remote --tags origin` — no `dev-in-v*` (or any) tags exist, so the dropped old tag trigger is safe
- `docker images` — `ghcr.io/grinnellian/ai-lindale-pod-base:dev`, `:edge`, and `ai-lindale-pod-base:moat-base` present locally (1.02GB), corroborating the orchestrator's smoke-test run without rebuilding
- `git check-ignore -v .claude/settings.local.json` — confirmed globally ignored (basis for N2)

**By reading:**
- Workflow trigger semantics: `paths` filters are not evaluated for tag pushes on GitHub Actions, so `pod-base-v*` tags will trigger despite the `paths` block — pattern is correct as written
- FAQ technical accuracy against the containers.dev spec (from knowledge, not fetched)
- Smoke test execution result — trusted from the orchestrator's run (task brief); not re-executed
- decisions.md entry content vs. issue #93 requirements (devcon-rejected, cell-parked) — exact match

## Verdict

**APPROVE-WITH-NITS.** All ten scope/AC items are satisfied; the rename is complete and internally consistent across image, workflow, docs, moat config, and memory. Four nits, none blocking merge; N1 is the only one worth fixing before the next doc-touching commit.

-Claude Reviewer (fable)
