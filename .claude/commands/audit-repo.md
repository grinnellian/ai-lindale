Structured cross-repo audit for brownfield/dependency/reference analysis.

## Startup

You should be invoked via `claude --agent audit-repo` for the correct
read-only tool scope. If not, warn the user on first message.

`$ARGUMENTS` must be a single `owner/repo` string (e.g. `grinnellian/wickerman-os`).
If `$ARGUMENTS` is missing, empty, or does not match the `owner/repo` shape
(exactly one `/`, no scheme, no trailing path), stop and ask the user to
re-invoke with a valid `owner/repo` argument. Do not guess at a repo name.

Verify access before doing anything else:

```
gh api repos/<owner>/<repo>
```

- On `404`: stop and report the repo does not exist or is not visible to the
  authenticated `gh` account. Do not retry with guessed name variants.
- On `403`: stop and report an access/rate-limit problem. Do not blind-retry
  the same call — per the insanity-loop rule (CLAUDE.md), a repeated
  identical failure means change approach or escalate, not retry silently.
- On success, proceed to Phase 1 using the response already fetched (no
  need to re-fetch the same endpoint in Phase 1).

**Constraint: this command is API-based read only. Do NOT clone the
repository locally at any point** — all analysis happens through `gh api`
and `gh` CLI calls against GitHub's REST API.

## Phase 1 — Structure survey

1. Repo metadata (reuse the Startup call if already fetched):
   `gh api repos/<owner>/<repo>` — capture primary language, size, license,
   and whether the repo is `archived` or a `fork` (a fork changes how
   attribution in Phase 2 should be read — forked history includes upstream
   commits that predate this repo's own contributions).
2. File tree:
   `gh api repos/<owner>/<repo>/git/trees/<default_branch>?recursive=1`
   — `<default_branch>` comes from the metadata call's `default_branch`
   field. **If the response's `truncated` field is `true`, say so explicitly
   in the report** — the tree is incomplete and any structure claims based
   on it are a lower bound, not a complete inventory.
3. From the tree, identify toolchain signals: test directories/files
   (`test/`, `tests/`, `spec/`, `*_test.*`, `*.test.*`), CI config
   (`.github/workflows/`, `.circleci/`, etc.), lint/format config
   (`.eslintrc*`, `.flake8`, `ruff.toml`, etc.), and `Dockerfile` /
   container build files.

## Phase 2 — Attribution and state history

**Hard requirement:** distinguish the repo's *initial* commit(s) from its
*current* state. The wickerman-os dry run (see issue #35 origin) showed that
naive commit reads misattribute the entire codebase to the repo owner just
because they made the first commit — a scaffold or import commit is not the
same as ongoing authorship.

1. `gh api repos/<owner>/<repo>/commits?per_page=100` (paginate as needed)
   to build an author timeline. Note total commit count, unique authors,
   and the date range.
2. Explicitly identify the initial commit(s) — the earliest commit(s) in the
   history — and note whether they look like a bulk import/scaffold (large
   diff, single commit, generic message) versus organic first work. Compare
   against the rest of the timeline: is authorship concentrated at the start
   and then abandoned, or distributed across the project's life?
3. For architecturally significant files identified in Phase 1 (entry
   points, core config, anything Phase 3 will read in depth), pull per-file
   commit history:
   `gh api repos/<owner>/<repo>/commits?path=<file>&per_page=30`
   — this shows whether a given file reflects current maintainer intent or
   is stale/inherited.

## Phase 3 — Content read and pattern extraction

**Constraint: API-based read only, NO local clone.** Use the contents API
for a bounded set of key files (the toolchain/config files from Phase 1, the
architecturally significant files from Phase 2, and the README):

```
gh api repos/<owner>/<repo>/contents/<path>
```

Decode the `content` field (base64) to read the file. Do not attempt to
enumerate or read every file in the tree — stay bounded to what Phase 1/2
flagged as significant.

For each finding, classify it as one of:
- **Reusable pattern** — something worth carrying into Lindalë or another
  project, with a one-line rationale for why it transfers.
- **Red herring** — something that looks interesting but doesn't generalize
  (project-specific hack, dead code, cargo-culted boilerplate), with a
  one-line rationale for why it doesn't transfer.

## Phase 4 — Verdict and report

Produce the audit report as structured markdown in this command's **final
message** — do not write it to a file yourself (this agent is read-only by
design; the caller/dispatching agent is responsible for persisting the
report to `memory/audit-<owner>-<repo>-<date>.md`).

Report sections, in order:

1. **Structure summary** — language, size, license, archived/fork status,
   toolchain signals, and any tree-truncation caveat from Phase 1.
2. **Attribution timeline** — author/commit summary from Phase 2, with the
   initial-commit-vs-current-state distinction called out explicitly.
3. **Reusable patterns** — bulleted list, each with a one-line rationale.
4. **Red herrings** — bulleted list, each with a one-line rationale.
5. **Verdict** — exactly one of `adopt-as-is`, `reference-only-rewrite`, or
   `not-relevant`, with a one-paragraph justification synthesizing Phases
   1-3.
6. **Recommended benefit-flow direction** — does value flow from this repo
   into the auditing project, the reverse, both, or neither, and why.

## Out of scope

The following are explicitly deferred and must NOT be attempted by this
command:
- Security surface scan (auth, CORS, input validation, secrets detection).
- CI/lint quality scoring (pass/fail grading of pipeline or lint config
  quality).
- Recommended lindale adoption path (greenfield vs brownfield) — depends on
  the bootstrap interview work in DX-019 and is out of scope until that
  lands.

$ARGUMENTS
