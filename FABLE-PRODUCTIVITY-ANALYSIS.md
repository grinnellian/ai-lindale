# Fable Productivity Analysis — ai-lindale

**Analyst:** Claude Opus 4.8 (deliberately *not* the model under evaluation), independent read of the repository.
**Date of analysis:** 2026-07-06.
**Purpose:** a defensible — not promotional — basis for deciding whether Claude Fable credits earn their keep,
intended for excerpting into friends-and-family funding materials for a separate project.
**Bias posture:** the commissioning operator wants this to survive a skeptical reader. Where the flattering
reading and the ground truth diverge, the ground truth wins and is stated plainly. Overclaims are called out
as overclaims, including ones the commissioning brief itself suggested.

The central question is *not* "does Fable write more code." Most implementation tokens on the day under
study were spent by cheaper Sonnet subagents. The honest question is: **does a Fable session, acting as
orchestrator / planner / reviewer / verifier, convert a fixed amount of human attention and cheaper model
labor into more delivered, defect-checked work than the prior baseline?** That is what the numbers below test.

---

## 1. Method

All figures come from the repository's own history and GitHub, reproduced in a throwaway clone so the working
tree was never touched. Every table cell traces to a command listed here.

- **Commit clustering:** `git log --format='%ad %h %s' --date=short | sort | uniq -c` — development happens in
  tight single-day bursts separated by weeks, so "sprint" = a day-cluster.
- **Session split within 2026-07-06:** author timestamps + branch. The day contains two distinct sessions:
  a **morning reconstruction** (00:38–08:46, 5 commits, landed on `main` from another machine) and
  **Sprint F** (12:09–21:29, 58 commits on branch `orchestrate/2026-07-06`, the Fable-orchestrated wave).
  They are kept separate throughout; conflating them would flatter Sprint F.
- **LOC deltas:** `git diff --shortstat <range>` and `--numstat` bucketed by file type.
- **Issues:** `gh issue list --state closed --json number,closedAt,stateReason` (closure *reason* matters — see §3).
- **Reviews:** file count / line count under `memory/reviews/pr-101/`; `git log --diff-filter=A` to prove
  first appearance.
- **Cross-repo:** a second clone of `grinnellian/moat`, branch `feat/podman`; `gh pr view 435 --repo majorcontext/moat`.
- **Model attribution of old commits is treated as UNCERTAIN.** Git records a human author (`Ian Bone` early,
  `Iri Bone` later) on every commit, not a model. The operator states prior work was "at best opus." We cannot
  verify that from the repo; we can only bound it and say so.

---

## 2. Data

### 2.1 Development clusters (whole history)

