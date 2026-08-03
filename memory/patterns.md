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

**Update (2026-07-06, DX-037 review): the commit-failure claim below is stale.**
This orchestration wave dispatched 15 worktree dev agents that all committed via
`Bash` (`git commit`) without failure — `Write`/`Edit` also worked, as expected
since they never depended on the bugs below. `git push` and `gh` (PR creation,
issue comments) remain **untested** in this mode and should still be treated
with the caution the historical evidence below establishes. Read the section
below as "originally observed for commit/push/gh; commit is now known-good,
push/gh unconfirmed either way" rather than as current-state truth for `git
commit` specifically. See `.claude/agents/tpm.md` §"Dispatching dev subagents"
and `.claude/agents/dev.md`'s TDD section for the narrowed workaround.

**Problem (original, historical):** dev subagents dispatched via the Agent tool with `isolation:
"worktree"` reliably fail on `Bash`, `Write`, and `Edit` calls even though their
agent definition grants all three. Repro'd 6× on BUG-007 (#78), 4× downstream;
tracked locally as BUG-006 (#77). **Confirmed Claude Code platform constraint**,
not a Lindalë frontmatter issue — at the time this was written. Do not assume
this reproduces on `git commit` today; verify push/gh before relying on this
section for those.

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

**Real fix:** EPIC-004 pod containers (pod-base, INFRA-012) — sidesteps worktree dispatch
entirely. Heavier parallelization cost than worktrees but unblocks dev work
under the current Claude Code platform.

**Pattern, narrowed (2026-07-06): dev subagent commits, TPM finalizes push/PR.**
Expect the subagent's return payload to contain a *committed* change (per the
2026-07-06 evidence above) that is not yet pushed or opened as a PR. The parent
TPM session (which has full Bash) then:

1. `cd` into the subagent's worktree path (returned in the agent result)
2. Inspect the commit(s) (`git log`, `git show`) — or, if the subagent fell
   back to stage-and-return because `git commit` itself failed for it, the
   staged diff (`git status`, `git diff --cached`) instead
3. Run lint/build/test if needed
4. `git commit` only if step 2 found staged-not-committed work (preserving the
   subagent's intended message from `.claude/commit-msg.txt`); otherwise skip —
   the commit already exists
5. `git push -u`
6. `gh pr create` with the body the subagent drafted (passed back in its
   return payload — instruct the subagent to *write* the PR body to
   `.claude/pr-body.md` since it can't open the PR itself; that path is the
   one every other statement of this protocol names — dev.md, tpm.md's
   dispatch quote, and the quote below)

**Instruct subagents up front:** "Run `git commit` normally — this works from a
worktree dispatch as of 2026-07-06. If `git push` or `gh` fails, commit
locally, write the PR body to `.claude/pr-body.md` inside the worktree, and
return — TPM will finalize the push and PR. If `git commit` itself
unexpectedly fails, fall back fully: stage everything, write the intended
commit message to `.claude/commit-msg.txt` and the PR body to
`.claude/pr-body.md`, then return — TPM will finalize the commit too."

This is a workaround for the push/gh half, not the desired end shape (the
commit half may no longer need one at all). When BUG-006 is fully resolved or
disproven upstream, retire whatever workaround remains.

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

**Orphaned worktrees crash file-watchers.** Aborted agent runs leave worktrees
under `.claude/worktrees/` containing dangling relative-symlink hooks; dev
servers with glob-tracking watchers (e.g. Turbopack) crash on them. Prune
orphaned worktrees (`git worktree prune` + delete the directory) as part of
dispatch cleanup.

**DX-034 (#80) findings: worktree location under `.claude/` is a Claude Code
harness default, not a Lindalë-configured path.** `dev.md`'s frontmatter only
sets `isolation: worktree` — it never specifies a directory — and no committed
`.claude/settings.json` or CLI flag exposes a worktree-base-path knob (`claude
--help` shows `-w/--worktree` with no path option). Confirmed empirically: a
dev subagent's own working directory lands at `.claude/worktrees/agent-<id>/`
with no Lindalë config driving that choice. The permission-prompt noise on
every worktree op is therefore harness behavior Lindalë cannot relocate from
agent definitions, `CLAUDE.md`, or `settings.json` today. What *is*
Lindalë-controlled: documenting the constraint (here and in `dev.md`) and
routine pruning of orphaned worktrees so the directory doesn't accumulate
stale state. If Claude Code ever exposes a worktree-base-path setting, revisit
this note and wire it up; until then, treat DX-034 as blocked on upstream
rather than fixable in this repo.

**Stash hygiene across detached-HEAD switches.** A stash created before
switching branches/worktrees in detached-HEAD state is easy to strand. Pop or
apply the stash before the next switch; never leave a dispatch with a dirty
stash.

## maxTurns is a hard stop, not a graceful exit (DX-029)

**Platform-level limitation, not prompt-enforceable.** DX-029 added `maxTurns` to
every agent's frontmatter (and, per the DX-029 review, `templates/sme.md`) as a
runaway ceiling. AC3 of that ticket asked for graceful behavior on limit reached
("summary + exit, not hard kill"). Verified against the live Claude Code
subagent frontmatter reference (see `memory/reviews/pr-101/DX-029.md`): the
documented semantics are "Maximum number of agentic turns before the subagent
stops" — a stop, full stop. There is no prompt-level hook that fires before the
cutoff to let an agent emit "what was accomplished and what remains"; the
harness owns the cutoff and the agent gets no final turn to summarize.

**Disposition:** treat AC3 as waived at the platform level, not deferred as an
implementation gap. Keep setting `maxTurns` everywhere (including
TPM-generated SME agents) as a ceiling against insanity loops — it still does
that job — but don't design future work around an assumed graceful-exit
callback that the platform doesn't expose. If Claude Code ever adds a
pre-cutoff hook, revisit this note.

## Git/GitHub operational lore (harvested from catalyst-build)

**`mergeable` flips to UNKNOWN after each merge.** GitHub recomputes PR
mergeability for ~5–15s after any merge to the base branch. When merging a
queue, poll `gh pr view --json mergeable` until it settles before merging the
next one — don't treat UNKNOWN as a conflict.

**`git mv` does not stage later edits.** After `git mv old new`, a subsequent
Write/Edit to `new` is an *unstaged* modification. `git add` explicitly before
committing or the commit ships the pre-edit content.

**Fetching GitHub issue attachments needs auth.** Plain `curl` on
`github.com/user-attachments/assets/<uuid>` returns a 9-byte "Not Found".
Working incantation:
`curl -sL -H "Authorization: Bearer $(gh auth token)" -o <file> <url>`,
then sanity-check the size with `file`/`wc -c`. Subagents without gh auth
should ask the dispatching TPM to pre-download.

## Downstream conventions worth knowing (harvested from juno)

**Committed `settings.json` vs personal `settings.local.json`.** A downstream
can commit team-wide harness config (e.g. `{"worktree": {"bgIsolation":
"none"}}`) in `.claude/settings.json` while keeping personal permission
allowlists in the gitignored `settings.local.json`. Upstream should document
this split (adoption guide) rather than treating all settings as personal.

**Tombstone-override technique.** To retire a framework-provided agent in a
downstream without fighting install.sh: replace the symlink with a real file
containing `tools: [Read]`, a DEPRECATED description, and a pointer to the
replacement. install.sh's local-override detection (BUG-007) then leaves it
alone. Signals a framework gap when it happens — see DX-039 (#90).

**Commit-trailer opt-out.** Some downstreams require agents to omit session
trailers (`Claude-Session:` URLs) and keep only `Co-Authored-By`. Respect a
project's CLAUDE.md on this; it is a legitimate per-project policy.

**`isolation: worktree` is not universally viable.** juno's authored dirs are
live game-save junctions that cannot exist in a worktree copy; it removed
`isolation: worktree` from dev.md with an in-file rationale. Treat worktree
isolation as a per-project default, not an invariant.

## Harvest residue — surveyed but deliberately not ticketed (2026-07-06)

Fan-out survey of downstream installs; big items became #88–92. These were
judged low-priority or counter-direction — recorded so the next harvest
doesn't re-litigate them:

- **block-risky.sh deny hook** (catalyst-build, also nested in
  sticker-ninja/catalyst-build): PreToolUse deny-list for rm -rf /
  force-push / hard-reset. NOT lifted — runs counter to the
  container-as-boundary pivot (EPIC-004). Revisit only if a downstream
  demands bare-metal guardrails.
- **SME archetypes** (juno): "write-scoped documentarian" and "read-only
  adversarial checker" agent shapes could enrich templates/sme-bootstrap.md.
- **cortex-recall skill** (cortex-tools + account-migration, byte-identical):
  reusable "search archived claude.ai history" skill; harvest only if the
  cortex DB/MCP becomes part of the stack.
- **In-repo memory protocol phrasing** (cortex-tools CLAUDE.md): one-fact-
  per-file + MEMORY.md index convention — candidate wording for
  templates/CLAUDE.md.
- **juno team-config.yml**: real-world exemplar of a no-CI project (prose
  toolchain, Knowledge/ instead of memory/) — reference for adoption-guide
  examples.
- **juno generic skill patterns — NOT yet landed** (FEAT-011 #91 non-goals
  routing, flagged by the FEAT-011 review m3): issue #91 committed the two
  generic patterns inside juno's project skills to this file "instead" of
  porting the skills themselves — (1) per-file subagent commit-message
  fan-out (from juno's `autocommit`), (2) gated intake → parallel design →
  sequential implementation (juno's mission-design flow). Neither entry was
  ever written, and they cannot be reconstructed faithfully without access
  to the juno repo — this note records the debt explicitly so the routing
  promise isn't silently lost. Next session with juno access: land the two
  entries here, or note on #91 where they moved.

## Worktree branch collision on review-fix cycles (FEAT-018 run, 2026-07-20)

When a second dev subagent is dispatched to fix review findings on a branch
the first dev created, the branch is still checked out in the first agent's
worktree (`.claude/worktrees/agent-<id>/`), so `git checkout <branch>` fails
and sandboxing blocks editing the other agent's worktree. Working pattern
(discovered by the fix-cycle dev on PR #109): create a local tracking branch
(`git checkout -b <name> origin/<branch>`), do the work there, and push
`HEAD:<branch>` — the PR updates normally, no force-push needed. Candidate
for dev.md's subagent-fallback section; related: BUG-006 (#77), DX-034 (#80).
