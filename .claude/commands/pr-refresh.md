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

This is the queue-maintenance companion to `/autodev` (`.claude/commands/autodev.md`):
`/autodev` drives individual tickets through the lifecycle state machine and
its review/merge cycle, while `/pr-refresh` reconciles and rebases the queue
of open PRs those runs produce. Run it before or between `/autodev` passes,
not as a substitute for either command's own review gate.

## Phase 1 — Reconcile

1. `gh pr list --state open --limit 100 --json number,title,headRefName,baseRefName,mergeable,updatedAt`
   to get the live queue (the default cap of 30 would silently truncate a
   longer queue mid-reconcile).
2. Compare against tracked queue state in memory. The primary source is the
   autodev-state tracker (`memory/autodev-state-<date>.md`, the most recent
   one — see `autodev.md`'s Memory section); ticket labels via
   `gh issue view N --json labels` corroborate it. `memory/decisions.md` /
   `memory/patterns.md` are durable lore, not run state — consult them for
   conventions, not for which PRs are in flight. Note any PR that's
   untracked, merged, closed, or diverged from what memory expects.
3. Recompute the cross-PR conflict matrix: for each pair of open PRs, check
   whether they touch overlapping files (`gh pr diff N --name-only`). Use this
   to classify each PR into the Tier 1/2/3 dispatch model already documented
   in `memory/patterns.md` (Tier 1 = clean off `main`, Tier 2 = stacked on
   another open PR, Tier 3 = hot-file collision, park it).
4. From the conflict matrix, derive a merge order — Tier 1 PRs first (any
   order), then Tier 2 PRs in dependency order, Tier 3 PRs last or excluded
   until unblocked.
5. Record the reconciliation plan (which PRs are in scope, the conflict
   matrix, the proposed merge order) and `git commit` it before touching any
   branch — "commit" here means an actual git commit, so the plan survives
   the session. Write it into the autodev-state tracker
   (`memory/autodev-state-<date>.md`) or a dated scratch note — not
   `memory/patterns.md` or `memory/decisions.md`, which hold durable lore
   and would accrete per-run noise. Do not hold the plan only in
   conversation state.

## Phase 2 — Rebase loop

For each PR in the merge order from Phase 1:

1. Check whether the branch is checked out in a worktree
   (`git worktree list`) — if so, work from that worktree path rather than
   creating a second checkout, and respect stash hygiene when switching
   (memory/patterns.md).
2. Rebase onto the PR's actual base branch, not a hardcoded `main` — use the
   `baseRefName` fetched in Phase 1 step 1 (`gh pr view <number> --json
   baseRefName` if it needs refreshing): `git fetch origin && git rebase
   origin/<baseRefName>`. For a Tier 1 PR this is ordinarily `main`; for a
   Tier 2 PR stacked on another open PR, `baseRefName` is that PR's branch —
   rebasing onto `origin/main` instead would replay the parent branch's
   commits into the child and pollute its diff. If the parent PR in a Tier 2
   pair hasn't merged yet, this step still rebases onto the parent branch as
   it currently stands; re-run once the parent merges and GitHub retargets
   the child.
3. On conflict: resolve using the cross-PR conflict matrix from Phase 1 as
   context (a conflict between two PRs known to touch the same file is
   expected, not a surprise). If resolution is non-trivial or ambiguous,
   stop and escalate rather than guessing — this command must never force a
   resolution it isn't confident in.
4. Run the project's toolchain hooks from `team-config.yml` (or
   `.claude/team-config.yml` downstream) — `test`, `build`, `lint`,
   whichever are configured — to verify the rebased branch before pushing.
   If no toolchain block is configured (in this upstream repo there is no
   live `team-config.yml` at all), fall back to the test/build commands the
   project's own `CLAUDE.md` documents (here: the suites under
   `scripts/tests/`). If neither source yields a verification command, do
   **not** push the rebase unverified — park the PR and note the missing
   toolchain configuration in the report. Do not push on a red run.
5. Push the rebased branch. **Never force-push `main`/`master`, and never
   force-push a branch other agents or humans may have pushed to since your
   fetch** (rebase-pushing a dev-agent PR branch this command just rebased
   is the normal case, not a violation of this rule). Use
   `git push --force-with-lease`, not `--force`, and only after the
   verification step passes.
6. After a merge lands (if this run also merges PRs rather than only
   rebasing them), poll `gh pr view --json mergeable` on the remaining
   queue and wait for it to settle out of `UNKNOWN` before evaluating or
   merging the next PR (memory/patterns.md).
7. If a branch can't be rebased cleanly after one honest attempt, park it
   (`needs-human` or equivalent) and move to the next PR in the queue. This
   one-attempt policy is deliberately *stricter than* CLAUDE.md's
   insanity-loop rule (which triggers at 3+ identical failures) — rebase
   conflicts don't resolve differently on a second identical attempt, and
   the queue shouldn't stall behind one PR.

## Phase 3 — Report

Produce a summary table: PR number, title, tier, action taken (rebased /
pushed / parked / skipped), and any escalations that need a human. Call out
any PR whose tracked memory state no longer matches reality (merged, closed,
retargeted) so the next `/autodev` or `/pr-refresh` run starts from ground
truth.

$ARGUMENTS
