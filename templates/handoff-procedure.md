# Handoff Procedure
#
# Instructions for wrapping up a Lindale-managed engagement: separating
# client deliverables, framework artifacts, and personal notes into their
# own lanes so a successor (human or team) can pick up cleanly, and so the
# framework itself stays reusable for the next engagement.
#
# Derived from the BizTrip engagement handoff (April 2026). Read and follow
# these steps when an engagement is ending — triggered by the user asking
# for a handoff, wrap-up, or offboarding, or by `/handoff`.

## Step 1: Triage Files Into Four Categories

Before creating any branch, sort the repo's current state (committed and
uncommitted) into four buckets:

1. **Client** — deliverables the client owns going forward: product docs,
   open tickets relevant to their roadmap, README/CLAUDE.md content that
   describes the product itself (not the framework running it).
2. **Successor** — notes for whoever picks up the engagement next (human PM,
   another team) that are *about* the engagement but not something the
   client's repo should carry long-term: handoff context, decision
   rationale, open threads, "things I'd do differently."
3. **Framework** — Lindale-specific artifacts: `.claude/agents/`,
   `.claude/commands/`, `memory/`, any bare-metal enforcement scripts the
   engagement added on top of the framework, `team-config.yml`. Useful to
   the next engagement using this framework, not necessarily to this client.
4. **Working-copy** — anything personal to the operator that shouldn't be in
   any shared branch at all: scratch notes, local credentials, WIP
   experiments that never shipped.

A single file can only belong to one bucket. When a file seems to straddle
two (e.g., a memory file with both framework lore and client-specific
decisions), split it before proceeding rather than forcing a choice.

## Step 2: Client Handoff Branch

Create a branch off `main` (convention: `<owner>/client-handoff`) containing
only Client-bucket content: docs and tickets the client's team should see
going forward. This branch is meant to be reviewed and merged (or cherry-
picked) by the client — it should read as "the state of the project," not
"the state of the engagement."

## Step 3: Framework Branch (Unmerged)

Keep Framework-bucket content on its own branch (convention:
`<owner>/framework-handoff`, or a similarly scoped generic name — the
BizTrip engagement this procedure was derived from used
`<owner>/devcontainer-setup`, a name specific to that engagement's own
tooling, not a convention to reuse verbatim) that does **not**
merge into `main`. This branch preserves the agent configuration, memory,
and any engagement-specific tooling used during the engagement so the next
engagement can start from them, without polluting the client's `main` with
framework internals the client didn't ask for and doesn't need to maintain.

## Step 4: Hoist Personal Files Out of the Repo

Working-copy content never touches a shared branch. Move it to a path
outside the repo entirely (e.g., `../notes/pm/`) before the handoff branches
are finalized. If any of it was accidentally committed, remove it from
history on the branch being handed off (not from `main` after the fact —
catch it before pushing).

## Step 5: `.gitignore` Patterns for the Split Model

To keep `main` clean of framework artifacts that only exist on the framework
branch, add entries to `.gitignore` on `main` for anything the framework
branch introduces that shouldn't reappear on `main` by accident (e.g. local
scratch state under `memory/*-local.md`, editor-specific config). This is
advisory, not enforced — the split is maintained by branch discipline (Steps
2-3), `.gitignore` just prevents accidental leakage if someone checks out the
framework branch and later switches back to `main` without a clean tree.

## Step 6: Compose the Handoff Message

Write a single handoff message (issue comment, PR description, or direct
message to the client/successor) that covers:
- What was delivered and where it lives (link the Client branch)
- What's open — ticket references, known gaps, follow-up work
- Where framework/engagement artifacts live if the successor wants them
  (link the Framework branch)
- Any credentials, access, or environment notes the successor needs

**Signing convention:** sign agent-composed handoff messages with the
project-scoped role, not the generic framework role — e.g. "— BizTrip
Lindalë TPM (on Claude)" rather than "-Claude TPM". The handoff message is a
deliverable to a human outside the engagement; it should be traceable to
*which* engagement's TPM composed it, not just that a TPM agent did.

## Step 7 (Optional): Autodev Demo Branch

If useful as a capability demo or proof of value, run `/autodev` against a
handful of open tickets on a disposable branch (convention:
`<owner>/autodev-demo`) and include a short recap (tickets closed, time
taken) in the handoff message. This branch is a demonstration artifact, not
a deliverable — it does not need to merge anywhere.

## Convention: Where Client vs Successor Docs Live

- **Client-bucket** docs are committed to the Client Handoff branch (Step 2)
  — they become part of the client's repo history.
- **Successor-bucket** notes are either committed to the Framework branch
  (Step 3), if they're useful to whoever runs this framework next, or
  hoisted outside the repo (Step 4) if they're specific to this operator and
  not reusable. When in doubt, prefer hoisting — it's easier to bring a note
  back into a repo later than to scrub one that shouldn't have been
  committed.

## Status Checklist

- [ ] Files triaged into Client / Successor / Framework / Working-copy
- [ ] Client handoff branch created off `main`
- [ ] Framework branch created, kept unmerged
- [ ] Personal/working-copy files hoisted outside the repo
- [ ] `.gitignore` updated on `main` if needed
- [ ] Handoff message composed and signed with the project-scoped role
- [ ] (Optional) Autodev demo branch run and recapped
