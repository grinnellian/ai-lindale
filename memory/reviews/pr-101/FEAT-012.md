# Review: FEAT-012 — /pr-refresh command (reconcile and rebase the open-PR queue)

- **Ticket:** FEAT-012
- **Issue:** #92 (no comments; issue body is the authoritative spec)
- **Reviewer:** Claude Reviewer (fable)
- **Date:** 2026-07-06
- **Commit under review:** `43575e2` (feat(FEAT-012): add /pr-refresh command, +72 lines, single file), as amended by `9672c16` (doc sweep rewrote the hook-era Startup wording — line 5–9 of the current file). Reviewed at current state of `.claude/commands/pr-refresh.md` on `orchestrate/2026-07-06`.
- **Verdict:** REQUEST-CHANGES

## Acceptance criteria

| # | AC (from issue #92) | Status | Evidence |
|---|---|---|---|
| 1 | Generic `.claude/commands/pr-refresh.md` upstream — catalyst's known-bug-ledger conflict rules and docker test invocations genericized to `team-config.yml` toolchain hooks or dropped | Satisfied | File contains no catalyst-, docker-, or bug-ledger-specific references (grep clean). Verification is genericized to "toolchain hooks from `team-config.yml` (`test`, `build`, `lint`)" (Phase 2 step 4), matching the commented `toolchain:` block in `templates/team-config.yml:16-20`. Conflict rules generalized to the cross-PR conflict matrix. See MINOR-3 for a fallback gap. |
| 2 | Referenced from autodev docs as the queue-maintenance companion | **Not satisfied** | `grep -rn pr-refresh` across the repo hits only `README.md:35` and `CLAUDE.md:66` — both are file-tree listing lines added by the later doc sweep (`9672c16`), not a companion reference. `.claude/commands/autodev.md` contains zero occurrences of "pr-refresh", "queue", "refresh", or "companion". `docs/` has no reference either. The FEAT-012 commit touched only `pr-refresh.md` (1 file changed). |
| 3 | Phase 1 — reconcile: memory state vs live `gh pr list`, recompute conflict matrix and merge order, commit the plan | Satisfied with deviations | Steps 1–5 cover all four elements. Deviations: tracked-state pointer and plan location diverge from the autodev-state tracker convention (MINOR-1, MINOR-2). |
| 4 | Phase 2 — rebase loop: rebase off main, worktree-locked branches, conflict resolution, verification before push, never force-push shared branches | Mostly satisfied | Worktree handling (step 1), matrix-informed conflict resolution with escalate-don't-guess (step 3), verify-before-push with red-run block (step 4), force-with-lease-only discipline (step 5) all present. Rebase target is hardcoded to `origin/main` for all tiers — wrong for Tier 2 stacked PRs (MAJOR-2). |
| 5 | Phase 3 — report | Satisfied | Summary table spec (PR, title, tier, action, escalations) plus a memory-vs-reality drift callout feeding the next `/autodev` or `/pr-refresh` run. |
| 6 | Embedded lore (mergeable→UNKNOWN ~5–15s, `git mv` staging) lands in `memory/patterns.md`; command defers rather than duplicates | Satisfied | Lore exists at `memory/patterns.md:186-193` ("Git/GitHub operational lore (harvested from catalyst-build)"), landed prior to this ticket (`410a83f`). The command's Startup (lines 11–13) and Phase 2 step 6 point at patterns.md and omit the details (no 5–15s figure, no `git add` mechanics) — correct deference, not duplication. The Tier 1/2/3 model is likewise referenced against `memory/patterns.md` (three-tier dispatch playbook, lines 23–50) with only one-line glosses inline. |

## Findings by severity

### Blocker
None.

### Major

**MAJOR-1 — AC 2 unmet: no autodev-docs cross-reference.** The issue's second scope checkbox requires `/pr-refresh` be "referenced from autodev docs as the queue-maintenance companion." `autodev.md` does not mention it; neither does anything in `docs/`. The only repo-wide mentions are file-tree lines in `README.md`/`CLAUDE.md` added by an unrelated doc sweep, which list the file's existence but do not establish the companion relationship. One sentence in `autodev.md` (e.g., near the dispatch/tier material) closes this.

**MAJOR-2 — Phase 2 step 2 hardcodes `git rebase origin/main` for every PR, including Tier 2 stacked PRs.** Phase 1 explicitly classifies Tier 2 as "stacked on another open PR" (base = parent branch, per `memory/patterns.md:32-36`, which documents `gh pr create --base <parent-branch>`). Rebasing a stacked child onto `origin/main` before its parent merges replays the parent's commits into the child branch, polluting the child PR's diff with the parent's changes. Phase 1 step 1 already fetches `baseRefName` in the JSON, but Phase 2 never uses it. Fix: rebase onto `origin/<baseRefName>` (or state explicitly that Tier 2 PRs are only rebased after their parent has merged and GitHub has retargeted them — the command's rebase-only mode, acknowledged in step 6's "if this run also merges," cannot rely on that ordering).

