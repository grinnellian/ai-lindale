# Skill Skeleton Template
#
# Skills are project-owned by default (FEAT-011) — most projects will
# create these directly rather than have the framework generate them.
# This file is a starting skeleton showing the expected frontmatter
# convention, not a meta-template consumed by an agent.
#
# Skills live at .claude/skills/<skill-name>/SKILL.md. Copy this file
# to that path and customize.
#
# Conventions:
#   - Directory name and `name:` field should match (kebab-case).
#   - `description:` is shown to Claude Code when deciding whether the
#     skill applies — keep it specific about when to invoke the skill.
#   - Everything below the frontmatter is the skill's instructions,
#     read by Claude Code when the skill is invoked.

---
name: {{SKILL_NAME}}
description: {{One or two sentences describing what this skill does and when to use it}}
---

## What this skill does

{{Describe the task this skill automates or the workflow it encodes.}}

## When to use it

{{Describe the trigger conditions — e.g. "when committing per-file changes
across multiple unrelated files" or "when designing a new mission spec".}}

## Steps

1. {{Step one}}
2. {{Step two}}
3. {{Step three}}

## Notes

{{Any caveats, edge cases, or references to related memory/patterns.md
entries.}}
