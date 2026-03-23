# Wickerman-OS Architecture Assessment (2026-03-22)

## Attribution

Only the initial commit is Tabulanis's work. All subsequent work (devcontainer, tinyproxy,
standardization, security) was done by the user with their Lindalë agents. Patterns "pulled
from wickerman-os" were the user's own work done in that repo.

## What it is

A single-machine, self-hosted AI platform: Python installer generates a Docker Compose stack
with NiceGUI dashboard, nginx reverse proxy, and five plugins (Model Router, Chat, Flow Editor,
Model Trainer, Code Forge). Each plugin is a JSON manifest + embedded Dockerfile + embedded app code.

## Verdict: Reference implementation you'd rewrite, not components to adopt

### Useful as reference

- **Model Router** (`manager.py`): OpenAI-compatible API routing between local llama.cpp and
  remote providers (OpenAI/Anthropic/Gemini). Multi-slot architecture with per-agent system prompts.
  Good reference for Lindalë's inference layer.
- **Per-agent RAG memory**: FAISS vector store + SQLite per agent, with automatic context archival.
  Maps to Lindalë's agent memory scoping.
- **GPU resource management**: Hardware detection (AVX/CUDA), VRAM monitoring, GPU layer allocation.
  Needed for the home lab b100 machine.
- **Docker networking patterns**: `wm-net` network, per-plugin containers, nginx gateway, `.local`
  subdomain routing.

### Red herrings (Tabulanis's initial architecture — the starting state, not the target)

- Dashboard/Chat UI/Flow Editor/Trainer/Forge — solve his use case, not agent orchestration
- Monolithic installer — no clean module boundaries
- Embedded-string-literal packaging — can't lint, test, diff, or contribute to
- Docker socket mounting + hardcoded creds — opposite of Lindalë's security direction

### Correct relationship

Benefit flows FROM Lindalë TO wickerman-os (brownfield adoption, Layer 4 test case).
The devcontainer/tinyproxy patterns the user "pulled back" were their own work done in that repo.
Wickerman-os is not an upstream dependency.
