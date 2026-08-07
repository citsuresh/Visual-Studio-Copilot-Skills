# Code Summary

This repo is a collection of GitHub Copilot CLI **skills** for use with Visual Studio Copilot. It
has no application code of its own — each top-level skill folder contains a `SKILL.md` (the
skill's instructions/workflows) plus supporting docs and assets. `Install-Skills.ps1` copies each
skill folder into `%USERPROFILE%\.copilot\skills\` so they're available to the Copilot CLI.

No C# solution detected in this repo; tracked in docs-only mode (no code graph).

## Skills in this repo

| Skill | Purpose |
|---|---|
| `project-memory-management` | Manage persistent, low-token project memory (`docs/CODE_SUMMARY.md`, `DESIGN_DECISIONS.md`, `PROJECT_STATE.md`, `ROADMAP.md`) for any repo. |
| `project-memory-management-graph` | Same as above, plus builds/maintains a Roslyn-based code knowledge graph via the standalone `GraphTools` executables. Intended for large/complex C# solutions. |
