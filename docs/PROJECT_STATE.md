# Project State

This file is overwritten (not appended) at the end of each working session.

## Current focus

Added the optional read-aloud (TTS) rule to `project-memory-management-graph` (skill version 25):
Bootstrap Step 7c, `scripts/Speak-Text.ps1` (system default voice, `-Text` only, `NoVoice` exit 2).
Committed (`fb8de95`), installed to `%USERPROFILE%\.copilot\skills\` and pushed to `origin/main`.
Then re-ran Bootstrap here to re-sync this repo from v24 to v25. This repo remains docs-only: no
tracked `.sln`/`.slnx`, code graph, or Key Flows file.

## Recently changed

Committed and pushed (`fb8de95`): `project-memory-management-graph/SKILL.md` (v25),
`project-memory-management-graph/scripts/Speak-Text.ps1` (new).

Uncommitted in the working tree:

- `.github/copilot-instructions.md`: marker 25, TTS bullet at the end of Persistent Project Memory;
  also the earlier v24 changes (marker, `vs-chat-history` pointer).
- `docs/CODE_SUMMARY.md`: `vs-chat-history` row (earlier) and the `Speak-Text.ps1` note.
- `docs/DESIGN_DECISIONS.md`: new 2026-11-13 entry on the TTS rule and the never-set-a-voice choice.
- `docs/PROJECT_STATE.md`: this snapshot.
- New: `docs/SCRIPTS.md` and `scripts/agent/Find-WrongLineEndings.ps1` (read-only check for lone-LF
  lines in CRLF files; the edit tool left three such lines once).

## Open tasks/bugs

- Commit and push the uncommitted files above (manual commit review first).
- Not tested: `Speak-Text.ps1` in PowerShell 7 and on a machine with no voice (simulated only);
  whether a later chat follows "enable tts" in practice.
- Not run live: tool permission prompts, workspace banners, the V2 Idle-to-Pending upgrade path, a
  card above a scrolled-up chat list, the `Send-CopilotPrompt.ps1` new-session path. All
  `AgentCursor`, `Compare-RepoSnapshot` and `Install-Skills` cases are marked not run.
- `Install-Skills.ps1` does not remove destination-only files: a script removed from the repo stays in
  the installed skill and must be deleted by hand.
- `Read-CopilotReply.ps1` can return an empty reply when searching for a long prompt's text.
- Monitoring-cost measurements for supervising a chat through a sub-agent are still to be made.
- AgentDebugToolkit repo (separate): `tools/Watch-CopilotChat.ps1` still has the old name and is not
  synced with V1; make the MCP `ui_inspect` read-only by dropping `screenshot`; improve the
  list-windows flag error message; add a test trait for the interactive-desktop click test.
- No code graph or Key Flows file is generated here; no build or test suite applies.
