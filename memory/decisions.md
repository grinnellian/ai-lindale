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
