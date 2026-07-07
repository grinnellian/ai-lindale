# Review: FEAT-011 — Adopt .claude/skills convention with installer support

- **Ticket:** FEAT-011
- **Issue:** #91
- **Reviewer:** Claude Reviewer (fable)
- **Date:** 2026-07-06
- **Commits reviewed:** `0dc367c` (red tests), `5fdcd6b` (implementation), plus current
  state on `orchestrate/2026-07-06` (install.sh subsequently touched by BUG-009 `e5b9474`
  and doc sweep `9672c16`; adoption-guide.md by DX-014/DX-025/DX-036/FEAT-013 — none of
  these altered the FEAT-011 skills block, verified by diff `5fdcd6b..HEAD`)
- **Verdict:** REQUEST-CHANGES

## AC Table

| # | Acceptance criterion (issue #91 scope) | Status | Evidence |
|---|---|---|---|
| 1 | Define `.claude/skills/` convention in adoption-guide.md ownership table (project-owned by default; framework-managed skills symlinked like agents/commands) | **Satisfied** | `docs/adoption-guide.md` lines 63–64 add two ownership-table rows (project-owned / framework-shipped); "Skills Convention (FEAT-011)" section (lines 115–140) states project-owned-by-default, `SKILL.md` frontmatter shape, template pointer, and future framework-shipped symlink behavior. Guarded by `test_guide_documents_skills`. |
| 2 | install.sh handles framework-shipped skills via generic loop (companion to BUG-008 commands glob) | **Satisfied, with a correctness defect in the refresh path** | `scripts/install.sh` lines 122–123 scaffold `.claude/skills/` alongside agents/commands; lines 148–161 glob `$FRAMEWORK_DIR/.claude/skills/*/` and route each through `link_managed` (BUG-007 skip/force logic), gated behind the self-host check and a `[ -d ]` guard. Fresh link, ok/no-op, project-owned skip, empty/absent framework skills, and idempotency all verified green. **But the "wrong symlink → refreshed" branch is broken for directory symlinks — see Major finding M1.** |
| 3 | (Optional) `templates/skill.md` skeleton showing frontmatter conventions | **Satisfied, with a usability defect** | `templates/skill.md` exists with `name`/`description` frontmatter, kebab-case convention notes, and section skeleton. Guarded by `test_skill_template_exists`. Copy-verbatim instruction produces a SKILL.md whose frontmatter Claude Code will not parse — see Minor finding m1. |
| — | Non-goal routing: generic patterns inside juno's skills (per-file subagent commit-message fan-out; gated intake → parallel design → sequential implementation) "go to memory/patterns.md instead" | **Not satisfied** | `memory/patterns.md` harvest-residue section (2026-07-06) records cortex-recall, SME archetypes, etc., but neither juno generic pattern appears anywhere in the file (grepped `gated|intake|fan-out|autocommit|mission-design`). See Minor finding m3. |

## Findings

### Blockers

None.

### Major

**M1 — `link_managed` refresh path silently fails for directory symlinks (skills) and corrupts the stale target.**
`scripts/install.sh` line 63: the refresh branch runs `ln -sf "$src" "$dest"`. When
`$dest` is a symlink pointing at an **existing directory** (the skills case — agents and
commands are file symlinks, skills are directory symlinks), both BSD and GNU `ln -sf`
dereference the destination and create the new link *inside* the pointed-to directory
instead of replacing the symlink. Reproduced end-to-end with the real install.sh: a stale
skill symlink pointing at `../../.old-framework/.claude/skills/autocommit` produced

```
  refreshed .claude/skills/autocommit (was -> ../../.old-framework/.claude/skills/autocommit)
```

with `REFRESHED` incremented — yet afterward `readlink .claude/skills/autocommit` still
returned the **old** path, and a stray `autocommit -> ../../.ai-lindale/...` symlink had
been silently deposited inside the old target directory. The installer lies (reports
refreshed), leaves the wrong link in place, and pollutes the stale target.

Reachability: dormant today (the framework ships zero skills, so no downstream has a skill
symlink), but the trigger is explicitly anticipated by install.sh's own header — the
INFRA-001 note (lines 26–28) says symlink targets will change when the `framework/`
restructure lands, which is exactly the wrong-symlink-refresh scenario. FEAT-011 is the
first ticket to route directories through `link_managed`, so the defect is introduced by
this change even though the branch predates it (BUG-007).

Fix: in the refresh branch use `ln -sfn` (`-n` is accepted by GNU ln and is the macOS/BSD
synonym for `-h`, "do not follow a destination symlink"), or `rm "$dest" && ln -s "$src" "$dest"`.
Add a skills variant of `test_wrong_symlink_refreshed` (see m2) — it would have caught this red.

### Minor

