# Project State

This file is overwritten (not appended) at the end of each working session.

## Current focus

`agent-orchestrator` is at v11. The two Copilot-chat watchers are now `Watch-CopilotChatV1.ps1` (full
UI tree per poll) and `Watch-CopilotChatV2.ps1` (the default: a light probe per poll). A live card test
found that V2 never saw a question card; V2 now searches the last real messages near the end of the
chat list and returns V1's details (question, options, banners, `AwaitingReply`, last message) by
running V1 once when the wait ends. Test cases for the scripts now live in `tests\` folders next to
them. This repo remains docs-only; the gitignored `.vs\Visual-Studio-Copilot-Skills.slnx` is
open-folder scaffolding, not a tracked C# solution.

## Recently changed

- `agent-orchestrator/SKILL.md` v6 to v11 (commits `301d688`, `8e6cfd8`, `a39082d`, `4ff2b40`,
  `fd8a50c`, `d516abe`): plain-text question detection, `Send-CopilotPrompt.ps1` finds the chat
  itself (v7), watcher rename to V1/V2 (v8), end-of-wait sound change and its revert (v9, v10),
  V2 fix and detail step (v11).
- `agent-orchestrator/scripts/`: new `Read-CopilotReply.ps1`, `Invoke-CopilotReview.ps1`,
  `Watch-CopilotChatV2.ps1` (learned scripts, indexed in `scripts/SCRIPTS.md`).
- Test documents (`ca5de2f` and `d516abe`): `agent-orchestrator/scripts/tests/` (watchers, send,
  option picker, reading and review scripts, `Compare-RepoSnapshot`), `ui-interaction/scripts/tests/`
  (`AgentCursor`), `tests/` (`Install-Skills`).
- `.github/copilot-instructions.md`: regenerated memory section (skill-version 23).

## Open tasks/bugs

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
