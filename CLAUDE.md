# Working in this repository (for Claude Code sessions)

This repository holds the Visual Studio Copilot skills (`agent-orchestrator`, `ui-interaction`, and others), their
scripts and the offline tests in `scripts/agent`. Read `docs/PROJECT_STATE.md` first for the current state and
`docs/DESIGN_DECISIONS.md` (append-only) for why things are the way they are. This file records how to work here
quickly and cheaply. The user asked for it so that every new chat starts with these habits.

## Time and cost: what is specific here

- **Offline tests first.** Logic is tested by the suites in `scripts/agent` (sender, mailbox, router, choice prompt,
  user activity, watcher). Run only the suite that covers the file you edited, then the full set once before a commit.
- **Live runs.** A live run sends turns to a Copilot worker chat, which reports credits per response (about 2 to 12) and needs
  the person to keep their hands off the machine. Reuse a running mailbox listener for several messages.
- **Read-only first.** `Get-CopilotChatTranscript.ps1`, the mailbox log and `-Status` often answer a question without a worker
  turn.
- **Pick the right tool for a send.** One-shot task: `Send-CopilotPrompt.ps1` (the fast send). To-and-fro with a worker
  (phases, questions, adjusting): `Send-AgentMessage.ps1` with `-Bootstrap`, `-WaitReply`, and `-StopListening` at the end.
  The conservative (older) path is used only after a mechanical failure of the fast send. See Step 2b of
  `agent-orchestrator/SKILL.md`.
- **Do not re-measure known costs.** Sender stage times are recorded in `docs/DESIGN_DECISIONS.md` and the skill
  changelog. Use `-Trace` on the sender only when a stage looks slow again.

## Model choice: what is specific here

- **A strong model** for design that touches the rules which stop UI automation from disturbing a person typing, and the mailbox
  protocol and its privacy limits, and for reviewing a risky change before it ships.
- **A cheap model** for running the `scripts/agent` suites, reading the mailbox log and transcripts, and routine edits to the
  changelog, index and state files.

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
- **Where a worker can see files.** A worker chat's terminal does not see new folders under `%LOCALAPPDATA%` or `%APPDATA%` (it sees the temp
  folder, `C:\ProgramData` and `%USERPROFILE%\.copilot`): put anything shared with a worker under the temp folder.

## How to change things without wasting versions or trust

- **Combine small related changes into one version before committing.** The user prefers this. A version number is spent
  once it is pushed, so hold a tiny fix until it can ride with something else.
- **Measure with interleaved before/after runs.** Alternate old and new on the same chat, at least 4 pairs, and report the
  median. Report the quiet wait separately, because it depends on the person. The real speed gains came from removing
  repeated work (a window search costs 0.4 to 0.9 s each, the helper compile 1 s), never from dropping a guard. The cached
  sender in the first feedback was fast because it had no draft refusal, banner check or read-back.
- **Tests must redirect logs and folders.** Set `AGENTUI_LOG_DIR` and `AGENTUI_MAILBOX_ROOT` in any test that logs or posts,
  or entries land in the real mailbox log. Delete probe folders under the temp folder afterwards.
- **Lessons from this repo.** The `-WaitReply` parsing bug passed offline because the tests fed message objects, not the transcript's
  real JSON. Adding diagnostics to the mailbox listener while a worker ran it crashed that run. Read the worker chat back instead
  of assuming what it did.

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
- Stop at the first refusal (the window is on another virtual desktop, or the person is typing): ask the person to switch back or wait. Do not loop retrying for 90 seconds.
