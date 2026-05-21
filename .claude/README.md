# .claude/ structure

Core agents (architect, tpm, dev) are symlinked from the Lindalë
framework (.ai-lindale/). Do not edit them here — edit the framework repo.

Project-specific agents (e.g. <domain>-sme) are real files
owned by this project.

To update the framework:

```bash
git submodule update --remote .ai-lindale
```
