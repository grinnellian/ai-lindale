# Wickerman-OS Audit Findings (2026-03-22)

## Context

TPM audited `grinnellian/wickerman-os` to identify lindale roadmap items.
The upstream author (Tabulanis) is the user's friend with no formal dev training.
The user is converging from both ends: making lindale ready for brownfield adoption
while making wickerman-os ready to receive it ("chunnel" approach).

## Key Decisions from Discussion

### Reviewers are SME instantiations
Security reviewer, code-quality reviewer, tech-writer, etc. are all SME types,
not new core roles. The SME template (DX-004) should support adversarial/reviewer
personality types whose job is to find problems.

### Pluggable workloop is the big architectural idea
The current TPM → Architect → Dev loop should be configurable with insertion
points for quality gates. Gates are friction generators by design (honest
antagonism). This became EPIC-002.

### Greenfield vs brownfield adoption
Lindale has implicitly targeted greenfield. Wickerman-os is the brownfield test
case. Different entry points:
- Greenfield: bootstrap interview → generate agents → go
- Brownfield: audit existing → standardization plan → incrementally introduce agents

### Bootstrap interview should be light-touch
Determine user background lightly, but don't over-prescribe starting material.
Less is more for context engineering.

### DX-023 hook should be PreToolUse not PostToolUse
User carried lindale patterns to wickerman-os; PostToolUse wasn't working.
PreToolUse with context injection is the working pattern.

### DevContainer solves sandboxing blocker
The wickerman-os devcontainer with tinyproxy domain filtering may solve
lindale's DX-022 sandboxing pain point. User is excited about this.

## Issues to Create (blocked by GH token permissions)

1. **EPIC-002**: Pluggable Workloop with Quality Gates and Adversarial SMEs
2. **INFRA-002**: DevContainer Template with Network Sandboxing
3. **DX-024**: Subagent Permission Inheritance for Research Tasks
4. **FEAT-002**: Cross-Repo Audit Command (`/audit-repo <owner/repo>`)
5. **DX-025**: Standardization Playbook Template (tag for user eval)

## Issues to Update

- **DX-004**: Note that adversarial/reviewer SMEs are a key use case
- **DX-019**: Bootstrap interview should produce standardization plans for brownfield
- **DX-023**: Reference wickerman-os PreToolUse implementation; PostToolUse doesn't work
