# Project State

This file is overwritten (not appended) at the end of each working session.

## Current focus

Closed the open-task list from the v25 (TTS) work. `Install-Skills.ps1` gained `-Prune` (removes
installed files no longer in the repo, with the per-skill confirmation; default still leaves them but
now lists them); sandbox cases I-06, I-09 and I-10 passed (`tests/Install-Skills.tests.md`).
`Speak-Text.ps1` was run in a portable PowerShell 7.4.6 (exit 0, spoken). The v25 work and the
Bootstrap re-sync are committed and pushed (`fb8de95`, `33137d8`). This repo remains docs-only: no
tracked `.sln`/`.slnx`, code graph, or Key Flows file.

## Recently changed

Uncommitted (manual commit review first): `Install-Skills.ps1` (`-Prune`),
`tests/Install-Skills.tests.md` (I-06 updated, I-09 and I-10 added, findings rewritten), `README.md`
(`-Prune` note), `docs/PROJECT_STATE.md` (this snapshot).

## Open tasks/bugs

- Commit and push the uncommitted files above.
- Not tested: `Speak-Text.ps1` on a machine with no voice (simulated only); whether a later chat
  follows "enable tts" in practice (it did in this chat).
- Not run live: tool permission prompts, workspace banners, the V2 Idle-to-Pending upgrade path, a
  card above a scrolled-up chat list, the `Send-CopilotPrompt.ps1` new-session path. All
  `AgentCursor` and `Compare-RepoSnapshot` cases are marked not run; `Install-Skills` I-01 to I-10 ran
  in a sandbox only (the `-Prune -Force` combination with files to delete was not run).
- The earlier notes on `Read-CopilotReply.ps1` (empty reply on a long reply) and on monitoring-cost
  measurements were stale: the first was fixed 2026-10-31 (header of the script), the second is
  recorded in `agent-orchestrator/scripts/tests/Monitoring-cost.md`. Not re-run today; a live
  `Read-CopilotReply.ps1` check needs a second VS chat window.
- AgentDebugToolkit repo (separate): `tools/Watch-CopilotChat.ps1` still has the old name and is not
  synced with V1; make the MCP `ui_inspect` read-only by dropping `screenshot`; improve the
  list-windows flag error message; add a test trait for the interactive-desktop click test.
- No code graph or Key Flows file is generated here; no build or test suite applies.
