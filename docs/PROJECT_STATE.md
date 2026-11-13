# Project State

This file is overwritten (not appended) at the end of each working session.

## Current focus

Making installs and updates easy on any machine. `Install-Skills.ps1` has `-Prune` and `-Check`
(committed `a83824b`, `68e1d6d`) plus `-Remote` and `-MaxAgeHours` (fetch GitHub, report `REMOTE:`,
pull fast-forward only and install; the `RESULT:` line says "GitHub not checked" when the remote is
unreachable). Every skill's Step 0 now also checks the GitHub upstream, once per session, and asks
before running `Install-Skills.ps1 -Remote -Force`: the five UI/chat skills (version bumps: vs-debug 7,
ui-interaction 18, ui-navigation-orchestrator 6, vs-chat-history 9, agent-orchestrator 17), the graph
skill (Workflow 0 section, no bump), the deprecated `project-memory-management` (new version 1) and
`install-skills` (uses `-Remote`). Sandbox cases I-13 to I-19 passed (`tests/Install-Skills.tests.md`).
`Speak-Text.ps1` ran in PowerShell 7.4.6. This repo remains docs-only: no tracked `.sln`/`.slnx`, code
graph, or Key Flows file.

## Recently changed

Uncommitted: `Install-Skills.ps1` (`-Remote`, `-MaxAgeHours`), the `SKILL.md` of all eight skills,
`README.md`, `docs/CODE_SUMMARY.md`, `tests/Install-Skills.tests.md` (I-13 to I-19),
`docs/PROJECT_STATE.md`. The edited skills are not installed yet.

## Open tasks/bugs

- The new Step 0 text (fetch, `git show "@{u}:..."`, `ask_user`, then the install) has not been run by a
  skill in a real chat, only the script behind it. Until the edited skills are installed, the running
  copies still use the old local-only check.
- The `install-skills` skill itself has not been run in a real chat (only the script was tested), and
  the first install on a brand-new machine still needs the spelled-out prompt in the README (Option 0).
  The printed `git clone` lines for missing companions were not seen (none was missing here).
- Not tested: `Speak-Text.ps1` on a machine with no voice (simulated only); whether a later chat
  follows "enable tts" in practice (it did in this chat).
- Not run live: tool permission prompts, workspace banners, the V2 Idle-to-Pending upgrade path, a
  card above a scrolled-up chat list, the `Send-CopilotPrompt.ps1` new-session path. All
  `AgentCursor` and `Compare-RepoSnapshot` cases are marked not run; `Install-Skills` I-01 to I-19 ran
  in a sandbox only (the `-Prune -Force` combination with files to delete was not run).
- The earlier notes on `Read-CopilotReply.ps1` (empty reply on a long reply) and on monitoring-cost
  measurements were stale: the first was fixed 2026-10-31 (header of the script), the second is
  recorded in `agent-orchestrator/scripts/tests/Monitoring-cost.md`. Not re-run today; a live
  `Read-CopilotReply.ps1` check needs a second VS chat window.
- AgentDebugToolkit repo (separate): `tools/Watch-CopilotChat.ps1` still has the old name and is not
  synced with V1; make the MCP `ui_inspect` read-only by dropping `screenshot`; improve the
  list-windows flag error message; add a test trait for the interactive-desktop click test.
- No code graph or Key Flows file is generated here; no build or test suite applies.
