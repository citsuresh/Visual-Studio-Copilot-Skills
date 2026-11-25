# Working in this repository (for Claude Code sessions)

This repository holds the Visual Studio Copilot skills (`agent-orchestrator`, `ui-interaction`, and others), their
scripts and the offline tests in `scripts/agent`. Read `docs/PROJECT_STATE.md` first for the current state and
`docs/DESIGN_DECISIONS.md` (append-only) for why things are the way they are. This file records how to work here
quickly and cheaply. The user asked for it so that every new chat starts with these habits.

## Time and cost: the standing rules

- **Offline tests first.** Logic is tested by the suites in `scripts/agent` (sender, mailbox, router, choice prompt,
  user activity, watcher). Use a live run only for what an offline test cannot show (real UI, the real worker chat).
- **Do not re-run what just passed.** If a suite passed and the code it covers did not change, skip it. Run only the suite
  that covers the file you edited, then the full set once before a commit.
- **Batch live runs.** A live run sends turns to a Copilot worker chat, which reports credits per response (about 2 to
  12) and needs the person to keep their hands off the machine. Put several checks into ONE run and reuse a running
  mailbox listener for several messages. Before a live run, say what it will cost (turns) and what it will prove.
- **Make the first run count.** Print every result into the reply the first time. Two earlier runs lost their results
  because the harness assigned them to `$null` or a variable. The person usually sees only your reply text, not
  collapsed tool output, so write the exchange (what was sent, what came back) into the reply.
- **Stop at the first refusal.** If the sender says the window is on another virtual desktop, or the person is typing,
  stop the run and ask the person to switch back. Do not loop retrying for 90 seconds.
- **Read-only first.** A read-only look (inspect, `Get-CopilotChatTranscript.ps1`, the mailbox log, `-Status`) often answers
  a question without a worker turn.
- **Pick the right tool for a send.** One-shot task: `Send-CopilotPrompt.ps1` (the fast send). To-and-fro with a worker
  (phases, questions, adjusting): `Send-AgentMessage.ps1` with `-Bootstrap`, `-WaitReply`, and `-StopListening` at the end.
  The conservative (older) path is used only after a mechanical failure of the fast send. See Step 2b of
  `agent-orchestrator/SKILL.md`.
- **Do not re-measure known costs.** Sender stage times are recorded in `docs/DESIGN_DECISIONS.md` and the skill
  changelog. Use `-Trace` on the sender only when a stage looks slow again.

## Model choice

Before each task, say in one line which model suits it and whether to switch, so the person is aware. The test is cost,
not capability: if a cheaper model can do the task, SUGGEST the switch and wait for it. Say "no switch" only when the
current model is the right one (it is the cheapest that can do the task well). Do not skip a suggestion because the saving
looks small or because the current model could manage: the person decides. A session cannot switch its own model (the tool
refuses); ask the person to pick it in the model menu. A session you start with `start_session` can be given a model, and a
cheaper one suits a read-only job.

A long session also costs more per turn, because its whole history is read again each time. For work that does not need
the earlier conversation (a new feature, a separate review), suggest starting a new chat instead of continuing.

- **A cheaper, faster model (for example Haiku 5.5):** running the test suites, reading logs and transcripts, searching the
  repository, routine documentation edits (changelogs, indexes, state files), formatting and line-ending fixes.
- **The middle model (for example Sonnet 5.5):** writing or changing scripts and tests, reviewing another agent's
  feedback against the code, designing a small change, preparing a commit.
- **A stronger model (for example Opus 5.5 or Fable 5.2):** design with safety implications (the rules that stop UI
  automation from disturbing a person typing, the mailbox protocol and its privacy limits), finding the root cause of a
  failure nobody has explained, and reviewing a risky change before it ships.
- Switch back down after the harder part. Do not leave a strong model running a long test loop.

## Repository conventions that save rework

- **Versions.** Every change to a skill's content needs a new `CURRENT_SKILL_VERSION` in its `SKILL.md`, because the
  installer compares numbers and a machine already on that number will not update. Add one changelog entry, newest
  first. Run `scripts\Update-SkillsIndex.ps1`: the first sentence of the entry becomes `whatsNew` in
  `skills-index.json`, so keep it to one short sentence and start the next sentence with a capital letter, not a backtick.
- **Approval.** Commit, push and install only when the person says so, and keep `.github/copilot-instructions.md` out of
  commits (it is Bootstrap-generated and often modified for other reasons). The person's push can work when yours fails.
- **Line endings.** Files here are CRLF in the working tree (`core.autocrlf` is true). The Write tool produces LF:
  normalise a new or rewritten file to CRLF. Check with a count of lone LF before committing.
