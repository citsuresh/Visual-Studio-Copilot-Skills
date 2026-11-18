# Project State

This file is overwritten (not appended) at the end of each working session.

## Current focus

2026-11-18: Begin Session and user-approved Bootstrap synced this repo's project memory from
graph skill v25 to v27. The generated instructions now use the installed GraphTools wrapper
under `%USERPROFILE%\.copilot\toolkits\GraphTools` and delegate TTS to `read-aloud`.
Reviewed real-world UI/debugger feedback and shipped source-verified skill corrections. Only
AgentDebugToolkit Phase 1a (read-only state inspection) is approved and delegated to the separate
VS instance; its completion/audit report is pending. No toolkit commit, push or installation is
authorized. Installed skills report up to date; toolkits were unchanged by the latest install.
This repo remains docs-only, with an empty graph registry and no Key Flows file. The graph
viewer matches the installed skill's copy. One reusable script is indexed.

## Recently changed

- Bootstrap: `.github/copilot-instructions.md` and this file.
- Committed/pushed `99b9173`: `ui-interaction` v21, `vs-debug` v10,
  `agent-orchestrator` v20 and `skills-index.json`. Installed copies were hash-verified.
- Committed/pushed `3ce128e`: `read-aloud/SKILL.md` now requires hosting-repository identity
  and announcements before blocking questions in both speech modes. Installed copy matches
  the approved draft/source hash; post-install check reports `RESULT: UpToDate`.

## Secrets / personal-data review (2026-11-13)

All four repos, working trees and full history: no tokens, keys, passwords, databases or binaries. Fixed and
pushed to the public toolkit repos the same day (GraphTools 91e46d6, AgentDebugToolkit 67f28aa,
VsChatHistoryToolkit 65e7594): personal email line removed from GraphTools copilot-instructions.md;
session-state/ added to AgentDebugToolkit .gitignore; MIT LICENSE added to all three. Left as is: the
committed graph JSONs in AgentDebugToolkit and VsChatHistoryToolkit contain C:\Users\sveluswa\.nuget\...`npaths (username only; the graphs are those repos' own project memory, so they stay tracked).
In this repo only `.github/copilot-instructions.md` (Bootstrap-generated) holds a username path.

## Open tasks/bugs

- TTS pre-question timing: user confirmed the repo-labelled auto-TTS announcement finished
  before the question card while this VS was inactive. Regular TTS, active-window silence,
  both-mode precedence and disabled-mode scenarios remain untested for this change.
- The graph skill's Step 0 toolkit check ran in this chat and reported `GraphTools UpToDate`;
  repair/error branches were not exercised.
- Not run: I-39 (missing `skills-source.json`),
  `SOURCE: Differs` / `NotRecorded`. Not observed: Defender/SmartScreen on locally built unsigned
  executables; PowerShell 7 (only 5.1 installed).
- TTS: new `read-aloud` skill (committed, installed, hashes verified) with `Speak-Text.ps1` plus
  opt-in ducking (`AudioDucker.cs`); graph skill v27 (Step 7c is now a pointer bullet; its `Speak-Text.ps1`
  is a forwarder). Tested in a temp folder: helper round trip, manual-change case, ducking during speech,
  kill mid-speech then recovery, stub installed and not installed; live ducking heard and accepted at
  `duckPercent` 10 (user's machine setting, not in the repo). Not tested: NoVoice with ducking on,
  PowerShell 7, a real chat triggering the skill from "enable tts".
- Hooks need `git config core.hooksPath .githooks` once per clone (set here); web-UI edits and
  `--no-verify` bypass them. No GitHub Action exists.
- The `install-skills` skill ran in this chat: remote check, approved install with
  `-SkipToolkits`, installed-file hash comparison and post-install check all succeeded.
- Not tested: `Speak-Text.ps1` on a machine with no voice (simulated only).
- Not run live: tool permission prompts, workspace banners, the V2 Idle-to-Pending upgrade path, a card
  above a scrolled-up chat list, the `Send-CopilotPrompt.ps1` new-session path. All `AgentCursor` and
  `Compare-RepoSnapshot` cases are marked not run; `Install-Skills` I-01 to I-19 and I-24 to I-35 ran in a
  sandbox only.
- AgentDebugToolkit repo (separate): `tools/Watch-CopilotChat.ps1` still has the old name and is not
  synced with V1; improve the list-windows
  flag error message; add a test trait for the interactive-desktop click test. It also has two
  uncommitted graph doc files, deliberately left out. Feedback review confirmed current MCP
  `ui_inspect` is already read-only and has no screenshot option.
- `docs/DESIGN_DECISIONS.md` has an unrelated pre-existing typo ("ersion" in the 2026-11-13 skills index
  entry), not fixed.
- No code graph or Key Flows file is generated here. Documentation changes need no application
  build; installer consistency and generated-index checks apply.
