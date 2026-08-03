Walk through the standardized engagement handoff checklist.

## Startup

You should be invoked via `claude --agent tpm` (or an equivalent agent with
`git`, `gh`, and memory-file access). If not, warn the user on first message.

This command is for wrapping up a Lindale-managed engagement — read
`templates/handoff-procedure.md` (or `.ai-lindale/templates/handoff-procedure.md`
in downstream projects) in full before doing anything else. That file is the
source of truth for the procedure; this command just drives it interactively.

## Procedure

Follow `templates/handoff-procedure.md` step by step:

1. **Triage.** Sort the repo's current state into Client / Successor /
   Framework / Working-copy buckets (Step 1). Report the triage to the user
   before creating any branch — this is the point to catch a miscategorized
   file cheaply.
2. **Client handoff branch.** Create the branch off `main` (Step 2) with only
   Client-bucket content.
3. **Framework branch.** Create the unmerged framework branch (Step 3).
4. **Hoist personal files.** Move Working-copy content outside the repo
   (Step 4). If any of it is already committed on a branch about to be
   shared, stop and flag it rather than pushing — do not silently rewrite
   history that isn't yours.
5. **`.gitignore` check.** Decide whether `main` needs new `.gitignore`
   entries per Step 5.
6. **Compose the handoff message.** Draft the message per Step 6, including
   the signing convention (project-scoped role, not the generic framework
   role). Show the draft to the user before sending/posting it.
7. **Optional autodev demo.** Only run Step 7 if the user asks for a demo
   branch — it is not part of the default checklist.

## Rules

- This command never force-pushes or rewrites `main` — the Client and
  Framework branches are additive; landing them on `main` (if at all) is a
  human decision, not something this command does automatically.
- Do not skip the triage report-back in Step 1, even under time pressure —
  miscategorized files are the most common handoff mistake and are far
  cheaper to fix before a branch exists than after.
- If the engagement's repo has no clear "client" (e.g., this is an internal
  or framework-only project), say so and skip Steps 2 and the client-facing
  parts of Step 6 rather than forcing the split.

## Report

At the end, summarize: which branches were created, what was hoisted where,
and the final handoff message (with its signature) for the user to review
before it goes out.

$ARGUMENTS
