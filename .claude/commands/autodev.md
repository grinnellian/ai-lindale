Process the provided tickets through the lifecycle state machine.

## Startup

If specific tickets or a milestone were provided, process them. If no arguments were given, survey open tickets, summarize their states, and recommend what to work on next — then wait for the user to confirm before dispatching.

You should be invoked via `claude --agent tpm` for full hook enforcement. If not, warn the user on first message.

## Routing (DX-039)

Before dispatching a planner or review roster, check for a `routing:` block in
the project's `team-config.yml` (or `.claude/team-config.yml` downstream).

- **Planner lookup:** take the ticket's prefix (`FEAT`, `BUG`, `DX`, etc.) and
  look it up in `routing.planners`. Dispatch the named agent for the
  NEEDS_REVIEW step in place of `architect`. If `routing:` is absent, the
  prefix has no entry, or the value is `architect`, dispatch `architect` —
  today's default behavior is unchanged.
- **Reviewer fan-out:** during the REVIEW state, after the planner-of-record
  reviews the PR, match the PR's changed paths (`gh pr diff --name-only`)
  against each glob key in `routing.reviewers`. Dispatch the mapped agent for
  every matching glob, in addition to the planner review. If `routing:` is
  absent or `reviewers` has no matching entry, review is planner-only — same
  as today.
- Agent names in both tables must be dispatchable via the `Agent` tool — a
  project-defined agent in `.claude/agents/` (see DX-036 / #85, which lifted
  the `Agent(architect, dev)` frontmatter restriction on `tpm.md` so the TPM
  can dispatch any project-defined agent by name). If a configured agent name
  doesn't resolve, fall back to `architect` and note the misconfiguration in
  the ticket comment rather than failing the dispatch.

## State Machine

Read each ticket's labels via `gh issue view N --json labels` to determine state:

| Label | State | Action |
|-------|-------|--------|
| (none) | OPEN | Triage: validate ACs are clear and scoped. Apply `needs-arch-review`. |
| `needs-arch-review` | NEEDS_REVIEW | Spawn the routed planner subagent (see Routing; defaults to **architect**) to review and post TDD plan. On completion, apply `arch-approved`, remove `needs-arch-review`. |
| `arch-approved` | PLANNED | Spawn **dev** subagent to implement. On dispatch, apply `in-progress`, remove `arch-approved`. |
| `in-progress` | IN_PROGRESS | Skip — dev is working. |
| `ready-for-review` | REVIEW | Coordinate review cycle: the routed planner reviews the PR; dispatch additional reviewers per the `routing.reviewers` glob matches for what the PR touches (falls back to planner-only review when unconfigured). Send review issues back to dev for fixes. After all reviews pass: if `--auto-merge`, merge PR and close issue; otherwise report to user. |
| `needs-human` | ESCALATED | Report required human action, skip. On next run, check for human response (issue comment) and resume from appropriate state. |
| `blocked` | BLOCKED | Report blocker, skip. |

## Rules

- Dispatch independent architect reviews in parallel
- Respect ticket dependencies — don't start a ticket until its prerequisites are in `in-progress` or later
- On human escalation: apply `needs-human` label, comment what the human needs to do, move to next ticket
- On blocker: apply `blocked` label, comment context on the issue, move to next ticket
- When all actionable tickets are dispatched, produce a summary table of statuses
- `--auto-merge` skips the human gate, not the review cycle — every PR gets agent review before merge

$ARGUMENTS
