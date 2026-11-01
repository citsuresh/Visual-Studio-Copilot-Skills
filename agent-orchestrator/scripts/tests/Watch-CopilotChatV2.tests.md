# Watch-CopilotChatV2.ps1: test cases

Script: `..\Watch-CopilotChatV2.ps1` (the default watcher). Read [README.md](README.md) first for the rules.

Setup used so far: a Visual Studio window with a Copilot chat in Agent mode (window titled for the
AgentDebugToolkit solution, hwnd changes per start; look it up with `list-windows --titleContains`).
Send prompts with `Send-CopilotPrompt.ps1 -Hwnd <h> -Quiet -AsJson -Text '<prompt>'`, then run the watcher as
shown. "Last result" is from 2026-10-31 unless stated.

## Prompts that produce each scenario

| Scenario | Prompt text (single line) |
| --- | --- |
| Plain-text question | `Test only, change nothing and run no tools: reply with exactly this one sentence and nothing else: Shall I proceed with the cleanup? Please approve or decline.` |
| Normal reply | `Test only, change nothing and run no tools: reply with exactly the single word DONE.` |
| Choice card | `Test only, change nothing: use your question card tool (a choice card, not plain text) to ask "Pick one" with options Alpha and Beta. Then reply with only the chosen option.` |
| Two-question card | `Test only, change nothing and run no other tools: use your question card tool ONCE with TWO questions in the same card: ...` |
| Free-text card | `Test only, change nothing and run no other tools: use your question card tool ONCE to ask the free-text question "Type any word" with NO options (a text box only). ...` |

Copilot words the card itself (it showed "Option A / Option B" and "Which response would you like? Yes / No"
for prompts that asked for other labels). Read the real options before answering.

## Cases

