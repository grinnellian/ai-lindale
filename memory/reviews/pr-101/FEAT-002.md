# Review: FEAT-002 — /audit-repo cross-repo audit command

- **Ticket:** FEAT-002 (issue #35: Cross-Repo Audit Command)
- **Reviewer:** Claude Reviewer (fable)
- **Date:** 2026-07-06
- **Branch:** orchestrate/2026-07-06
- **Commits reviewed:** `ea938a1` (red: fixture tests), `1b65549` (green: command + agent), plus later touches `719a9b1` (DX-029 maxTurns) and `1bee20c` (DX-014 skills section)
- **Files:** `.claude/commands/audit-repo.md`, `.claude/agents/audit-repo.md`, `scripts/tests/test-audit-repo-fixtures.sh`
- **Verdict:** APPROVE-WITH-NITS

## Acceptance criteria

Issue #35 lists five "suggested output" items; the architect plan deliberately deferred
three of them (security-surface scan, CI/lint scoring, adoption-path recommendation)
and required the deferrals be explicit. The plan also imposed hard requirements from
the wickerman-os dry run (issue #35 comment, 2026-03-22).

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | `/audit-repo <owner/repo>` command exists, invocable with scoped read-only access | Satisfied | `.claude/commands/audit-repo.md` (4-phase procedure); `.claude/agents/audit-repo.md` scoped to Bash/Read/Grep/Glob |
| 2 | `$ARGUMENTS` validated as `owner/repo`; no guessing on bad input | Satisfied | Command Startup section: exactly one `/`, no scheme, no trailing path; stop-and-ask on mismatch; 404/403 stop-and-report with insanity-loop citation |
| 3 | Repository structure summary | Satisfied | Phase 1: metadata, recursive tree with explicit `truncated` caveat requirement, toolchain signals; report section 1 |
| 4 | Code quality assessment | Satisfied at signal level | Phase 1 detects tests/CI/lint/container configs; pass/fail *scoring* explicitly deferred in Out of scope (per plan). Type-coverage signal missing — see Nit-3 |
| 5 | Security surface scan | Satisfied (as explicit deferral) | Out of scope item 1, "must NOT be attempted" |
| 6 | Identified gaps (what the project needs) | **Partially satisfied** | Neither a report section nor an explicit deferral — see Minor-1 |
| 7 | Recommended lindale adoption path | Satisfied (as explicit deferral) | Out of scope item 3, correctly tied to DX-019 dependency |
| 8 | Plan hard req: attribution + initial-commit-vs-current-state distinction | Satisfied | Phase 2 marked "Hard requirement", cites the wickerman misattribution failure mode; fork caveat in Phase 1.1; per-file `commits?path=` history; report section 2 calls the distinction out explicitly |
| 9 | Plan hard req: API-only, no local clone, at any phase | Satisfied | Stated three times: command Startup constraint, Phase 3 constraint, agent Constraints ("Never clone the target repository locally") |
| 10 | Plan hard req: read-only agent; report persisted by CALLER, not agent | Satisfied | Phase 4: report in final message, "do not write it to a file yourself"; agent Constraints repeat it with the same `memory/audit-<owner>-<repo>-<date>.md` target — consistent across both files |
| 11 | Deferred scope explicit in the command file | Satisfied (with Minor-1 caveat) | "Out of scope" section lists exactly the three plan-named deferrals |
| 12 | Fixture tests exist and pass | Satisfied | 18/18, run by reviewer (see below) |

## Findings by severity

### Blockers
None.

### Major
None.

### Minor

**MINOR-1 — "Identified gaps" is neither delivered nor explicitly deferred.**
Issue #35's suggested output item 4 ("Identified gaps — what the project needs") does
not appear as a Phase 4 report section, and it is absent from the Out of scope list
(`grep -i gap` over both files: zero hits). The plan's own bar was that anything not
delivered must be an explicit deferral; the three named deferrals meet that bar, this
fourth item silently falls between "delivered" and "deferred." The verdict/benefit-flow
sections cover adjacent ground but are not a gaps inventory. Fix is one line in either
the report-sections list or the Out of scope list.

### Nits

**NIT-1 — Test coverage gaps around the plan's hard requirements.**
`scripts/tests/test-audit-repo-fixtures.sh` asserts the command file's "NO local clone"
phrasing (case-sensitive, matches only the Phase 3 wording, not the Startup constraint)
but has no assertion on the *agent* file's no-clone constraint, and nothing asserts the
caller-persists-report requirement (Phase 4 / agent Constraints) — one of the three
plan hard requirements. All 18 existing assertions are sound; these are additions, not
fixes.

**NIT-2 — Pagination guidance is vague against a 30-turn ceiling.**
Phase 2 says `commits?per_page=100` "(paginate as needed)" without mentioning
`gh api --paginate`. On a large repo, manual page-walking plus the mandatory
CLAUDE.md/memory pre-read (agent Context section) will pressure the DX-029
`maxTurns: 30` budget. One phrase (`--paginate`) removes the pressure.

**NIT-3 — Type-coverage signal missing from Phase 1 toolchain scan.**
Issue #35's quality item names "type coverage"; Phase 1.3 lists test, CI, lint, and
container signals but no type-checker configs (`tsconfig.json`, `mypy.ini`,
`pyrightconfig.json`, etc.). Scoring is deferred; signal detection is not, so this one
signal is a small in-scope omission.

**NIT-4 — Undocumented model choice.**
`model: claude-opus-4-7` matches architect/tpm, but the closest sibling by shape —
researcher, also a read-only Bash/Read/Grep/Glob investigator — runs
`claude-sonnet-4-6`. No rationale recorded anywhere (contrast: the DX-029 commit
records the maxTurns rationale, and the agent file itself documents the empty-skills
decision). Either choice is defensible; the divergence just isn't explained.

## Conventions and later-commit consistency

- Frontmatter carries all sibling fields (name, description, tools, model, color,
  initialPrompt, maxTurns). `skills:` absence is a documented decision in the agent
  body ("Skills (DX-014)" section explains why none of the bundled skills apply to an
  API-only, no-clone role) — this is the right way to diverge.
- Sandbox Reminder section matches the architect/tpm/researcher convention, with a
  role-appropriate rationale (unrestricted `gh api`).
- "MUST NOT sign chat responses" present; no issue-comment signing rule, appropriate
  since the role never comments on issues.
- DX-029 (`719a9b1`) added `maxTurns: 30` with recorded rationale ("read-heavy,
  low-turn analysis, same tier as SME"); DX-014 (`1bee20c`) added the skills audit
  section. Both later touches are consistent with the FEAT-002 design.
- CLAUDE.md File Structure tree (on this branch) lists both new files.
- Downstream propagation: `scripts/install.sh` globs `.claude/agents/*.md` and
  `.claude/commands/*.md` (BUG-009/BUG-008), and its comment names `audit-repo.md`
  explicitly — the new role installs downstream with no further work.

## Verified by running vs by reading

**Verified by running (chfirmed):**
- `bash scripts/tests/test-audit-repo-fixtures.sh` → **18 passed, 0 failed**, exit 0
  (matches the green-phase commit's claim exactly).
- `gh issue view 35 --comments` → ticket body + wickerman-os dry-run comment (source
  of the attribution/no-clone/caller-persists requirements).
- `git log --follow` on both files → exactly the expected history (red test commit,
  green implementation commit, DX-029, DX-014); no drive-by edits from other tickets.
- `gh issue view 103 --comments` → real-world exercise evidence: the omnigent
  deep-dive used the FEAT-002 report vocabulary end-to-end (reusable patterns with
  rationales, red herrings with rationales, verdict from the exact three-value set —
  "reference-only-rewrite" — benefit-flow direction, attribution nuance: it flagged the
  squash-export "prior private life" exactly as Phase 2 mandates). It deviated from the
  API-only rule (shallow clone to a scratchpad) **by explicit orchestrator instruction
  and with a disclosed method note** — a sanctioned, transparent exception, and
  incidental evidence the constraint is understood as a rule rather than a suggestion.
  The format held up under a much heavier load than the wickerman dry run.

**Verified by reading only:**
- The phased procedure's semantic correctness (API endpoint shapes, base64 contents
  decode, `truncated` handling, fork-attribution caveat) — not executed against a live
  target repo in this review.
- Agent tool-scoping effectiveness (frontmatter `tools:` list is prompt/harness-level
  enforcement; no runtime probe of what the agent can actually invoke).
- install.sh glob propagation of the new files (BUG-009's own test suite covers it;
  not re-run here).

## Verdict

**APPROVE-WITH-NITS.** All plan hard requirements are satisfied and traceable to the
wickerman dry-run lessons; the three mandated deferrals are explicit; tests pass as
claimed and were re-run by this reviewer; the format survived a real deep-dive (#103).
One minor (a fourth suggested-output item neither delivered nor explicitly deferred)
and four nits, none of which block merge.

-Claude Reviewer (fable)
