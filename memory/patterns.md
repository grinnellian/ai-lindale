# Patterns and Playbooks

Working patterns for agent operations. Hook-era enforcement lore (bash-allowlist,
enforce-write-paths) has been retired with DX-033 / EPIC-004 — the patterns kept
here are the ones still useful under the container-as-boundary model.

## gh CLI hygiene — multi-line bodies

**Pattern:** for any issue/PR/comment body longer than one line, write the body
to a temp file and use `--body-file`. Never pass multi-line content inline via
`--body`.

1. `printf 'markdown body\nwith\nnewlines' > /tmp/issue-body.md`
2. `gh issue create --title 'PREFIX-NNN: Title' --body-file /tmp/issue-body.md --label LABEL`
3. `gh issue comment N --body-file /tmp/comment.md`

**Rationale:** shell quoting of multi-line strings with backticks, pipes
(markdown tables), or `$(...)` is fragile. Temp files sidestep the entire
quoting/escaping minefield and are easy for humans to review pre-send.
Originally a workaround for the bash-allowlist hook (BUG-004 / BUG-005); the
hook is gone but the practice is still the right default.

## Three-tier dispatch playbook (parallel autodev with open PRs)

When multiple PRs are in flight and the TPM is choosing what to dispatch next,
classify candidate work by collision risk:

### Tier 1 — branch off `main`, zero conflict
Pure-additive work (new files, isolated subtrees). Safe to dispatch in parallel
right now. Examples: new test specs in a dedicated dir, new docs files.

### Tier 2 — stacked branch off an open PR
The candidate touches files that an open PR also touches, or depends on a new
primitive that hasn't landed yet. Branch from the parent PR and open the new PR
with `gh pr create --base <parent-branch>` — GitHub auto-retargets to `main`
when the parent merges.

### Tier 3 — do not start yet
Two or more open PRs touch the same hot file, or the work is blocked on a
`needs-design` / `needs-human` label. Park until conflicts resolve.

### Hot-files matrix
Before dispatching, build (or refresh) a table:

| File | Owned by PR | Don't edit until merged |
|---|---|---|
| `path/to/file` | #NNN | wait |

Cross-reference every candidate against this table. If a candidate edits a
hot-file row, it's Tier 2 or Tier 3, never Tier 1.

**Origin:** distilled from catalyst-build `memory/autodev-strategy-2026-05-20.md`.

## Local-overrides breadcrumb (downstream divergence)

When a downstream project diverges from a Lindalë-shipped file (agent
definition, command, hook, template), leave a breadcrumb so future syncs don't
silently clobber the local edits.

**Pattern:** drop an `AGENT-CUSTOMIZATIONS.md` (or `LOCAL-OVERRIDES.md`) in the
same directory as the diverged file, listing:
- which files are local copies (no longer symlinked to `.ai-lindale/`)
- why the divergence happened
- whether re-syncing from upstream requires manual merge

**Why:** `install.sh` currently overwrites without warning (BUG-007 #78). Until
that's fixed with skip/--force semantics, the breadcrumb is the only signal a
future operator gets that "this file is intentionally not upstream."

**Origin:** catalyst-build `.claude/agents/AGENT-CUSTOMIZATIONS.md`.

## Subagent finalization — TPM picks up where dev drops

**Problem:** dev subagents dispatched via the Agent tool with `isolation:
"worktree"` reliably fail on `Bash`, `Write`, and `Edit` calls even though their
agent definition grants all three. Repro'd 6× on BUG-007 (#78), 4× downstream;
tracked locally as BUG-006 (#77). **Confirmed Claude Code platform constraint**,
not a Lindalë frontmatter issue.

**Upstream tracker (anthropics/claude-code):**
- #37730 — subagents don't inherit `settings.local.json`; worktree path doesn't
  match user-scope settings expectations
- #25526 — `Bash(*)` allowlist doesn't propagate to subagents
- #38859 — `bypassPermissions` silently ignored for Agent-tool subagents
- #40241 — `--dangerously-skip-permissions` doesn't propagate either
- #57037 — parallel-dispatch cascade: first Bash succeeds, subsequent denied
- #29110 — bypassPermissions + worktree fundamentally broken; cleanup silently
  destroys uncommitted agent work
- #37258 — worktree subagents lose parent OAuth credentials (regression 2.1.81)
- #31940 — long-term fix to watch: per-subagent `cwd` / `additionalDirectories`
  in frontmatter

**Diagnostic signature:** if the agent reports first Bash call (e.g. `git
checkout`) succeeds and subsequent calls denied, that's #57037's cascade.

**Hypothesis (needs A/B):** launching the parent with `claude -w <name>` puts
the parent inside a worktree, creating nested-worktree when Dev is dispatched
with `isolation: "worktree"`. Subagent worktree branches from `origin/HEAD`, not
the parent's branch — Dev's staged work can land on a sibling branch the outer
session never sees. Anecdotally the stage-and-finalize workaround holds when
the worktree is requested conversationally but not when launched via `-w`.

**Asymmetry to remember:** dev invoked via `/dev` slash command (frontmatter
inert per BUG-003) works fine — no worktree, normal Write/Edit on main tree.
Dev invoked via Agent tool from TPM honors frontmatter `isolation: worktree`
and hits the bugs above. This is why catalyst-build's manual `/dev` workflow
succeeds while TPM-driven `/autodev` dispatch fails on the same agent
definition.

**Real fix:** EPIC-004 dev-in containers — sidesteps worktree dispatch
entirely. Heavier parallelization cost than worktrees but unblocks dev work
under the current Claude Code platform.

**Pattern:** **dev subagent stages, TPM finalizes.** Expect the subagent's
return payload to contain *staged but unpushed* work. The parent TPM session
(which has full Bash) then:

1. `cd` into the subagent's worktree path (returned in the agent result)
2. Inspect the staged diff (`git status`, `git diff --cached`)
3. Run lint/build/test if needed
4. `git commit` (preserving the subagent's intended message), `git push -u`
5. `gh pr create` with the body the subagent drafted (passed back in its
   return payload — instruct the subagent to *write* the PR body to a file
   like `.claude/pr-body-<issue>.md` since it can't open the PR itself)

**Instruct subagents up front:** "You may not be able to run `git commit` /
`git push` / `gh` from the worktree. If those fail, stage all changes, write
the intended commit message to `.claude/commit-msg.txt` and the PR body to
`.claude/pr-body.md` inside the worktree, then return — TPM will finalize."

This is a workaround, not the desired shape. When BUG-006 is resolved
upstream, the workaround retires.

## Worktree footguns

**Branch-name collisions are silent.** Aborted agent runs leave behind branch
names that later attempts try to claim. Always
`git branch --list 'PREFIX/*'` before claiming a branch name in a worktree
dispatch.

**Tests in dev-containers may bind-mount the main checkout, not the worktree.**
If the project's test command runs inside a container with a bind-mount, the
container sees the *main checkout's* files — not the subagent's worktree. The
subagent thinks it's testing its changes; it's actually testing main.
Options:

1. Have the subagent commit its specs/changes first, then check out the branch
   in the main checkout, *then* run tests. Or:
2. Route the container command through the worktree path explicitly (`docker
   compose exec ... bash -c 'cd /path/in/container/to/worktree && npm test'`).
   Or:
3. Defer to CI — let the PR's CI run be the source of truth for test results,
   and dispatch the subagent only to land code.

**Origin:** catalyst-build `memory/autodev-state-2026-05-20.md` §"Process
refinements adopted mid-wave".
