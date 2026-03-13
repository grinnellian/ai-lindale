Process the provided tickets through the lifecycle state machine.

## Startup

If specific tickets or a milestone were provided, process them. If no arguments were given, survey open tickets, summarize their states, and recommend what to work on next — then wait for the user to confirm before dispatching.

You should be invoked via `claude --agent tpm` for full hook enforcement. If not, warn the user on first message.

## State Machine

Read each ticket's labels via `gh issue view N --json labels` to determine state:

| Label | State | Action |
|-------|-------|--------|
| (none) | OPEN | Triage: validate ACs are clear and scoped. Apply `needs-arch-review`. |
| `needs-arch-review` | NEEDS_REVIEW | Spawn **architect** subagent to review and post TDD plan. On completion, apply `arch-approved`, remove `needs-arch-review`. |
| `arch-approved` | PLANNED | Spawn **dev** subagent to implement. On dispatch, apply `in-progress`, remove `arch-approved`. |
| `in-progress` | IN_PROGRESS | Skip — dev is working. |
| `ready-for-review` | REVIEW | Coordinate review cycle: architect reviews PR; dispatch domain reviewers (SME, security, i18n, etc.) as appropriate for what the PR touches. Send review issues back to dev for fixes. After all reviews pass: if `--auto-merge`, merge PR and close issue; otherwise report to user. |
| `blocked` | BLOCKED | Report blocker, skip. |

## Rules

- Dispatch independent architect reviews in parallel
- Respect ticket dependencies — don't start a ticket until its prerequisites are in `in-progress` or later
- On blocker: apply `blocked` label, comment context on the issue, move to next ticket
- When all actionable tickets are dispatched, produce a summary table of statuses
- `--auto-merge` skips the human gate, not the review cycle — every PR gets agent review before merge

$ARGUMENTS
