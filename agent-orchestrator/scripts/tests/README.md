# Test cases for the agent-orchestrator scripts

These scripts drive a real Visual Studio Copilot chat through UI Automation, so they cannot run as unit tests.
Each `<Script>.tests.md` lists the scenarios to run by hand (or by an orchestrating agent) when the script is
changed, when a new version of it is written, or after a Visual Studio / Copilot update. Read the file for the
script you are changing BEFORE editing it, and update it AFTER: a scenario that found a bug stays in the list as
a regression test.

| Script | Test cases |
| --- | --- |
| `Watch-CopilotChatV2.ps1` (default watcher) | [Watch-CopilotChatV2.tests.md](Watch-CopilotChatV2.tests.md) |
| `Watch-CopilotChatV1.ps1` (full-tree watcher) | [Watch-CopilotChatV1.tests.md](Watch-CopilotChatV1.tests.md) |
| `Send-CopilotPrompt.ps1` | [Send-CopilotPrompt.tests.md](Send-CopilotPrompt.tests.md) |
| `Select-ChoicePromptOption.ps1` | [Select-ChoicePromptOption.tests.md](Select-ChoicePromptOption.tests.md) |
| `Read-CopilotReply.ps1`, `Get-CopilotChatTranscript.ps1`, `Invoke-CopilotReview.ps1` | [Reading-and-review-scripts.tests.md](Reading-and-review-scripts.tests.md) |
| `AgentCursor.ps1` (owned by `ui-interaction`) | [AgentCursor.tests.md](../../../ui-interaction/scripts/tests/AgentCursor.tests.md) |
| `Compare-RepoSnapshot.ps1` | [Compare-RepoSnapshot.tests.md](Compare-RepoSnapshot.tests.md) |
| Cost of supervising a chat (measurements, not test cases) | [Monitoring-cost.md](Monitoring-cost.md) |

## Format of a test case

`ID | setup / action | expected | last result`. The last result says WHEN and WHERE it was run (date, which
window) or `not run` with the reason. Never write "pass" for something that was not run.

## Rules for running them

- Use a window whose chat you own. Never answer a card, prompt or question that you did not create: a card
  that appears in someone else's chat belongs to them.
- Test prompts start with "Test only, change nothing" and ask for one exact reply, so a failed test costs
  one cheap Copilot turn and changes no files.
- Copilot decides how a question card is worded. Ask for a card, then read the options it actually shows
  (`Select-ChoicePromptOption.ps1` with no `-Option` lists them) instead of assuming your wording.
- Run long waits in the background (or with a timeout) and kill anything that runs well past its expected time.
- Run `Watch-CopilotChatV2.ps1 -CrossCheck` after any change to how it looks for things: `Mismatches` must be 0
  (one mismatch on the poll where a card first appears is a timing race between the two probes, not a bug).

## Scenarios that need setup you cannot always get

- Tool permission prompts ("Do you allow Copilot to ...?"): need Copilot's tool approvals set to ask. A prompt appeared for listing a folder outside the workspace once approvals were set to ask; reads there and a plain `echo` were auto-approved before that. Choosing "Always allow" changes a lasting setting: do it only when the user asks.
- Workspace banners (folder mismatch / untrusted folder): need a window whose open folder differs from the session's. Run once on 2026-11-01 with a mismatch banner; the untrusted-folder banner has not been run.
- A chat list scrolled up while a card is open.
Mark these `not run` with the reason until someone sets them up.
