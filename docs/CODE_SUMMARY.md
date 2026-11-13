# Code Summary

This repo is a collection of GitHub Copilot CLI **skills** for use with Visual Studio Copilot. It
has no application code of its own — each top-level skill folder contains a `SKILL.md` (the
skill's instructions/workflows) plus supporting docs and assets. `Install-Skills.ps1` copies each
skill folder into `%USERPROFILE%\.copilot\skills\` so they're available to the Copilot CLI.

No C# solution detected in this repo; tracked in docs-only mode (no code graph).

## Update index and hooks

| File | Responsibility |
|---|---|
| `skills-index.json` | Generated: per skill `version` and one-line `whatsNew`. Read by each skill's Step 0 (clone copy and `git show "@{u}:skills-index.json"`) instead of the whole `SKILL.md`. |
| `scripts/Update-SkillsIndex.ps1` | Generator, derived from each `SKILL.md`'s `CURRENT_SKILL_VERSION` and changelog entry. `-Check` (read-only), `-Stage`, `-WarnUnbumped` (staged vs HEAD), `-WarnUnbumpedFrom/-To` (range, warn only). |
| `.githooks/pre-commit`, `.githooks/pre-push` | Regenerate and stage the index on commit; warn (never block) about a missing version bump over the whole push. Need `git config core.hooksPath .githooks` per clone; LF line endings (see `.gitattributes`). |
| `Install-Skills.ps1 -Check` | Also prints `INDEX: UpToDate / OutOfDate / Missing`; does not change `RESULT:`. |

## Skills in this repo

| Skill | Purpose |
|---|---|
| `project-memory-management` | Deprecated predecessor; use `project-memory-management-graph` in docs-only mode instead. |
| `project-memory-management-graph` | Begin Session, Bootstrap, End Session and Initialize; supports docs-only repos or registered per-solution Roslyn graphs through GraphTools. Includes user-curated feature-checklist guidance and regression-audit protocols. Ships `scripts/Speak-Text.ps1` (optional read-aloud: speaks a short text with the Windows default voice via System.Speech; `-Text` only, `NoVoice` and exit 2 when no voice), used by the Step 7c bullet that Bootstrap writes into the Persistent Project Memory section. |
| `agent-orchestrator` | Supervise a Copilot agent in another Visual Studio window; composes UI interaction and debugger skills. Core scripts in `scripts/`: `Send-CopilotPrompt`, `Watch-CopilotChatV2` (default: light Pending/Idle poll) and `Watch-CopilotChatV1` (full-tree: Pending/Working/Idle with prompt text, including permission prompts), `Get-CopilotChatTranscript`, `Select-ChoicePromptOption` (cards and permission-prompt buttons) and `Compare-RepoSnapshot`; learned scripts are indexed in `scripts/SCRIPTS.md` when saved. |
| `ui-interaction` | Shared UI automation primitives through AgentDebugToolkit; scoped selectors, ambiguity handling, compact inspection and explicit typed-input read-back. Owns the shared hands-off cursor indicator `scripts/AgentCursor.ps1` (blue = orchestrator, green = UI run, red = input), also used by `agent-orchestrator` and `ui-navigation-orchestrator`. |
| `ui-navigation-orchestrator` | Navigate WinForms/WPF apps with a per-target-repo navigation-tree cache; composes `ui-interaction` and `vs-debug`. |
| `vs-debug` | Visual Studio debugger bridge through AgentDebugToolkit/EnvDTE: attach, breakpoints, stepping, call stacks, thread/frame selection and evaluation. |
| `vs-chat-history` | Search and read local Visual Studio Copilot Chat history through the `chathistory` CLI; supports session lookup and capped excerpts, with rename only on request. |
| `install-skills` | Lets Copilot install/update the repo's skills on request ("install skills from <url>", "check the repo and update all the skills"): `Install-Skills.ps1 -Check -Remote` (read-only, `REMOTE:` and `RESULT:` lines, companion-tool report), then `-Remote -Force` (pull + install), `-Prune` only after asking. Every other skill runs a once-per-session Step 0 that fetches GitHub and compares versions (local clone and upstream). |
