# Code Summary

This repo is a collection of GitHub Copilot CLI **skills** for use with Visual Studio Copilot. It
has no application code of its own — each top-level skill folder contains a `SKILL.md` (the
skill's instructions/workflows) plus supporting docs and assets. `Install-Skills.ps1` copies each
skill folder into `%USERPROFILE%\.copilot\skills\` so they're available to the Copilot CLI.

No C# solution detected in this repo; tracked in docs-only mode (no code graph).

## Skills in this repo

| Skill | Purpose |
|---|---|
| `project-memory-management` | Deprecated predecessor; use `project-memory-management-graph` in docs-only mode instead. |
| `project-memory-management-graph` | Begin Session, Bootstrap, End Session and Initialize; supports docs-only repos or registered per-solution Roslyn graphs through GraphTools. Includes user-curated feature-checklist guidance and regression-audit protocols. |
| `agent-orchestrator` | Supervise a Copilot agent in another Visual Studio window; composes UI interaction and debugger skills. Core scripts in `scripts/`: `Send-CopilotPrompt`, `Watch-CopilotChat` (Pending/Working/Idle, including permission prompts), `Get-CopilotChatTranscript`, `Select-ChoicePromptOption` (cards and permission-prompt buttons) and `Compare-RepoSnapshot`; learned scripts are indexed in `scripts/SCRIPTS.md` when saved. |
| `ui-interaction` | Shared UI automation primitives through AgentDebugToolkit; scoped selectors, ambiguity handling, compact inspection and explicit typed-input read-back. Owns the shared hands-off cursor indicator `scripts/AgentCursor.ps1` (blue = orchestrator, green = UI run, red = input), also used by `agent-orchestrator` and `ui-navigation-orchestrator`. |
| `ui-navigation-orchestrator` | Navigate WinForms/WPF apps with a per-target-repo navigation-tree cache; composes `ui-interaction` and `vs-debug`. |
| `vs-debug` | Visual Studio debugger bridge through AgentDebugToolkit/EnvDTE: attach, breakpoints, stepping, call stacks, thread/frame selection and evaluation. |
