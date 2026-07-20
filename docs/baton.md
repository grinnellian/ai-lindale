# BATON v1

A light, machine-greppable handoff contract for continuation trampolines
(`scripts/trampollm.sh`, FEAT-018) that chain fresh `claude -p` invocations
into a multi-bounce relay. Findings that motivated this shape came from the
FEAT-017 spike (#107) — see that issue for the empirical background.

This is a standalone schema doc: downstream tickets can cite BATON v1
without depending on the trampoline script itself.

## The block

A baton is a fenced block of `key: value` lines, emitted as the tail of a
bounce's final message:

```
--- BATON v1 ---
status: CONTINUE | DONE | PARK | ESCALATE
goal: <one line, copied verbatim from the previous baton — stable across bounces>
ticket: #NNN
next-agent: dev | architect | tpm | <same>
done-criteria: <how the chain knows to emit DONE>
state: <what is now true: branch, commits, tests green/red; may point at a tracker file>
next-step: <the successor's first action — imperative>
breadcrumbs: <tried-and-failed, gotchas; "none" allowed>
--- END BATON ---
```

Why this shape (not free text, not full JSON): fenced key/value is
machine-greppable, human-readable when posted in an issue comment (glass
walls), and robust to an LLM's tendency to paraphrase — the FEAT-017 spike
observed 7/7 trials reproducing the sentinel fence verbatim when the wrapping
prompt demanded it explicitly. The prompt contract is part of the utility,
not optional: a relay only works because every bounce is instructed to end
with a complete block.

## Field requirements

| Field | Requirement | Notes |
|---|---|---|
| `--- BATON v1 ---` / `--- END BATON ---` fence | **Hard** | The sentinel a trampoline parses on. Emit exactly one block; if more than one appears, the last is used. |
| `status:` | **Hard** | One of `CONTINUE \| DONE \| PARK \| ESCALATE`. Case-insensitive by convention; trampolines uppercase before dispatch. |
| `goal:` | contract-by-convention | Copied verbatim bounce-to-bounce so drift is visible. |
| `ticket:` | contract-by-convention | `#NNN`. When present, a trampoline can auto-adopt it for escalation even if not passed on the CLI. |
| `next-agent:` | contract-by-convention | Persona for the next bounce. `<same>` (or empty) keeps the current agent. |
| `done-criteria:` | contract-by-convention | How the chain recognizes it should emit `DONE`. |
| `state:` | contract-by-convention | What is now true — may be a pointer into a durable ledger rather than a restatement of it (see DX-038 below). |
| `next-step:` | contract-by-convention | The successor's first action, written as an imperative. |
| `breadcrumbs:` | contract-by-convention | Tried-and-failed attempts, gotchas. `"none"` is a valid value. Excluded from the loop-detection hash (see below) so breadcrumb-only edits don't count as forward progress, and can't mask a genuine repeat either. |

Only the fence and `status:` are enforced by the trampoline loop itself; the
remaining fields are enforced by the wrapping relay prompt (contract-by-convention),
not by a parser. A trampoline that receives a reply without a valid fence
and `status:` treats it as a malformed baton — one corrective re-prompt, then
a trip (see `scripts/trampollm.sh`'s exit code table).

## Status vocabulary

| Status | Meaning |
|---|---|
| `CONTINUE` | Another bounce picks up this baton verbatim as its seed context. |
| `DONE` | The relay terminates successfully (trampoline exit 0). |
| `PARK` | The relay stops; a human is notified (trampoline exit 2). |
| `ESCALATE` | The relay stops; a human is notified (trampoline exit 2). Distinct from `PARK` in intent — `PARK` implies "resumable later," `ESCALATE` implies "needs a decision" — but a trampoline handles both identically today. |

## Identity and signing

Batons are **unsigned by design**. A human-facing handoff (see FEAT-013
below) carries a signature because a person is accountable for it; a baton
is machine-to-machine, and its identity is the `next-agent:` routing field,
not a signature block.

## Relations to neighboring contracts

BATON v1 shares field *names* with two other in-flight conventions where the
concepts rhyme, but is deliberately not the same contract as either:

- **DX-038 memory state tracker (#89) — shared subset + pointer, not the
  same contract.** The tracker is the durable ledger; the baton is the
  in-flight message carrying a delta and a pointer into it (`state:`). Never
  duplicate the ledger in a baton — the baton is the entire seed context for
  the next fresh window, so it must stay small.
- **FEAT-013 handoff (#62) — deliberately separate.** The handoff is
  human-facing, prose, and signed; the baton is machine-to-machine, emitted
  per-bounce, and unsigned. `goal`/`state`/`next-step` are shared field
  names so the concepts rhyme across the two documents; nothing else is
  shared.
- **EPIC-005 k10s task ticket (#70) — superset candidate.**
  `goal`/`status`/`ticket`/`breadcrumbs` map onto k10s's
  `description`/`context`/`ticket_id`; a k10s task ticket would add
  `signature`, `budget`, and `additional_endpoints` on top. BATON v1 is
  designed so those fields can be added without renaming anything already
  here. No dependency in either direction as of v1.

## Observability

Every baton is written verbatim to
`memory/trampoline/<run-id>/NNN-baton.md` (zero-padded, one file per bounce)
— the chain of these files is the audit trail. When a rail trips
(`--max-bounces`, cumulative `--max-cost-usd`, identical-baton loop
detection, exhausted error retries, or an unrecoverable malformed baton),
the trampoline writes `memory/trampoline/<run-id>/TRIPPED.md` containing the
rail name, bounce count, cumulative cost, and the last good baton verbatim —
the resume path is feeding that block back in as a fresh `--prompt`. If
`ticket:` is known (from `--ticket` or supplied by the baton itself), the
trip also posts an issue comment and adds the `needs-human` label.