**m1 — `templates/skill.md` copy-verbatim instruction yields a SKILL.md whose frontmatter won't parse.**
Lines 1–16 are a prose header *above* the `---` frontmatter, and line 8–9 instructs "Copy
this file to that path and customize" without saying to delete the header. Claude Code
only recognizes frontmatter that starts at the top of `SKILL.md`; a verbatim copy leaves
the `name`/`description` block unparsed and the skill silently never loads. The style
mirrors `templates/sme.md`, but sme.md is consumed by TPM generation, not copied by a
human. Fix: add "delete this header block after copying" to the instructions, or move the
guidance below the frontmatter / into an HTML comment.

**m2 — Test gaps in the new skills coverage (8 tests, all green, but the risky paths are unexercised).**
Missing from `scripts/tests/test-adoption.sh`:
- wrong-symlink refresh for a skill directory (the exact M1 scenario; the suite has this
  test for agents at `test_wrong_symlink_refreshed` but not for directory symlinks);
- `--force` on a project-owned skill directory colliding with a framework skill
  (exercises the `rm -rf` of a real directory — new territory, since directories were
  previously "defensive error" per the header comment);
- absent `$FRAMEWORK/.claude/skills/` (the `[ -d ]` guard at install.sh line 153 is never
  exercised: `setup_project` unconditionally `mkdir -p`s the fixture skills dir at
  test-adoption.sh line 45, which also diverges from the real repo, which has **no**
  `.claude/skills/` directory).

**m3 — Issue non-goal routing unfulfilled.**
Issue #91's Non-goals section commits the generic patterns inside juno's skills
(per-file subagent commit-message fan-out; gated intake → parallel design → sequential
implementation) to `memory/patterns.md` "instead" of porting the skills. Neither pattern
is in `memory/patterns.md` (the 2026-07-06 harvest-residue section covers cortex-recall,
SME archetypes, and others, but not these two). The FEAT-011 commits don't claim this
either, so either land the patterns.md entries or note explicitly (issue comment /
follow-up DOCS ticket) that the routing moved elsewhere.

### Nits

**n1 — install.sh header comment now misleading.** Line 18 still documents
"Directory → error (skipped defensively)". No error branch exists — directories fall
into the same skipped/forced path as regular files, and after FEAT-011 a real directory
is the *expected* project-owned-skill override, not a defensive edge case.

**n2 — sync.sh message omits skills.** `scripts/sync.sh` line 19: "If new agents or
commands were added, re-run install.sh" — a newly framework-shipped skill also requires a
re-run; the message should say "agents, commands, or skills".

**n3 — Generated linglink README omits skills.** The `.claude/README.md` heredoc
(install.sh lines 184–198) documents agents ownership (symlinked core vs. project-owned)
but says nothing about `.claude/skills/`, the one directory whose ownership convention is
inverted (project-owned by default).

**n4 — "never touched by install.sh" overstates.** adoption-guide.md's skills section
says project skills "are ... never touched by `install.sh`". Under `--force` with a name
collision against a (future) framework-shipped skill, `link_managed` runs `rm -rf` on the
project-owned skill directory. General `--force` semantics are documented earlier in the
guide, but the absolute claim here could bite; "never touched by a default run" would be
accurate.

## Verified by running vs. by reading

**By running:**
- `bash scripts/tests/test-adoption.sh` — 57 passed, 0 failed, including all 8 FEAT-011
  skills tests (`skills: .claude/skills/ scaffolded`, `framework-shipped skill is
  symlinked`, `project-owned skill is not touched`, `no framework skills does not crash`,
  `local override of framework skill is skipped`, `idempotent on re-run`, `guide documents
  .claude/skills convention`, `templates/skill.md skeleton exists`).
- Isolated `ln -sf` probe in scratchpad confirming BSD ln dereferences a
  symlink-to-existing-directory destination (creates link inside the target instead of
  replacing).
- End-to-end M1 reproduction: fake downstream project + fake framework submodule + real
  `scripts/install.sh`, pre-seeded stale skill symlink pointing at an existing old
  framework path; observed the false "refreshed" report, unchanged stale symlink, and
  stray link inside the old target.

**By reading:**
- Issue #91 body via `gh issue view --json` (no comments on the issue).
- Commits `0dc367c` and `5fdcd6b` (full diffs) and `git diff 5fdcd6b..HEAD` over the three
  touched files to confirm the FEAT-011 blocks survived BUG-009 / DX-014 / doc-sweep
  edits intact.
- Current `scripts/install.sh`, `scripts/tests/test-adoption.sh`, `docs/adoption-guide.md`,
  `templates/skill.md`, `scripts/sync.sh`, `templates/sme.md` (template-style comparison),
  `memory/patterns.md` (non-goal routing check), `templates/CLAUDE.md` (skills line in the
  scaffolded file-structure block — present and accurate).

## Verdict rationale

The three scoped ACs are substantively delivered and the happy paths are well-tested, but
M1 is a verified correctness defect in exactly the mechanism this ticket ships — a refresh
that reports success while leaving the wrong symlink in place and writing garbage into the
stale target — with a trigger the codebase itself anticipates (INFRA-001 path
restructure). The fix is small (`ln -sfn` in the refresh branch + one directory-refresh
test), so REQUEST-CHANGES rather than a conditional approve.

-Claude Reviewer (fable)
