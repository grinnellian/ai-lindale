# Decisions

## DX-018: In-repo memory replaces auto-memory

**Decision:** All agent memory lives in `memory/` within the repo, not in `~/.claude/projects/`.

**Rationale:**
- Prevents data exfiltration outside the working directory
- Version controlled and visible in code review
- Reduces permission prompts for out-of-tree writes
- Downstream projects inherit the pattern — their memory stays in their repo

**Convention:**
- `MEMORY_INDEX.md` — index of all topic files (keep concise)
- Small topic files by subject (e.g., `decisions.md`, `patterns.md`)
- Agents use `Read`/`Write`/`Edit` on `memory/` files directly
- `memory: project` frontmatter removed from all agent defs (writes to `.claude/agent-memory/`, competing location)

## Commit and push policy

**Decision (original):** Agents should commit and push liberally on main.

**Rationale:** So long as agents never force-push and stay in the working directory, the blast radius is minimal. Frequent commits reduce waste and keep work visible. No human approval needed for commit/push.

**Amended 2026-07-07 (DX-027 review, MIN1):** the "on main" clause is stale.
Ticket work now flows through issue branches and PRs with review gates: dev
MUST NOT push to `main` (`.claude/agents/dev.md` Constraints), and TPM
direct-commits only small doc/memory changes. Read the policy as **commit and
push liberally on whatever branch you are legitimately on** — the liberality
(no human approval per commit, no force-push, stay in the working directory)
still holds; the branch target does not. This is the convention `tpm.md`'s
Commit Cadence section points at.

## Greenfield vs brownfield adoption

**Decision:** Lindale must support both adoption paths. They have different entry points.

**Greenfield:** Bootstrap interview → generate agents → go.
**Brownfield:** Audit existing project → generate standardization plan → incrementally introduce agents.

**Context:** Wickerman-os is the brownfield test case. The user is converging from both ends — making lindale ready for brownfield while making wickerman-os ready to receive it. Greenfield has been the implicit target so far; brownfield requires audit tooling (FEAT-002), standardization playbooks (DX-025), and lighter-touch bootstrapping.

