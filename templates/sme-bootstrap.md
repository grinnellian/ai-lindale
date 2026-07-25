# SME Bootstrap Procedure
#
# Instructions for the TPM to generate a project-specific domain SME agent.
# Read and follow these steps when no SME agent is detected.

## Step 1: Detect Existing SME

Before generating, check whether an SME already exists using two passes:

**Pass 1 — convention match:**
Look for any file matching `*-sme.md` or `sme.md` in `.claude/agents/`.
If found, the project already has an SME. Skip generation.

**Pass 2 — content match:**
If no convention match, read any agent file in `.claude/agents/` that is NOT
one of the core framework agents (`architect.md`, `tpm.md`, `dev.md`). Check
whether its content describes a domain expert, subject matter expert, or
read-only reviewer role. If found, treat it as the project's SME and skip
generation.

This handles projects that already have a hand-written domain expert predating
the framework (e.g., `forensic-accountant.md`, `regulatory-advisor.md`).

## Step 2: Read Project Context

Read the following files from the repo root:
- `CLAUDE.md`
- `README.md`
- `team-config.yml` or `.claude/team-config.yml` (if either exists)
- Any config files that exist: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.

## Step 3: Identify Domain

If `team-config.yml` contains an `sme.domain_hint` value, use that as the
primary domain signal. Otherwise, infer the domain from project context
(CLAUDE.md, README, config files).

If neither `domain_hint` nor project context provides a clear signal,
default to "general technical".

## Step 4: Read the Meta-Template

Read `templates/sme.md` from the framework:
- If running in a downstream project with `.ai-lindale/`, read `.ai-lindale/templates/sme.md`
- If running in the framework repo itself, read `templates/sme.md`

## Step 5: Generate Agent File

Generate a concrete agent file at `.claude/agents/<name>.md` by replacing all
`{{PLACEHOLDERS}}` in the template:

- `{{AGENT_NAME}}`: a short, domain-fitting slug (e.g., `astrologer`, `compliance-officer`, `clinician`, `sme`)
- `{{DISPLAY_NAME}}`: human-readable role name (e.g., `Astrologer`, `Compliance Officer`, `SME`)
- `{{DOMAIN}}`: the detected domain (e.g., `astrology`, `fintech`, `healthcare`)
- `{{DOMAIN_DESCRIPTION}}`: 1-2 sentences of domain-specific framing
- `{{DOMAIN_CRITERIA}}`: bullet list of domain-specific review criteria

Note: `CLAUDE_AGENT_ROLE` in the hook command is always `sme` (hardcoded in the
template). This is the permission class, not the identity. Do not change it.

## Step 6: Generate Command File

Generate a matching command file at `.claude/commands/<name>.md`:

```
/clear

Activate the **<name>** agent. Review CLAUDE.md and memory/* files, then await further instructions.

$ARGUMENTS
```

## Step 7: Report

Report to the user:
"Generated domain SME: **<display_name>** (`/<name>`). This agent is project-owned and can be customized."

The generated SME is project-owned — committed to the repo, never overwritten
by framework updates.

## Note: TPM Dispatch (DX-036)

No further step is needed to make the new SME dispatchable. The framework
TPM's `tools:` frontmatter declares a bare `Agent` (unrestricted), so any
agent defined in `.claude/agents/` — including the one you just generated —
is immediately callable via the TPM's `Agent` tool. If a downstream project
has claimed a local override of `tpm.md` that re-narrows `Agent` to an
explicit list, that override must be kept in sync by hand whenever a new
agent is added.