| ID | Setup / action | Expected | Last result |
| --- | --- | --- | --- |
| V2-01 | Choice card open. `Watch-CopilotChatV2.ps1 -Hwnd <h> -RequireBusyFirst -CrossCheck` | `State` Pending, `PromptKind` ChoicePrompt, `Question` and `Options` filled, `Mismatches` 0 | Pass (skills chat and toolkit chat) |
| V2-02 | Two-question card open | Pending, `MorePages` true; after answering page 1 with `Select-ChoicePromptOption.ps1`, `NextQuestion` names page 2 | Pass |
| V2-03 | Free-text card open | Pending; same fields as V1 returns for it (this Copilot version showed radio options "Enter text" / "Skip") | Pass |
| V2-04 | Plain-text question reply (see prompt table) | `State` Idle, `AwaitingReply` true, `LastMessageTail` holds the sentence, `Note` says Idle is not done | Pass |
| V2-05 | Normal one-word reply | Idle, `AwaitingReply` false, `LastMessage` DONE, `CompletionFooter` set | Pass |
| V2-06 | REGRESSION: card is the last real message but the list is only about 98 % scrolled (card partly out of view) | Pending. Before the fix both the light probe and `Test-ListAtEnd` said "not at end" and V2 polled until Timeout (30 s of `-CrossCheck` showed 7 of 7 mismatches) | Pass after the fix (toolkit chat) |
| V2-07 | REGRESSION: the list ends with an empty view-model placeholder item (`Microsoft.VisualStudio...`) after the card or footer | Card still found; a finished reply's footer still found (V2 skips trailing placeholders like V1) | Card: pass after the fix (skills chat). Footer behind a placeholder: not separately reproduced |
| V2-08 | Chat tab not active (Git Changes tab on top in the same pane) | `State` NotVisible, immediately | Pass (AgentDebugToolkit window); `-CrossCheck` agreed |
| V2-09 | `-Hwnd 0x1` (no such window) | `State` WindowGone within a second | Pass |
| V2-10 | Chat stays busy past `-TimeoutSeconds` | `State` Timeout, returns within a few seconds of the limit, `Note` says still busy | Pass (30 s, 90 s runs) |
| V2-11 | Any end state with `-NoDetail` | No Question/Options/AwaitingReply (null), returns in about 1 s, no V1 run | Pass |
| V2-12 | Idle or Pending with `-ExePath C:\nope\agentdebug-ui.exe` | State still correct, `DetailNote` explains the missing exe, no exception | Pass |
| V2-13 | Idle chat with `-CrossCheck` | `Mismatches` 0 | Not run on a clean idle chat (every idle chat probed was NotVisible or gone); card cases give 0 |
| V2-14 | Probe cost on a long chat, 10+ polls | median probe well under 1 s | Pass: median 164 ms, max 1.5 s (8 polls, toolkit chat) |
| V2-15 | Wait ends | one beep (880 Hz); `-NoBeep` silent; the beep comes before the detail step | Not verified by ear; code path only |
| V2-16 | `-RequireBusyFirst` right after a send | Idle not reported until the stop button was seen or `-StartGraceSeconds` passed | Pass in all send-then-wait runs |
| V2-17 | Light probe says Idle but the full tree has an open prompt | `Upgraded` true, `State` Pending, `Note` says the light probe missed it | Not run (needs a prompt shape V2 cannot see; the Upgraded code path is untested) |
| V2-18 | Tool permission prompt open | Pending, `PromptKind` PermissionPrompt (`Allow this time` found in the input area or last message) | Pass 2026-11-01 (toolkit window, twice: Pending, PermissionPrompt, Options Allow this time / Deny from the detail step). The permission prompt appeared for a read outside the workspace, once the user's approvals were set to ask |
| V2-19 | Card open while the list is scrolled up more than about 10 % from the end | Known limit: not detected while polling (Timeout), detail step cannot help because it never runs | Not run; documented as a con in the script header |
| V2-20 | Workspace-mismatch / trust banner showing | `Banners` lists it with Id, Text, Buttons (from the detail step) | Not run: needs a mismatched window |
| V2-21 | A task is running (stop button showing), then someone clicks "New chat" (the visible chat changes). Watch with `-TraceFile`. | `State` ChatSwitched, `Note` says the watched chat may still be working; the trace shows the title changing and busy dropping | Pass 2026-10-31 (toolkit chat; clicked Create new session at t=12 s; ChatSwitched at 17 s instead of a false Idle) |
| V2-22 | REGRESSION for V2-21: start the watcher, then send the first message of a NEW session (the title changes from "New session..." to the prompt text while the chat is busy) | No ChatSwitched: the title change while busy is followed silently; the wait ends Idle through the completion footer | Pass 2026-10-31 (24 s, Idle) |
| V2-23 | The session title element is missing or two chats share a title | Known limit: no ChatSwitched, a switch can look like a false Idle; callers must confirm with `Read-CopilotReply.ps1` | Not run |
| V2-24 | A finished reply whose session title changes after the footer (Copilot renames the session) | No ChatSwitched (a footer at the end of the list means the reply finished) | Not run live; covered by the rule in the code |

## Bugs these cases found (keep as regression tests)

1. 2026-10-31: V2 never looked inside the message list, but a question card is the list's last message, so it
   reported "busy" until Timeout (V2-01, V2-06). Fixed by searching the last real messages.
2. 2026-10-31: the list ends with an empty placeholder item, so "the last item" was not the card (V2-07).
   Fixed by skipping `Microsoft.VisualStudio...` items.
3. 2026-10-31: the list's scroll percentage stops short of 100 (98.5 seen), so the strict "at end" test failed
   (V2-06). Fixed by searching while the list is within 10 % of its end, keeping the footer test strict.
4. 2026-10-31: the first audit compared V1's fields with V2's, not what each could SEE. Always run
   `-CrossCheck` against a real card (V2-01) before calling V2 equivalent to V1.
5. 2026-10-31: the watcher follows whichever chat is visible, so clicking "New chat" mid-task ended with a false Idle while the first chat kept working (found by the supervising chat in VsChatHistoryToolkit). Fixed with a ChatSwitched state keyed on the session title in the pane header; fire only when the title changed, the stop button is gone and there is no footer (V2-21, V2-22).

## Procedure after changing V2

Run V2-01, V2-02, V2-04, V2-05, V2-08, V2-09, V2-11, V2-12 and V2-14 at least. For a change to what the light
probe looks at, also V2-06 and V2-07, and always with `-CrossCheck` (`Mismatches` 0).
