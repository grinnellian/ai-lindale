Reconcile and rebase the open-PR queue.

## Startup

You should be invoked via `claude --agent tpm` (or an equivalent agent with
`gh`, `git`, and memory-file access) for a dedicated session with the right
tool scope. Both `--agent` and the slash-command form are prompt-level role
adoption — enforcement comes from the container boundary, not the invocation
path. If invoked another way, warn the user on first message.

Review `memory/patterns.md` before starting — the git/GitHub operational lore
section (mergeable-flips-to-UNKNOWN, `git mv` staging, stash hygiene across
worktree switches) applies directly to this command and is not repeated here.

## Phase 1 — Reconcile

1. `gh pr list --state open --json number,title,headRefName,baseRefName,mergeable,updatedAt` to get the live queue.
2. Compare against tracked queue state in memory (e.g. `memory/decisions.md` /
   `memory/patterns.md` references to in-flight PRs, or ticket labels via
   `gh issue view N --json labels`). Note any PR that's untracked, merged,
   closed, or diverged from what memory expects.
3. Recompute the cross-PR conflict matrix: for each pair of open PRs, check
   whether they touch overlapping files (`gh pr diff N --name-only`). Use this
   to classify each PR into the Tier 1/2/3 dispatch model already documented
   in `memory/patterns.md` (Tier 1 = clean off `main`, Tier 2 = stacked on
   another open PR, Tier 3 = hot-file collision, park it).
4. From the conflict matrix, derive a merge order — Tier 1 PRs first (any
   order), then Tier 2 PRs in dependency order, Tier 3 PRs last or excluded
   until unblocked.
5. Commit the reconciliation plan (which PRs are in scope, the conflict
   matrix, the proposed merge order) before touching any branch. If a
   project-specific location for this plan doesn't exist, write it to
   `memory/patterns.md` or a scratch note and say so — do not silently hold
   the plan only in conversation state.

## Phase 2 — Rebase loop

For each PR in the merge order from Phase 1:

1. Check whether the branch is checked out in a worktree
   (`git worktree list`) — if so, work from that worktree path rather than
   creating a second checkout, and respect stash hygiene when switching
   (memory/patterns.md).
2. `git fetch origin && git rebase origin/main` on the PR's branch.
3. On conflict: resolve using the cross-PR conflict matrix from Phase 1 as
   context (a conflict between two PRs known to touch the same file is
   expected, not a surprise). If resolution is non-trivial or ambiguous,
   stop and escalate rather than guessing — this command must never force a
   resolution it isn't confident in.
4. Run the project's toolchain hooks from `team-config.yml` (`test`, `build`,
   `lint`, whichever are configured) to verify the rebased branch before
   pushing. Do not push on a red run.
5. Push the rebased branch. **Never force-push a branch you did not
   create/are not the sole author of, and never force-push `main`/`master`.**
   Use `git push --force-with-lease`, not `--force`, and only after the
   verification step passes.
6. After a merge lands (if this run also merges PRs rather than only
   rebasing them), poll `gh pr view --json mergeable` on the remaining
   queue and wait for it to settle out of `UNKNOWN` before evaluating or
   merging the next PR (memory/patterns.md).
7. If a branch can't be rebased cleanly after one honest attempt, apply the
   insanity-loop rule from CLAUDE.md: don't retry the same resolution a
   second time — park it (`needs-human` or equivalent) and move to the next
   PR in the queue.

## Phase 3 — Report

Produce a summary table: PR number, title, tier, action taken (rebased /
pushed / parked / skipped), and any escalations that need a human. Call out
any PR whose tracked memory state no longer matches reality (merged, closed,
retargeted) so the next `/autodev` or `/pr-refresh` run starts from ground
truth.

$ARGUMENTS
