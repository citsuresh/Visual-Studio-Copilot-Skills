# Project State

This file is overwritten (not appended) at the end of each working session.

## Current focus

Making the skills portable. The three companion toolkits (GraphTools, AgentDebugToolkit,
VsChatHistoryToolkit) are public repos with a `VERSION` and `scripts\agent\Build-Toolkit.ps1`.
`Install-Skills.ps1` clones, fast-forwards (`-Remote`) and builds them under
`%USERPROFILE%\.copilot\toolkits\<Name>`, prints `TOOLKIT:` lines, and writes
`%USERPROFILE%\.copilot\skills-source.json` (`SOURCE:` in `-Check`). Flags: `-SkipToolkits`,
`-ToolkitBaseUrl`. The skills no longer hardcode `C:\MyFiles\Git\...`; each skill that uses a toolkit
checks it in Step 0 and asks before running the installer. Skill versions now: vs-debug 9,
ui-interaction 20, ui-navigation-orchestrator 8, vs-chat-history 11, agent-orchestrator 19,
project-memory-management 3, graph 26 (bootstrapped projects will look stale: the wrapper path changed).
Parts 1-3 are committed (`de6c323`); Parts 4 (skills) and 5 (docs, secrets review) are applied and
installed but NOT committed. This repo remains docs-only: no tracked `.sln`/`.slnx`, code graph, or Key
Flows file.

## Recently changed (uncommitted)

The seven skill `SKILL.md` files above plus `install-skills`, the eight `agent-orchestrator\scripts\*.ps1`
(default exe path under the toolkits folder), `skills-index.json`, `README.md` (Prerequisites, Installing,
new Toolkits section), the graph skill README, `tests/Install-Skills.tests.md` (I-24 to I-39),
`docs/CODE_SUMMARY.md`, `docs/DESIGN_DECISIONS.md`, `docs/ROADMAP.md`, this file.

## Secrets / personal-data review (2026-11-13)

All four repos, working trees and full history: no tokens, keys, passwords, databases or binaries. Fixed and
pushed to the public toolkit repos the same day (GraphTools 91e46d6, AgentDebugToolkit 67f28aa,
VsChatHistoryToolkit 65e7594): personal email line removed from GraphTools copilot-instructions.md;
session-state/ added to AgentDebugToolkit .gitignore; MIT LICENSE added to all three. Left as is: the
committed graph JSONs in AgentDebugToolkit and VsChatHistoryToolkit contain C:\Users\sveluswa\.nuget\...`npaths (username only; the graphs are those repos' own project memory, so they stay tracked).
In this repo only `.github/copilot-instructions.md` (Bootstrap-generated) holds a username path.

## Open tasks/bugs

- Parts 4 and 5 committed and pushed (see git log).
- Not run: I-38 (a skill's new Step 0 toolkit check in a real chat), I-39 (missing `skills-source.json`),
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
- The `install-skills` skill itself has not been run in a real chat (only the script was tested).
- Not tested: `Speak-Text.ps1` on a machine with no voice (simulated only).
- Not run live: tool permission prompts, workspace banners, the V2 Idle-to-Pending upgrade path, a card
  above a scrolled-up chat list, the `Send-CopilotPrompt.ps1` new-session path. All `AgentCursor` and
  `Compare-RepoSnapshot` cases are marked not run; `Install-Skills` I-01 to I-19 and I-24 to I-35 ran in a
  sandbox only.
- AgentDebugToolkit repo (separate): `tools/Watch-CopilotChat.ps1` still has the old name and is not
  synced with V1; make the MCP `ui_inspect` read-only by dropping `screenshot`; improve the list-windows
  flag error message; add a test trait for the interactive-desktop click test. It also has two
  uncommitted graph doc files, deliberately left out.
- `docs/DESIGN_DECISIONS.md` has an unrelated pre-existing typo ("ersion" in the 2026-11-13 skills index
  entry), not fixed.
- No code graph or Key Flows file is generated here; no build or test suite applies.