### Minor

**MINOR-1 — Phase 1 step 2 points at the wrong memory files for tracked queue state.** It says to compare against "`memory/decisions.md` / `memory/patterns.md` references to in-flight PRs." The convention established in `autodev.md` (same branch) is that live queue/dispatch state lives in `memory/autodev-state-<date>.md` — "Labels alone go stale across sessions; the tracker doesn't." The reconcile phase should name the autodev-state tracker as the primary tracked-state source; decisions.md/patterns.md are durable lore, not run state.

**MINOR-2 — Phase 1 step 5 suggests writing the reconciliation plan into `memory/patterns.md`.** Same layering problem as MINOR-1 in the write direction: a per-run plan (PR scope, conflict matrix, merge order) is transient state and would accrete noise in the durable patterns file. The autodev-state tracker (or a dated scratch note, which the step also allows) is the right home. Also, "Commit the reconciliation plan" is ambiguous between "git commit it" and "record it" — the issue said "commit the plan"; the command should say which.

**MINOR-3 — `team-config.yml` reference lacks path and absent-config fallback.** `autodev.md`'s routing section models the right pattern: "the project's `team-config.yml` (or `.claude/team-config.yml` downstream)" plus explicit behavior when the block is absent. Phase 2 step 4 gives neither. In this upstream repo there is no live `team-config.yml` at all (only `templates/team-config.yml`, where `toolchain:` is commented out), so a literal run here reaches step 4 with nothing configured and no instruction — does it push unverified, or park? Say which.

### Nit

**NIT-1 — Force-push rule phrasing undercuts the command's own core operation.** "Never force-push a branch you did not create/are not the sole author of" read literally forbids rebase-pushing dev-agent-authored PR branches — which is most of what this command exists to do in this framework. The intent (never force-push shared/protected branches; `--force-with-lease` elsewhere) is clear from context, but the sole-author clause should be reworded to something like "a branch other agents/humans may have pushed to since your fetch."

**NIT-2 — Insanity-loop attribution is looser than the cited rule.** Step 7 applies a one-honest-attempt park policy and attributes it to "the insanity-loop rule from CLAUDE.md," whose stated threshold is 3+ identical failures. The stricter policy is defensible for rebase conflicts (and consistent with CLAUDE.md's "repeating a failing operation identically is never the right move"), but say "stricter than" rather than implying equivalence.

**NIT-3 — `gh pr list` in Phase 1 step 1 has no `--limit`.** The default caps at 30 results; a longer queue would be silently truncated during reconcile. Unlikely at this repo's scale, cheap to add.

## Verified by running vs by reading

**Verified by running:**
- `gh api repos/grinnellian/ai-lindale/issues/92` — retrieved the authoritative spec; confirmed zero comments (`"comments": 0`). (`gh issue view` itself returned empty output in this environment; the API call was the fallback.)
- `git log` / `git show 43575e2` and `git show 9672c16 -- .claude/commands/pr-refresh.md` — confirmed the file's full history is exactly two commits: FEAT-012 creation and the doc sweep's Startup rewrite (hook-era "full hook enforcement" line replaced with container-as-boundary framing, now consistent with `autodev.md`'s Startup).
- `grep` sweeps for `pr-refresh` repo-wide (AC 2), for the lore anchors in `memory/patterns.md`, and for catalyst/docker residue in the command file.

**Verified by reading only:**
- The command's operational correctness as a playbook (rebase targets, force-push discipline, verification gating). This is a markdown slash command with no test harness — nothing in `scripts/tests/` or CI exercises command files, and there is no honest way to unit-test prose instructions. Executing `/pr-refresh` for real would mutate live PR branches and is out of scope for a read-only review.
- Downstream propagation: `scripts/install.sh:138-146` symlinks all `.claude/commands/*.md` by glob (BUG-008), so `pr-refresh.md` reaches downstream installs automatically. Read, not executed.
- `templates/team-config.yml` toolchain block (commented-out template) and `memory/patterns.md` tier/lore sections.

## Summary

The command itself is a well-built playbook: faithful to the three-phase spec, correctly defers to patterns.md lore instead of duplicating it, and carries real operational discipline (escalate-don't-guess conflicts, red-run push block, force-with-lease-only, park-and-move-on). Two things block approval: the issue's second scope checkbox (autodev docs cross-reference) was simply not done, and the rebase loop's hardcoded `origin/main` target contradicts the Tier 2 stacked-PR model the same command computes in Phase 1. Both are small, targeted fixes.

-Claude Reviewer (fable)