| Cluster | Dates | Commits | LOC Δ (`--shortstat`) | Tickets *completed* | Character |
|---|---|---|---|---|---|
| Bootstrap / extraction | Mar 8–12 | 17 | (initial import) | 8 | Framework extracted from aistrologer; agents, CLAUDE.md, adoption scripts, hooks |
| Roadmap / vision | Mar 22 | 10 | +606 / −115 | 1 | Mostly docs/roadmap/memory |
| Security-pivot grooming | Apr 21–22 | 2 | +197 / −30 | 2 (+16 abandoned) | 2 commits; a large backlog *closed as `NOT_PLANNED`* — see §3 |
| EPIC-004 pivot | May 21 | 7 | +514 / −48 | 2 | Hook enforcement retired in favor of container-as-boundary |
| **Morning reconstruction** | Jul 6, 00:38–08:46 | 5 | +473 / −822 | (rolled into PR #101) | Other machine; DX-035 removes hook scaffolding (net-negative LOC) |
| **Sprint F (Fable-orchestrated)** | Jul 6, 12:09–21:29 | 58 | +5,700 / −285 | 23 implemented (queued on draft PR #101) | Parallel worktree subagent waves |

Baseline single-day sessions land **1–2 completed tickets and a few hundred LOC**. Sprint F is a different
order of magnitude on both axes — but the LOC figure is misleading until decomposed (next).

### 2.2 Sprint F work-mix (the LOC number, honestly)

`git diff --numstat c1b1f41..3c0628b`, bucketed:

| Category | +added | −deleted | files |
|---|---:|---:|---:|
| Review markdown (`memory/reviews/`) | 2,962 | 0 | 24 |
| Docs / agent-prompt markdown | 1,417 | 222 | 27 |
| Shell (framework logic + tests) | 1,166 | 27 | 12 |
| YAML / CI | 99 | 3 | 3 |
| Other | 56 | 33 | 4 |

**52% of Sprint F's additions are review prose, ~25% docs/prompts, ~20% executable shell.** The raw "+5,700"
overstates code output by roughly 5×. This is a **prompts/docs/shell sprint**, not a big-code sprint — which is
what you'd expect from a framework whose "product" *is* agent definitions and installer logic. Any funding claim
must use the decomposed figure, not the headline LOC.

### 2.3 Tests

| | May 21 baseline | Sprint F (tip) |
|---|---|---|
| Suites in `scripts/tests/` | 1 (`test-adoption.sh`) | 6 |
| Adoption suite test cases (`run_test`) | 29 | 58 |
| Total test cases across suites | 29 | **129** (adoption 58, audit-repo 18, branch-naming 15, file-overlap 7, researcher 18, skills 14) |
| Net-new suites | — | 5 (audit-repo, branch-naming, file-overlap, researcher, skills) |

There was also a hook-test suite at May 21 (`scripts/hooks/tests/test-hooks.sh`), removed under DX-035 as dead
code; it is excluded above. All six current suites are wired into CI.

### 2.4 Review depth (the categorically-new artifact)

- 24 per-ticket review files, 2,962 lines, under `memory/reviews/pr-101/`.
- `git log --diff-filter=A` confirms **first appearance 2026-07-06** — no comparable review artifact exists
  anywhere in the prior four months of history. This is a new *kind* of output, not merely more of an old one.
- Verdicts: ~16 `APPROVE-WITH-NITS`, ~8 `REQUEST-CHANGES`. **Zero `BLOCK`/reject verdicts and zero blocker
  findings** — independently confirmed (every file's `### Blocker` section is empty/"none").
- Severity rollup **as stated by the operator: 0 blockers / 11 majors / 57 minors / 76 nits.** I independently
  confirmed the 0-blocker figure and that nit-level occurrences match 76; the major/minor split I could **not**
  cleanly reproduce because the files use inconsistent finding-ID conventions (`MAJOR-1` in some, `N1`/inline in
  others). Treat 11/57 as operator-reported, not analyst-verified.

### 2.5 Rework / defect signals

- **0 reverts** in the entire repository history (`git log --all | grep -i revert`). (Caveat: the repo is young
  and small; low absolute defect counts are partly a size effect.)
- Sprint F's review pass caught bugs **verified by execution, not just reading**, e.g.:
  - `check-file-overlap.sh` silent directory-containment false-negative (MAJOR-1, DX-012) — verified by running.
  - Dev TDD red/green contract "unsatisfiable on the BUG-006 subagent path" (DX-037) — traced across four files.
  - In the moat fork: a dual-engine orphaned-container bug caught in **pre-PR** review and "validated
    empirically with both engines live" (see §2.6).

### 2.6 Cross-repo throughput (moat fork)

Same day, a separate Fable session forked `majorcontext/moat` and added podman support to an unfamiliar Go codebase.

| Metric | Value |
|---|---|
| Commits (branch `feat/podman`, all 2026-07-06) | 8, spanning ~18:17–19:46 local |
| Diff vs upstream merge-base | +1,198 / −53 across **28 files** (Go: `detect.go`, `docker.go`, `pool.go`, `storage.go` + tests) |
| Upstream PR | `majorcontext/moat#435`, opened 2026-07-07 02:44 UTC |
| PR outcome | **CLOSED unmerged 03:28 UTC (~44 min later)** — see §3 |
| Security property | Hard floor (real token only in outer proxy) re-verified live post-change; **independently re-verified by a second session that was not the fork author** (#95) |

---

## 3. Confounds (stated plainly)

1. **Attribution — the load-bearing one.** Most Sprint F implementation tokens were Sonnet, dispatched into
   isolated worktrees. Fable's contribution was planning, routing, merge-ordering, review, and verification.
   The defensible claim is **"Fable-as-orchestrator multiplies cheaper labor,"** not "Fable writes more code."
   Every §2 figure is a *team* output under Fable direction, not a Fable-solo output.

2. **Single-day sample + novelty/attention effects.** Sprint F is one day. The operator was actively approving
   from mobile throughout — an unusually high-attention condition that will not replicate on an average day. n=1.

3. **Work-mix is not comparable across eras.** Sprint F skews to prompts/docs/shell (§2.2); some baseline eras
   were code-heavier per line. LOC-per-day comparisons across eras are apples-to-oranges and are *not* used as a
   headline here.

4. **Maturity effect — some credit belongs to the SYSTEM, not the model.** Sprint F ran fast partly *because*
   prior sprints built the ticket discipline, memory files, TDD conventions, and autodev state machine it relied
   on. A first-day session with none of that scaffolding would not hit these numbers. Productivity is
   co-produced by the accumulated framework.

5. **Issues-closed is a noisy metric.** On 2026-04-22, 16 issues were closed as `NOT_PLANNED` (the EPIC-003
   security approach was abandoned) against only 2 completed. A naive "18 issues closed that day" would be
   nonsense. Only `COMPLETED` closures are counted as throughput anywhere in this document. Conversely, Sprint
   F's 23 tickets are **implemented and queued to close on merge of draft PR #101** — the PR is still open, so
   `gh` shows them as not-yet-closed. The count is verified via the PR's `closingIssuesReferences`, not by
   closure date.

6. **Prior-sprint model uncertainty.** The repo does not record which model produced the baseline commits. The
   operator says "at best opus." Unverifiable from here — so the comparison is "Fable-orchestrated team vs prior
   human-plus-unknown-model baseline," and any "Fable vs Opus" framing is not supported by repository evidence.

---

## 4. Findings

**F1 — Real orchestration throughput multiple, robust to discounting.** Even after (a) stripping review prose
from the LOC count, (b) counting only `COMPLETED`/queued-to-close tickets, and (c) crediting the framework for
maturity: Sprint F delivered **23 implemented tickets and 5 net-new test suites (29→129 test cases) in a single
~9.5-hour session**, against a baseline norm of 1–2 tickets and a few hundred LOC per single-day session. The
multiple survives the discounts.

**F2 — A verification layer that simply did not exist before.** 24 execution-grounded review files (2,962 lines)
appear for the first time in the repo's history, and they caught bugs by *running* the code, not reading it.
This is the crispest form of the "orchestrator adds QA that cheap labor alone doesn't" argument: it is a new
*category* of output, evidenced by `--diff-filter=A` first-appearance, not a louder version of an old one.

**F3 — Cross-repo, cross-language competence with independent replication.** Same-day, execution-verified podman
support in an unfamiliar Go codebase (+1,198 LOC / 28 files), with the security-critical "hard floor" property
**re-verified by a second session that was not grading its own work** (#95), and a parallel A/B on #103 where two
different-model architect arms independently produced replicating deep-dive audits and each caught findings the
other missed (e.g. the `cursor_policy_hook.py:84` fail-open, verified against source). Independent replication is
the single strongest credibility signal in the dataset because it is the hardest to fake with a lucky run.

---

## 5. What this does and does not justify

**Supports (usable in funding materials):**

- Fable *as an orchestrator over cheaper implementers* converted one high-attention day into ~23 delivered,
  reviewed tickets plus a from-scratch review/verification corpus and a cross-repo Go contribution — well beyond
  the prior single-day baseline, and the gap holds after honest discounting (F1–F3).
- The value concentrates in **judgment work** — planning, routing, adversarial review, live verification,
  independent replication — which is exactly where the more expensive model is worth paying for while Sonnet does
  the bulk typing. That is a specific, defensible spend rationale: **buy Fable for the orchestrator/reviewer seat,
  not for volume code generation.**

**Does NOT support (do not put these in the deck):**

- **"Fable writes ~5,700 lines/day."** ~52% is review prose; real executable output was ~1,166 shell lines.
- **"Cleaned up months of broken CI."** Ground truth from `gh run list`: CI was **green on May 21** and broke
  **this same morning** (00:38, DX-035 deleted the path CI referenced). Sprint F repaired a defect a
  same-day, same-lineage session had *introduced hours earlier* — a within-day self-repair, not the clearing of
  long-standing prior-sprint rot. This is the one framing I would most strongly caution against: it is flattering,
  it appears in the commissioning brief, and it does not survive a 30-second check of the CI run history.
- **"Shipped podman upstream."** The upstream PR (`majorcontext/moat#435`) was **opened and closed unmerged within
  ~44 minutes**. The engineering — substantial, execution-verified, in an unfamiliar language — is real and is
  fair to cite. Upstream *acceptance* is not, and should be stated as "opened a substantial, verified upstream PR,"
  never "landed in upstream."
- **Any "Fable beats Opus by X" number.** Baseline model attribution is unverifiable from the repo (§3.6).

**Net:** the honest, excerptable sentence is roughly — *"On a high-attention day, a Claude Fable session
orchestrating cheaper Sonnet implementers delivered ~23 reviewed tickets, five new test suites, and a
verified cross-repo contribution, with a review pass that caught real bugs by executing them — an output well
above the project's prior single-day baseline, with the caveat that this is a single, high-supervision sample
on a framework whose conventions did much of the enabling work."*

---

*Reproduce: clone the repo, `git log`, `gh issue list`, and the commands in §1. All figures are re-derivable;
where a figure is operator-reported rather than analyst-verified (§2.4 major/minor split), it is labeled as such.*