- **Tests that pin positions.** The sender test pins parameter positions. Append new parameters last and update the test.
  The input-block functions in `Select-ChoicePromptOption.ps1` must stay identical to the sender's (a test checks it).
- **Docs to touch for a skill change:** `SKILL.md` (version, changelog, usage), `skills-index.json` (generated),
  `docs/DESIGN_DECISIONS.md` (append), `docs/SCRIPTS.md` for a new script or test, `README.md` for a headline change,
  `docs/PROJECT_STATE.md` at the end of a working session.

## How to change things without wasting versions or trust

- **Combine small related changes into one version before committing.** The user prefers this. A version number is spent
  once it is pushed, so hold a tiny fix until it can ride with something else.
- **Measure with interleaved before/after runs.** Alternate old and new on the same chat, at least 4 pairs, and report the
  median. Report the quiet wait separately, because it depends on the person. The real speed gains came from removing
  repeated work (a window search costs 0.4 to 0.9 s each, the helper compile 1 s), never from dropping a guard. The cached
  sender in the first feedback was fast because it had no draft refusal, banner check or read-back.
- **Challenge feedback before applying it.** Ask the other agent for the exact tool output, and check each claim against
  the existing SKILL text and the code. Write a one-observation item as "observed once, in <environment>", or drop it.
  One item (a DPI factor) was withdrawn when real numbers contradicted it.
- **Mock-only tests miss the real shape of data.** The `-WaitReply` parsing bug passed offline because the tests fed message
  objects, not the transcript's real JSON. When a bug shows up live, add a test with the real format.
- **Never edit a script that a live worker or process is running.** Adding diagnostics to the mailbox listener while a
  worker was running it crashed that run and put an error in the worker's chat.
- **Tests must redirect logs and folders.** Set `AGENTUI_LOG_DIR` and `AGENTUI_MAILBOX_ROOT` in any test that logs or posts,
  or entries land in the real mailbox log. Delete probe folders under the temp folder afterwards.
- **Report honestly and verify.** After a push run `git fetch` and compare the heads (a push once failed after the words
  "pushed" had been said). Say plainly what was not tested live. Read the worker chat back instead of assuming. Stage files
  by explicit path, never `git add -A`.
- **Answer the person's mid-task question in your next reply.** Questions often arrive while a long run is going; a short
  answer should not wait for the run to finish.
## Windows PowerShell 5.1 pitfalls met here

- `ConvertFrom-Json` returns a JSON array as ONE object: `@(...)` around it gives a single item holding arrays.
  Unroll with `foreach`.
- Variable names are case-insensitive: a local `$status` overwrote the `[switch]$Status` parameter. A parameter called
  `$Input` is the pipeline variable and is never your value.
- Do not name a function after an alias (`Rp`, `rd`, `sc`, `ri` and others run the alias).
- `Write-Host` output leaks into stdout when a script is run with `-File`, and then breaks `-AsJson` parsing. Silence it
  with `6>$null` when calling a script whose output you parse.
- A relative path in PowerShell can differ from the .NET process directory: set `[IO.Directory]::SetCurrentDirectory`
  or use absolute paths before `[IO.File]::WriteAllText`. A wrong path once wrote an empty file over a script
  (restored from git).
- `$PSScriptRoot` is empty inside a `param()` default when a script with `[CmdletBinding()]` runs under `-File`. In a
  function created from a script block it is empty too: pass the folder in.
- `.Count` on a single result can be `$null`: wrap in `@(...)`. A `$null = Function` swallows what you meant to print.
- `Remove-Item` with a wildcard on some paths is refused: delete files individually with `[IO.File]::Delete`.
- Piping an installer or script to `Select -First N` can cut it short: write its output to a file instead.
- A worker chat's terminal does not see new folders under `%LOCALAPPDATA%` or `%APPDATA%` (it sees the temp folder,
  `C:\ProgramData` and `%USERPROFILE%\.copilot`): put anything shared with a worker under the temp folder.

## Safety rules that apply to every live run

- Never type, click or take the foreground while the person is using the machine: the sender waits for a quiet keyboard
  and hands the person's window and focus back. Do not bypass that (`-IgnoreUserActivity`) unless the person says nobody
  is there.
- A draft in a chat input is the person's or another agent's: do not overwrite it unless it is your own leftover test
  text, and clear it afterwards.
- Always end mailbox mode (`-StopListening`) when the to-and-fro is over, including on failure, so the worker's chat
  does not stay busy. `Send-AgentMessage.ps1 -Status` lists forgotten listeners.
- Never put message text in a log or in a reply unless the person needs it. The mailbox log records lengths and short
  hashes by default.
