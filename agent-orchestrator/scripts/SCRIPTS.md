# Learned scripts (agent-orchestrator)

Scripts saved by the orchestrator during supervised runs, next to the core scripts listed in
`../SKILL.md`. Check this table before writing orchestration code. Curated by the user: scripts and
lines are never deleted by the orchestrator.

| Script | Purpose | How to call | Read-only or sends input / modifies | Date |
| --- | --- | --- | --- | --- |
| `Read-CopilotReply.ps1` | Reads Copilot's reply to one prompt: scrolls the chat list to its end (and checks `boundaryReached`), reads all rendered messages, returns only what follows the prompt, plus the completion footer, a `Busy` flag (stop button showing) and `IsClean` (the reply says NO ISSUES REMAIN with no numbered findings). Fixes "no reply yet" reads caused by the virtualized chat list. | `.\Read-CopilotReply.ps1 -Hwnd <h> -AfterPrompt '<phrase from the prompt>'` (without `-AfterPrompt` it uses the last Restore Checkpoint marker) | Read-only apart from the chat list's scroll position; never types or clicks | 2026-10-30 |
| `Invoke-CopilotReview.ps1` | One call for a review loop round: resolves the window (`-TitleContains`, restricted to `devenv`), refuses to send when the chat tab is not showing or the input holds text (so a draft is not cleared), sends the prompt with a unique reference tag via `Send-CopilotPrompt.ps1`, waits with `Watch-CopilotChat.ps1`, never answers a permission prompt or question card (returns `NeedsUser` with the question), then returns the reply via `Read-CopilotReply.ps1`. `-Review` wraps the prompt in review-only rules and the NO ISSUES REMAIN reply format. | `.\Invoke-CopilotReview.ps1 -TitleContains '<project>' -Review -Prompt '<what to review>'` | Sends a prompt (red-dot cursor via `Send-CopilotPrompt.ps1`); the blue session dot is the caller's | 2026-10-30 |
