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
