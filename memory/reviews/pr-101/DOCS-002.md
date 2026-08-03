# Review: DOCS-002 — ACKNOWLEDGMENTS file for upstream sources

- **Ticket:** DOCS-002
- **Issue:** #73
- **Reviewer:** Claude Reviewer (fable)
- **Date:** 2026-07-06
- **Commit under review:** `13346f4` — docs(DOCS-002): add ACKNOWLEDGMENTS for upstream sources (#73) (sole commit touching `ACKNOWLEDGMENTS.md` on `orchestrate/2026-07-06`; no later modifications)
- **Verdict:** APPROVE-WITH-NITS

## Acceptance criteria

Issue #73 body (retrieved via `gh api`; no comments on the issue) is prose, not a checklist. ACs derived from it:

| # | Acceptance criterion | Status | Evidence |
|---|---|---|---|
| 1 | File tracks upstream projects that inspired or were vendored into Lindalë | Satisfied | `ACKNOWLEDGMENTS.md` has three sections: "Vendored / integrated" (moat), "Prototyped in / origin" (aistrologer), "Harvested patterns" (catalyst-build, juno) |
| 2 | First entry is majorcontext/moat (MIT) | Satisfied | moat is the first and only "Vendored / integrated" entry; MIT stated in the heading; upstream license confirmed MIT via GitHub API |
| 3 | Serves as attribution | Satisfied | Names all four upstream sources with what each contributed; commit message and CLAUDE.md line 161 wire it in as "upstream attribution" |
| 4 | Serves as a link trail for learners | Satisfied | Links to moat repo, aistrologer repo, wiki Architecture Overview, `memory/decisions.md`, `memory/patterns.md`, `docs/adoption-guide.md` (all resolve; see nits N2/N3 on link style) |
| 5 | Serves as a vendoring manifest showing what was lifted and from which commit | Satisfied | Pinned commit `616f1b3` + full pseudo-version recorded; planned M3 subset boundary enumerated; correctly states nothing is vendored *yet* ("was (or will be) vendored", "pinned installed binary, not vendored source") |

## Findings by severity

### Blockers
None.

### Major
None.

### Minor

- **M1 — MIT claim rests on a repo with no LICENSE file.** `ACKNOWLEDGMENTS.md:49` states "Lindalë is MIT licensed." The only in-repo source for this is `README.md:129-131` ("## License / MIT"); `git ls-files | grep -i licen` finds no LICENSE file. The claim traces to a repo source, so it is not a fabrication, but an attribution/licensing document asserting MIT while the repo lacks an actual license text is the exact place this gap bites — MIT requires the license text to accompany the software. Pre-existing repo gap, not introduced by this ticket; recommend a follow-up ticket to add `LICENSE` rather than blocking DOCS-002.

### Nits

- **N1 — "credited inline ... at each pattern's 'Origin' note" is imprecise** (`ACKNOWLEDGMENTS.md:44-45`). Some harvested patterns carry per-pattern `**Origin:**` notes (`memory/patterns.md:52,70,155`), but the juno conventions (`patterns.md:202`) and the catalyst-build git/GitHub lore (`patterns.md:184`) are credited via section headings ("harvested from juno/catalyst-build"), not Origin notes. Substance of the credit claim holds; the mechanism described is only partly accurate.
- **N2 — relative wiki link in a public-facing doc** (`ACKNOWLEDGMENTS.md:14`). `../../wiki/Architecture-Overview` resolves only from GitHub blob view. It matches the CLAUDE.md convention, but README — the repo's other public-facing document, which ACKNOWLEDGMENTS resembles in audience — uses absolute wiki URLs (`README.md:117`). Absolute would be more robust for learners arriving from forks, raw view, or local clones.
- **N3 — EPIC-004 cited without issue number** (`ACKNOWLEDGMENTS.md:14`). CLAUDE.md and the commit message write "EPIC-004 (#69)"; the file drops the "#69", slightly weakening the stated "link trail for learners" purpose.

## Factual accuracy — claim-by-claim trace

| Claim in file | Source | Result |
|---|---|---|
| Pinned to commit `616f1b3` | `memory/decisions.md:52` | Match |
| Pseudo-version `v0.5.1-0.20260421175536-616f1b3464b2` | `memory/decisions.md:52`; upstream commit `616f1b3464b2` dated `2026-04-21T17:55:36Z` (GitHub API) — timestamp component matches exactly | Match, verified upstream |
| Verified in FEAT-008 spike on xo-brain | `memory/decisions.md:54` | Match |
| Features not in tagged v0.5.0 (RUNTIME column, multi-runtime metadata) | `memory/decisions.md:54-55` | Match |
| Vendoring deferred to M3; ~17k LOC production + ~5k gatekeeper | `memory/decisions.md:60-65` ("Vendor moat — deferred to M3") | Match |
| Subset boundary `internal/{run,container,daemon,config,credential,storage,routing,netrules}` + `providers/{claude,configprovider,github}` + gatekeeper proxy | `memory/decisions.md:70-72` | Match, list identical |
| MIT-to-MIT license compatible | `memory/decisions.md:68`; moat license = MIT per GitHub API | Match |
| moat is MIT | GitHub API `repos/majorcontext/moat` → `"license":"MIT"` | Verified |
| Extracted from aistrologer; roles/lifecycle prototyped there | `CLAUDE.md` "Current Status"; repo `grinnellian/aistrologer` exists (GitHub API) | Match |
| catalyst-build: autodev dispatch, worktree footguns, git/GitHub lore | `memory/patterns.md:52,155,184` and worktree sections | Match |
| juno: settings split, tombstone-override | `memory/patterns.md:204-215` | Match |
| "Where upstream code is vendored, its original license ... will be preserved" | Correct MIT obligation; consistent with nothing being vendored yet | Correct |

INFRA-012 rename check: `grep dev-in ACKNOWLEDGMENTS.md` — zero hits. The file never mentions container image names, so the dev-in → pod / ai-lindale-pod-base rename left no stale references here.

CLAUDE.md link check: `CLAUDE.md:161` `[ACKNOWLEDGMENTS](ACKNOWLEDGMENTS.md)` — target exists at repo root; resolves.

## Tone match

Consistent with repo voice: teaching-artifact framing ("link trail for learners"), en-dash asides, forward-pointing cross-references to memory files and wiki, honest about present vs. planned state ("Today (M1/M2)" vs "M3 (planned)"). No drift.

## Verified by running vs. by reading

**By running (commands executed):**
- `gh api repos/grinnellian/ai-lindale/issues/73 --jq .body` and `/comments` — AC source; issue has no comments
- `git log --oneline`, `git show 13346f4 --stat`, `git log --follow -- ACKNOWLEDGMENTS.md` — located the implementation; confirmed single-commit history, no later edits
- `gh api repos/majorcontext/moat` — license is MIT; `gh api .../commits/616f1b3464b2` — pinned commit exists, committer date matches the pseudo-version timestamp digit-for-digit
- `gh api repos/grinnellian/aistrologer` — origin repo exists
- `git ls-files | grep -i licen` — confirmed no LICENSE file (finding M1)
- `ls docs/adoption-guide.md`, grep for `ACKNOWLEDGMENTS` in CLAUDE.md, grep for `dev-in` in ACKNOWLEDGMENTS.md — link targets and rename check

**By reading (no runtime surface):**
- Claim-by-claim comparison of ACKNOWLEDGMENTS.md against `memory/decisions.md` (pin, pseudo-version, LOC estimates, subset boundary, MIT-to-MIT) and `memory/patterns.md` (harvested-pattern credits)
- Tone comparison against CLAUDE.md and README.md
- GitHub relative-link resolution semantics for `../../wiki/...` from a root-level blob (matches existing CLAUDE.md convention; not exercised in a browser)

## Verdict rationale

Every acceptance criterion is satisfied, every factual claim traces to an in-repo source, and the two externally checkable facts (moat's license, the pinned commit and its timestamp) verify against upstream. The findings are one pre-existing repo gap surfaced by this file (missing LICENSE) and three wording/link-style nits. Nothing warrants changes to this diff before merge, but nits count: **APPROVE-WITH-NITS**.
