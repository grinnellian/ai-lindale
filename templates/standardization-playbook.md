# Standardization Playbook Template
#
# This is a meta-template used by the TPM to generate a project-specific
# standardization playbook for a brownfield project — one with substantial
# pre-existing code but gaps in testing, CI, security, or code quality
# practice. The TPM reads audit findings, populates this template, and
# writes the result to docs/standardization-playbook.md in the downstream
# project.
#
# The TPM should replace all {{PLACEHOLDERS}} when generating. Only include
# rows that are actually surfaced by the audit — do not invent boilerplate
# items to fill out a phase. An empty phase (no rows) is a valid outcome.

# Standardization Playbook: {{PROJECT_NAME}}

Generated: {{DATE}}
Audit source: {{AUDIT_SOURCE}}

## Guiding Principles

- **Preserve author intent.** This playbook proposes standardization, not a rewrite. Don't second-guess design decisions the audit didn't flag as a problem.
- **Commit early and often; each item should be independently revertable.** Land one item at a time so any single change can be reverted without unwinding the rest.
- **Less is more.** Only include items the audit actually surfaced. An empty phase is a valid, honest outcome — do not pad a phase with invented boilerplate to make it look complete.
- **Phases should be substantially complete before the next begins.** Foundation work stabilizes the ground that Tests, Security, Code Quality, and Infrastructure work depends on.

## Phase 1: Foundation

Build system, package manifest, and CI stub — the ground everything else stands on.

| Item | Priority | Depends on | Issue |
|------|----------|------------|-------|
| {{FOUNDATION_ITEM}} | {{P0_P1_P2}} | {{DEPENDS_ON}} | {{ISSUE_REF}} |

## Phase 2: Tests

| Item | Priority | Depends on | Issue |
|------|----------|------------|-------|
| {{TEST_ITEM}} | {{P0_P1_P2}} | {{DEPENDS_ON}} | {{ISSUE_REF}} |

## Phase 3: Security

| Item | Priority | Depends on | Issue |
|------|----------|------------|-------|
| {{SECURITY_ITEM}} | {{P0_P1_P2}} | {{DEPENDS_ON}} | {{ISSUE_REF}} |

## Phase 4: Code Quality

| Item | Priority | Depends on | Issue |
|------|----------|------------|-------|
| {{CODE_QUALITY_ITEM}} | {{P0_P1_P2}} | {{DEPENDS_ON}} | {{ISSUE_REF}} |

## Phase 5: Infrastructure

| Item | Priority | Depends on | Issue |
|------|----------|------------|-------|
| {{INFRASTRUCTURE_ITEM}} | {{P0_P1_P2}} | {{DEPENDS_ON}} | {{ISSUE_REF}} |

## Status

- [ ] Phase 1: Foundation
- [ ] Phase 2: Tests
- [ ] Phase 3: Security
- [ ] Phase 4: Code Quality
- [ ] Phase 5: Infrastructure
