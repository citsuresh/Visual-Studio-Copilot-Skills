# Project State

This file is overwritten (not appended) at the end of each working session.

## Current focus

Making installs and updates easy on any machine. `Install-Skills.ps1` has `-Prune` (committed
`a83824b`), `-Check` (read-only, final `RESULT:` line) and a companion-tool report (folders like
`C:\MyFiles\Git\GraphTools` that skills refer to but are missing, with a `git clone` line for the three
known ones). New skill `install-skills` handles "install skills from <url>" and "check the repo and
update all the skills" (clone/pull, `-Check`, `-Force`, asks before `-Prune`); installed here and
hash-verified. Sandbox cases I-06 and I-09 to I-12 passed (`tests/Install-Skills.tests.md`).
`Speak-Text.ps1` ran in PowerShell 7.4.6. This repo remains docs-only: no tracked `.sln`/`.slnx`, code
graph, or Key Flows file.

## Recently changed

Committed with this snapshot: `Install-Skills.ps1` (`-Check`, companion report), new
`install-skills/SKILL.md`, `README.md` (Option 0 and `-Check` text, folder row), `docs/CODE_SUMMARY.md`
(skill row), `tests/Install-Skills.tests.md` (I-11, I-12), `docs/PROJECT_STATE.md`.

## Open tasks/bugs

- The `install-skills` skill itself has not been run in a real chat (only the script was tested), and
  the first install on a brand-new machine still needs the spelled-out prompt in the README (Option 0).
  The printed `git clone` lines for missing companions were not seen (none was missing here).
- Not tested: `Speak-Text.ps1` on a machine with no voice (simulated only); whether a later chat
  follows "enable tts" in practice (it did in this chat).
- Not run live: tool permission prompts, workspace banners, the V2 Idle-to-Pending upgrade path, a
  card above a scrolled-up chat list, the `Send-CopilotPrompt.ps1` new-session path. All
  `AgentCursor` and `Compare-RepoSnapshot` cases are marked not run; `Install-Skills` I-01 to I-12 ran
  in a sandbox only (the `-Prune -Force` combination with files to delete was not run).
- The earlier notes on `Read-CopilotReply.ps1` (empty reply on a long reply) and on monitoring-cost
  measurements were stale: the first was fixed 2026-10-31 (header of the script), the second is
  recorded in `agent-orchestrator/scripts/tests/Monitoring-cost.md`. Not re-run today; a live
  `Read-CopilotReply.ps1` check needs a second VS chat window.
- AgentDebugToolkit repo (separate): `tools/Watch-CopilotChat.ps1` still has the old name and is not
  synced with V1; make the MCP `ui_inspect` read-only by dropping `screenshot`; improve the
  list-windows flag error message; add a test trait for the interactive-desktop click test.
- No code graph or Key Flows file is generated here; no build or test suite applies.
