# Standardization Playbook Bootstrap Procedure
#
# Instructions for the TPM to generate a project-specific standardization
# playbook for a brownfield project. Read and follow these steps when a
# brownfield signal is detected and no playbook already exists.

## Step 1: Detect Brownfield Signal

Check whether `docs/standardization-playbook.md` already exists in the
downstream project. If it does, the project already has a playbook — skip
generation.

Otherwise, look for a brownfield signal: substantial pre-existing code
(more than a handful of source files, or a non-trivial git history) AND a
gap — no test suite, no CI configuration, or no lint/formatter config.

If the project has little or no pre-existing code (greenfield), this
procedure does not apply. Stop — there is nothing to standardize yet.

## Step 2: Gather Audit Findings

Prefer an existing audit: if the `/audit-repo` command (FEAT-002) is
available, run it and use its findings as the source for this playbook.

If `/audit-repo` is not available, perform a manual, read-only pass:
- Find existing tests (test directories, `*test*` files, test runner config)
- Find CI configuration (`.github/workflows/`, other CI config files)
- Find lint/formatter configuration
- Grep for common security smells (hardcoded secrets, disabled TLS
  verification, unsanitized shell/SQL interpolation, etc.)

This pass is read-only — observe and record, fix nothing. Fixes are proposed
as playbook items and executed later, one at a time, as their own tickets.

## Step 3: Read the Meta-Template

Read `templates/standardization-playbook.md` from the framework:
- If running in a downstream project with `.ai-lindale/`, read
  `.ai-lindale/templates/standardization-playbook.md`
- If running in the framework repo itself, read
  `templates/standardization-playbook.md`

## Step 4: Populate the Playbook

Replace all `{{PLACEHOLDERS}}` using only items the audit actually
surfaced in Step 2 — do not invent boilerplate items to fill out a phase.
An empty phase (no rows) is a valid, honest outcome.

For each item, set:
- **Priority**: `P0` for blocking security or correctness issues, `P1` for
  should-fix items, `P2` for nice-to-have improvements
- **Depends on**: any other playbook item (or existing issue) that must
  land first
- **Issue**: filled in during Step 5

Write the populated result to `docs/standardization-playbook.md` in the
downstream project.

## Step 5: Map Items to Issues

For each populated item, create a tracking issue with `gh issue create`,
following the downstream repo's Issue Numbering Protocol for prefix and
numbering. Create Foundation phase issues first, since later phases may
depend on them. Record each issue reference back into the "Issue" column
of `docs/standardization-playbook.md`.

## Step 6: Report

Report a summary to the user: how many items were found per phase, which
issues were created, and which phases came up empty (a valid outcome, not
a failure).

The generated playbook is project-owned — committed to the repo, never
overwritten by framework updates.
