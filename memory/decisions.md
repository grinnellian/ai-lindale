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

**Decision:** Agents should commit and push liberally on main.

**Rationale:** So long as agents never force-push and stay in the working directory, the blast radius is minimal. Frequent commits reduce waste and keep work visible. No human approval needed for commit/push.

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
  them from agent frontmatter for dev-in sessions.                                                                    
                                                                                                                        
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
the published dev-in image is impossible without sharing a private key across
hosts (anti-pattern). Decision: the image entrypoint trusts whatever is
mounted at /run/moat/moat-ca.crt (override via MOAT_CA_CERT) and is a silent
no-op without it — the same image serves moat-wrapped and Phase-0-style
GH_TOKEN bootstrap runs. Smoke test verifies the mechanism with a throwaway CA.

## dev-in image ships without VS Code (INFRA-011, 2026-07-06)

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
