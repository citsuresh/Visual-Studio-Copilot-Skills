# Project State

This file is overwritten (not appended) at the end of each working session. Earlier snapshots are in git history.

## Current focus

2026-11-26: a way to supervise a Claude desktop chat, a fix to reading a worker's answer, and the model-switch rules.
`agent-orchestrator` is at v46, `ui-interaction` at v29, `read-aloud` is unversioned (not in the index); all committed and pushed
(`origin/main` 30ac9dc) and installed.
- v45 (`-WaitReply` fix): the worker's `Replying to orchestrator:` line is matched at the start of ANY line, because a worker that
  follows the bootstrap text puts `From orchestrator:` and `Replying to orchestrator:` in one chat message (seen live). The
  first guess, a wait card not yet drawn, was not supported by the chat data. `ui-interaction` v29 deletes stale
  `AgentCursor.Native.<hash>.dll` copies (older than 7 days) after a new compile.
- v46 (Claude desktop chat): Step 1b of the orchestrator skill identifies the chat type first (`devenv.exe` is Copilot,
  `Claude.exe` class `Chrome_WidgetWin_1` title `Claude` is Claude). For Claude the window is used once for the first message
  (`Send-ClaudePrompt.ps1`), later messages go by mailbox with `-Channel`, and the answer is read from the worker's transcript
  file (`Read-ClaudeReply.ps1`, picks the file by channel name). `-WaitIdleSeconds` waits for a working chat instead of refusing.
  Live evidence, one machine, Claude 6.28899.6: a value set through UIA applies asynchronously (read-back matched after 117 to
  178 ms, so it is polled), the box emptied 282 to 334 ms after Send, only the ACTIVE chat exposes a `Prompt`, the busy refusal
  (`ClaudeBusy`) worked on the real UI, and a Copilot agent in Visual Studio sent the test line into a Claude chat three times
  (ad hoc code twice, the installed script once). No Claude worker with a mailbox listener was exercised end to end.
- read-aloud meeting check (`Test-MeetingActive.ps1`, written by another Claude session and reviewed here): stays quiet while
  an app that is not excluded holds the microphone; `mute` (default), `duck` or `off` in `tts-settings.json`; fails open.
  `Test-ReadAloud.ps1` passes (8 groups, via `-Command` only). A literal tab in the settings path in the skill text was fixed.
- Model switching: a session can switch its own model by driving the window's model menu with UIA (applies from the NEXT
  reply). The rules (suggest with a reason, Switch or Stay card, switch only on a click, 30 s wait then stay) are in the user's
  GLOBAL `~/.claude/CLAUDE.md`, together with the general working habits and the PowerShell 5.1 pitfalls. This repo's
  `CLAUDE.md` now holds only project-specific instructions.
- Offline suites at last run: sender 418, mailbox 76, router 75, Claude sender 28, Claude reader 23, input watcher 13,
  choice prompt 31, user activity 81, watcher 19 (via `-Command` only), read-aloud 8 groups.
- Standing user rules: UI automation must never disturb a person typing; keep testing cheap (offline first, batch live runs);
  commit, push and install only when asked; model suggestions follow the global file.

## Recently changed

- 2026-11-26 (pushed): v45 and ui-interaction v29 `83060ef`, v46 `29cf23e`, read-aloud meeting check `30ac9dc`. New scripts:
  `Send-ClaudePrompt.ps1`, `Read-ClaudeReply.ps1` (both in `agent-orchestrator/scripts/`), `read-aloud/scripts/Test-MeetingActive.ps1`;
  new tests `Test-SendClaudePrompt.ps1`, `Test-ReadClaudeReply.ps1`.
- This commit: this file, the trimmed repo `CLAUDE.md`, the five-column fix of four `docs/SCRIPTS.md` rows (they had two),
  and a design note.
- Not committed: `ui-interaction/scripts/Watch-UserInput.ps1` and `scripts/agent/Test-WatchUserInput.ps1` (a watcher that counts
  key presses, clicks and scrolls and ignores mouse movement; 13 offline assertions; not in the skill text, the index or
  `docs/SCRIPTS.md`; not tried with real input; not used by any flow yet).

## Open tasks/bugs

- Not verified: a reply read from a live Claude worker that runs the mailbox listener; a send into a busy Claude chat that
  queues; multi-line text; reaching a chat that is not the active one (split view or a second window); the idle suggestion
  text some users see in the chat box (not exposed in any UIA property read). The meeting check can stay silent if a crashed
  app leaves its microphone entry open (a guess, not seen); `"meeting":"off"` is the workaround.
- `Test-AgentMailbox.ps1` failed once in a run of five suites and passed in six reruns; cause not found.
- Mailbox: the worker's self-stop after two timeouts and a worker that never listens again are tested offline only; waits longer
  than 400 s are untried.
- Ten other scripts still use `$PSScriptRoot` in a `param()` default, empty under `powershell.exe -File` (user chose to leave
  them). `Test-ReadAloud.ps1` and `Test-WatcherProgress.ps1` run only via `-Command`.
- Teams screen-share detection for the quiet wait is untested until the person can share a screen.
- The Windows agent-activity limit: input sent by this machine's agents cannot be told from the person's input.
- Carried forward from earlier sessions, not re-checked in this one: notification v2 enable/stop branches partly untested and no
  phone-reply bridge; TTS cases not run (NoVoice with ducking, PowerShell 7, a real chat triggering "enable tts"); hooks need
  `git config core.hooksPath .githooks` once per clone; the separate AgentDebugToolkit repo (old `Watch-CopilotChat.ps1` name,
  list-windows flag message, an interactive-desktop test trait, two uncommitted graph doc files); an unrelated typo ("ersion")
  in the 2026-11-13 entry of `docs/DESIGN_DECISIONS.md`; the 2026-11-13 secrets/personal-data review found nothing in the four
  repos (a username path remains only in the Bootstrap-generated `.github/copilot-instructions.md`).
- This repo is docs-only: no code graph or Key Flows file is generated, and documentation changes need no application build;
  installer consistency and generated-index checks apply. The graph was not updated in this session's End Session (no solution
  registered; run Bootstrap only if one is added).