**Principle:** Less is more for context engineering. Don't over-prescribe starting material.
         
  
  ## Container-as-trust-boundary (EPIC-004 pivot)                                                                       
                                                                                                                      
  **Decision:** Replace hook-based enforcement with container isolation. The container IS the security boundary.

  **Rationale:**
  - PreToolUse hooks are fundamentally incompatible with Claude Code's absolute-path tool interface (BUG-004)
  - Hooks can't prevent determined escape (heredocs, backtick subshells — acknowledged in bash-allowlist.sh header)     
  - Container boundary provides hard isolation without fighting the tool interface
  - moat provides credential injection via TLS-intercepting proxy — agents never see raw tokens                         
                                                                                                                      
  **Implication:** Hooks become optional "roleplay rules" for bare-metal sessions, not a security layer. DX-033 removes 
  them from agent frontmatter for dev-in sessions (renamed to pod-base, INFRA-012).                                                                    
                                                                                                                        
  ## Moat version pin                                                                                                 

  **Decision:** Pin moat to commit `616f1b3` (pseudo-version `v0.5.1-0.20260421175536-616f1b3464b2`).

  **Rationale:** This is the exact commit verified in the FEAT-008 spike on xo-brain. It includes features not in the   
  tagged v0.5.0 release (RUNTIME column in `moat list`, multi-runtime metadata). Reproducible like a tag, known-good on
  our hardware.                                                                                                         
                                                                                                                      
  **Action:** Use `go install github.com/majorcontext/moat/cmd/moat@616f1b3` in setup scripts, not `@latest`.           
  
  ## Vendor moat — deferred to M3                                                                                       
                                                                                                                      
  **Decision:** Use moat as-is (installed binary) for M1/M2. Vendor the source subset into lindale at M3.               
  
  **Rationale:**                                                                                                        
  - Vendoring subset is ~17k LOC production + ~5k gatekeeper — non-trivial to lift now                                
  - Binary install is sufficient for Phase 0/1 (manually-run `moat run`)
  - Vendoring becomes worthwhile when k10s needs programmatic control (M3)                                              
  - MIT-to-MIT license compatible; no legal friction
                                                                                                                        
  **Subset boundary (when we do vendor):**                                                                            
  - Must-have: `internal/{run, container, daemon, config, credential, storage, routing, netrules}` + `providers/{claude,
   configprovider, github}` + gatekeeper proxy                                                                          
  - Skip: CLI chrome, TUI, non-target providers (aws, codex, gemini, meta, npm), doctor, quickstart
  - Friction: AWS provider hardcoded in `internal/run` (requires surgery); Cobra subcommand registration in `root.go`   
                                                                                                                      
  ## Token accounting owned by k10s, not moat                                                                           
                                                                                                                      
  **Decision:** k10s handles token budget tracking directly, not via `moat trace`.                                      
  
  **Rationale:** moat's gatekeeper head-truncates response bodies at 8KB. Anthropic `usage` blocks appear at the end of 
  responses (non-streaming) or in final `message_delta` events (streaming) — both beyond the 8KB capture window. moat 
  trace is supplementary evidence, not authoritative accounting.                                                        
                                                                                                                      
  ## TPM uses temp files for multi-line GitHub issue bodies

  **Decision:** TPM writes issue/PR bodies to `/tmp/*.md` via `printf` with `\n` escapes, then uses `gh issue create    
  --body-file /tmp/*.md`.
                                                                                                                        
  **Rationale:** The bash-allowlist hook's `extract_commands` function splits on `|`, `&&`, `||`, `;`, and newlines —   
  treating markdown table pipes as shell pipes and body text as separate commands. `--body-file` sidesteps the parser
  entirely. This is the canonical pattern until hooks are removed (DX-033).                                             
                                                                                                                      
  ## k10s belongs in a separate repo

  **Decision:** k10s (kubernagents) and Cortex will live in their own repo, not in ai-lindale.                          
  
  **Rationale:** k10s is an orchestrator that calls `moat run` — it's infrastructure for xo-brain, not part of the      
  reusable agent framework. Lindale defines roles and workflows; k10s deploys them. Separation keeps lindale portable 
  for downstream adopters who don't need k10s.                                                                          
                                                                                                                      
  **Tracked in:** EPIC-005 (#70)

  That's all the state worth persisting. Everything else is tracked in issues or on the wiki. Once DX-033 lands, this   
  file can be written directly — and the TPM temp-file decision becomes historical footnote.
## Moat CA: mount at runtime, never bake (INFRA-011, 2026-07-06)

Moat generates a per-host CA for its TLS-intercepting proxy. Baking a CA into
the published dev-in image (renamed to pod-base, INFRA-012) is impossible
without sharing a private key across hosts (anti-pattern). Decision: the image
entrypoint trusts whatever is mounted at /run/moat/moat-ca.crt (override via
MOAT_CA_CERT) and is a silent no-op without it — the same image serves
moat-wrapped and Phase-0-style GH_TOKEN bootstrap runs. Smoke test verifies
the mechanism with a throwaway CA.

## dev-in image ships without VS Code (INFRA-011, 2026-07-06; renamed to pod-base, INFRA-012)

L2 interaction decision is Claude Code Remote Control as primary UI; baking
VS Code (as the Phase 0 bootstrap container did) would multiply image size
for a UI path we don't use. Image is 0.22GB vs multi-GB bootstrap. VS Code
can be sudo-installed interactively if a session needs it.

## TPM's Agent tool is unrestricted, not an allowlist (DX-036, 2026-07-06)

**Decision:** `.claude/agents/tpm.md` declares `Agent` (bare, unrestricted) instead of
`Agent(architect, dev)` (a closed allowlist of the two framework-default subagent
types).

**Rationale:** The parenthesized form silently blocked TPM from dispatching any
project-owned agent — including SMEs the TPM itself generates via
`templates/sme-bootstrap.md`. `juno_automation_alpha` hit this live and forked
`tpm.md` entirely to hand-enumerate its 7-persona roster, losing framework updates
to that file. Verified that `dev.md` and `architect.md` already use the bare
`Agent` form for the same tool — the allowlist on `tpm.md` was an inconsistency,
not an intentional restriction. Per the container-as-boundary model (EPIC-004),
frontmatter tool lists are behavioral capability declarations, not enforcement, so
widening TPM's declared `Agent` access doesn't weaken the actual security boundary.

**Downstream implication:** projects that previously claimed a local override of
`tpm.md` solely to expand the `Agent()` allowlist (e.g. `juno_automation_alpha`)
can drop that override and resync to the framework symlink — see
`docs/adoption-guide.md` and `templates/sme-bootstrap.md` Step 8.

## Issue description is the authoritative spec (DX-028, 2026-07-06)

**Decision:** A ticket's GitHub issue *description* is the current, authoritative
spec. The comment thread is a discussion record, not a second source of truth —
an agent executing a ticket reads the description, not the thread.

**Rationale:** When agents debate scope in comments without folding the outcome
back into the description, a fresh LLM instance picking up the ticket has to
reconstruct intent from chronological thread archaeology ("comment 3 says X but
comment 5 overrides it in some cases..."). That's fragile, expensive, and
error-prone compared to reading one current spec.

**Who integrates:** TPM, as an extension of its existing exclusive issue-management
authority. Other agents (architect, dev) don't edit descriptions themselves —
when a comment changes scope or design, they flag it explicitly in the comment,
and TPM folds it into the description at the next state-machine checkpoint where
it reads that ticket's comments (arch review completion, ready-for-review,
escalation resume).

**No changelog needed:** GitHub's native edit history is the audit trail for
description changes — no "Update N" changelog note inside the body itself.
Comments stay the discussion record; the description states current truth.

**Where wired:** `.claude/agents/tpm.md` (Issue Description as Authoritative Spec
section, under Exclusive Authority: Issue Management) and `.claude/commands/autodev.md`
(Rules section — fold decisions into the description before advancing a ticket
past a checkpoint).

## Hard floor verified: moat + dev-in on xo-brain (EPIC-004 M1, 2026-07-06; dev-in renamed to pod-base, INFRA-012)

First end-to-end run of the dev-in image under moat (`moat run` with claude +
github grants, docker runtime). Verified: **real credentials never enter the
container** — the env carries placeholder values (`ghp_moatProxyInjectedPlaceholder…`,
`moat-proxy-injected`) that moat's TLS proxy swaps for real tokens at the
network layer; `gh api user` succeeds from inside with no real token present.

**Integration contract discovered:** moat's `base_image` must be a ROOT-user
image — moat apt-installs its baseline layer (ca-certificates, gosu, xvfb…)
with no `USER root` escape, and dev-in ends with `USER dev`. Interim: a local
root shim (`FROM dev-in` + `USER root`, tagged `ai-lindale-dev-in:moat-base`)
documented in moat.yaml. Long-term options: dev-in ships a `:root` build stage,
or upstream moat learns to elevate for its build layer. (Both options are now
tracked as INFRA-015, #98.)

**Follow-ups (ticketed 2026-07-06, cross-refs appended 2026-07-07 per the
EPIC-004 M1 review MIN-4 — the descriptions below are the original record):**
- `git` over the moat proxy fails with CONNECT 407 (proxy auth) while `gh`
  works — blocks the L5 clone-inside-container story; needs a git credential
  helper or proxy config in the moat github grant path. → INFRA-013 (#96).
- Network policy is permissive by default; the L3 strict allowlist
  (`network.policy: strict` + rules) still needs to be configured and tested.
  → INFRA-014 (#97).
- `moat.yaml` uses `dependencies: []` but moat still installs its own baseline
  apt layer + gh 2.40.0 (older than dev-in's) — harmless duplication, worth an
  upstream issue. → **Parked, no owning ticket yet** (EPIC-004 M1 review
  MIN-3): the upstream issue against majorcontext/moat has not been filed and
  the only other breadcrumb is a nit-list comment on the now-closed #95. Next
  TPM pass should either file the upstream issue or open a small INFRA ticket
  to carry it.
- GHCR package visibility (the root-shim FROM pulls a private `:edge` tag) —
  tracked as INFRA-016 (#100, needs-human).

## Pod naming decision (INFRA-012, 2026-07-06)

**Decision:** Rename the "dev-in" concept and image to **pod** /
`ghcr.io/grinnellian/ai-lindale-pod-base`. A pod is the sealed,
self-sufficient container an agent lives and works in — the L4 foundation of
container-as-boundary.

**Rationale:** "pod" gives enclosure + self-sufficiency in one word, and
aligns with the k10s roadmap vocabulary (machines as nodes, agents as pods,
GitHub as the control plane) — see EPIC-005 (#70) — so M3 inherits a
coherent naming story instead of reconciling two vocabularies later.
"dev-in" also risked mindshare collision with Devin/Windsurf-style product
names.

**Rejected:** "devcon" — collides with the `devcontainer.json` ecosystem and
invites false compatibility assumptions (see docs/faq.md for why a pod is
explicitly not a devcontainer), and reads too close to DEF CON.

**Parked, not rejected:** "cell" / "workcell" — a lean-manufacturing framing
(a workcell is a self-contained unit of production) that trades the
enclosure/security framing for a beehive-adjacent art direction rather than
a prison-adjacent one. Worth revisiting as a future branding/visual-identity
option if "pod" ever needs a friendlier public-facing gloss, but not adopted
now — "pod" better matches the k10s vocabulary already in use.

## Commit-cadence enforcement mechanism (DX-027, 2026-07-07)

**Decision:** Commit-early-and-often is enforced at two layers only —
prompt-level cadence rules (`dev.md`'s TDD red/green contract, `tpm.md`'s
Commit Cadence, with architect exempt) and the autodev review gate that
rejects a monolithic commit for a multi-phase ticket. No hook and no
commits-per-session metric.

**Rationale:** issue #40 listed four *possible* mechanisms, not four
requirements. Option 2 (PostToolUse hook) is architecturally moot — hook
enforcement was retired in the EPIC-004 container-as-boundary pivot. Option 4
(commits-per-session health metric) is deliberately dropped, not deferred:
its only prospective consumer is AFK orchestration (FEAT-003), which is still
open, and a metric with no consumer is noise. Recorded here because the
renouncement previously lived only in a commit message and the PR #101 body
(DX-027 review, MIN1).

**Exception wired in:** when BUG-006's stage-and-return fallback genuinely
applies, the red/green split collapses into one TPM-made commit; the gate
must not bounce that. See `dev.md`'s BUG-006 fallback exception and the
matching carve-out in `autodev.md`'s review-bar rule.

## maxTurns tiers and the AC3 waiver (DX-029, 2026-07-07)

**Decision:** every agent definition and agent-generating template carries a
`maxTurns` ceiling: audit-repo 30, `templates/sme.md` 30, researcher 40,
architect 50, tpm 100, dev 200.

**Rationale:** the ordering is read-only-analysis < planning < orchestration <
implementation. Read-heavy roles that neither dispatch nor write need the
fewest turns; researcher sits above audit-repo because WebSearch/WebFetch
round-trips cost turns; architect plans but does not implement; TPM
orchestrates many dispatches; dev does the most tool-work per task. The values
are uncalibrated first guesses — issue #47 says to calibrate from experience,
so update them *here* when experience says otherwise rather than only in the
frontmatter.

**AC3 waived, not deferred:** the ticket asked for graceful exit with a
summary at the cap. Claude Code documents `maxTurns` as "the maximum number of
agentic turns before the subagent stops" — a hard stop, with no pre-cutoff
hook that would let an agent emit what it accomplished. Nothing at the prompt
or frontmatter layer can supply that, so the AC is unsatisfiable rather than
unfinished. See `memory/patterns.md` §"maxTurns is a hard stop, not a graceful
exit" for the operational note.

**Not verified:** whether `maxTurns` caps a main interactive session launched
with `--agent` (the docs address subagents only), and whether an
`Agent()`-spawned subagent is actually cut off at its role's cap — asserted
from the docs, never observed. `test-researcher-fixtures.sh` asserts only that
`maxTurns:` is present, not its value, so the tiers above are not test-pinned.
