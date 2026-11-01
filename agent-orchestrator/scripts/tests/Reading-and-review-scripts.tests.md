# Read-CopilotReply, Get-CopilotChatTranscript, Invoke-CopilotReview, AgentCursor, Compare-RepoSnapshot: test cases

Read [README.md](README.md) first. "Last result" is from 2026-10-31 unless stated.

## Read-CopilotReply.ps1

| ID | Setup / action | Expected | Last result |
| --- | --- | --- | --- |
| R-01 | After a normal reply: `-Hwnd <h> -AfterPrompt '<phrase from the prompt>'` | `PromptFound` true, `Reply` holds only what follows the prompt, `Footer` set, `Busy` false | Pass |
| R-02 | Long chat (virtualized list) with the reply below the visible area | Scrolls to the end first; `ScrolledToEnd` true, `ScrollPercent` 100; the reply is returned (an unscrolled read looked like "no reply yet") | Pass |
| R-03 | Reply is exactly `NO ISSUES REMAIN.` | `IsClean` true; false when numbered findings follow or the reply is truncated | Pass (review runs) |
| R-04 | Prompt phrase not in the chat | `PromptFound` false | Pass: seen when a card was open and my prompt was not shown |
| R-05 | Reply still being written | `Busy` true | Pass |
| R-06 | A question or approval at the end of the reply | Not detected here: use `Watch-CopilotChatV2.ps1` (`AwaitingReply`) | Known gap (the plan to add `-IncludePrompt` was replaced by V2's detail step) |
| R-07 | REGRESSION: a long reply, so the prompt message is not rendered at the bottom of the chat list. `-AfterPrompt '<phrase>'` | `PromptFound` true, `ScrolledUpToFindPrompt` true, `PartialReply` true (messages rendered at neither scroll position are missing), the list is back at the bottom afterwards. Before the fix: `PromptFound` false and an empty `Reply` | Pass 2026-10-31 (toolkit chat, prompt far above newer messages: found after scrolling up, 10 messages merged, 58 s) |

## Get-CopilotChatTranscript.ps1

| ID | Setup / action | Expected | Last result |
| --- | --- | --- | --- |
| T-01 | `-Hwnd <h>` on a chat | One row per rendered message: `Index`, `IsFooter`, `Text`; only rendered messages (virtualized) | Pass; with a card open it returned only the card's title as the last row |
| T-02 | Chat scrolled up | Returns the rendered window only; scroll first (see Read-CopilotReply) | Known behavior |

## Invoke-CopilotReview.ps1

| ID | Setup / action | Expected | Last result |
| --- | --- | --- | --- |
| IR-01 | `-TitleContains '<solution> - ' -Review -Prompt '<what to review>'` on an idle chat | `Status` Done, `IsClean` true or the reply, a unique reference tag sent with the prompt, one beep | Pass: 84 s, after the V1/V2 rename (`-Poller V2`) |
| IR-02 | Chat tab not showing, or the input holds a draft | `Status` NotSent, nothing typed, draft kept (`-OverwriteInput` overrides) | Pass 2026-11-01 after the fix (NotSent / InputNotEmpty, the draft was still in the input afterwards). Before the fix the guard never fired: see Bugs found |
| IR-03 | Copilot raises a card or permission prompt | `Status` NeedsUser with the question and options; never answers it | Pass 2026-11-01 (NeedsUser with Question and Options; the script answered nothing) |
| IR-04 | `-Poller V1` | Same flow with the full-tree watcher | Pass 2026-11-01 (Done, IsClean true). The first run returned NoReply (ReadNotConfirmed), see IR-09 |
| IR-05 | Wait exceeds `-TimeoutSeconds` | `Status` Timeout | Pass 2026-11-01 (a heavy task with TimeoutSeconds 60: Timeout after 65 s; with a light prompt the reply finished first and the result was Done, which is not a failure) |
| IR-06 | After a Watch V2 change | IR-01 still passes (it calls `Watch-CopilotChatV2.ps1` and, on Pending, V1) | Pass 2026-10-31 after the V2 detail change (toolkit chat, 66 s; one foreground-activation retry, recovered). The wrapper now passes `-NoDetail` to V2 because it fetches prompt details itself |
| IR-07 | Another chat becomes visible while waiting (click New chat) | `Status` NoReply with a ChatSwitched message; nothing more sent | Pass 2026-11-01 (NoReply with "ChatSwitched: another chat became the visible one while waiting"; clicked Create new session 14 s into a long task) |
| IR-02b | IR-02 again with `-OverwriteInput` | `Status` Done (the draft is replaced) | Pass 2026-11-01 |
| IR-08 | REGRESSION: the reference tag appended to the prompt | The tag cannot be mistaken for a git ref (letters only, `msg-xxxxxxxx`) and Copilot asks nothing about it | Pass 2026-11-01 after the fix. Before: the 8-digit hex tag `ref a5dfd57b` made Copilot ask which git revision to summarize (a question card, NeedsUser) |
| IR-09 | REGRESSION: a complete reply whose list scroll position stays short of the end (very tall last message) | `Status` Done with a caveat in `Reason` once the footer was read; never ReadNotConfirmed for a complete reply | Code path fixed 2026-11-01 (`Read-CopilotReply` also reports `NearEnd`); the caveat path itself was not re-observed after the fix, a plain review returned Done with the end confirmed (19 s) |

## AgentCursor.ps1

See [AgentCursor.tests.md](../../../ui-interaction/scripts/tests/AgentCursor.tests.md) for its test cases.

## Compare-RepoSnapshot.ps1

See [Compare-RepoSnapshot.tests.md](Compare-RepoSnapshot.tests.md) for its test cases.

## Bugs these cases found (keep as regression tests)

1. 2026-11-01: the wrapper's "input is empty" check looked for an element named `Ask Copilot`, which is the input box itself and exists with or without text, so a draft was silently overwritten (IR-02). Now it reads the Send button: disabled when the input is empty, enabled when it holds text. `get-text` cannot be used: it returns the element's name, not its content.
2. 2026-11-01: the wrapper's reference tag was 8 hex digits, which Copilot read as a git commit and asked about (IR-08, found through IR-07). It is now letters only.
3. 2026-11-01: `ReadNotConfirmed` was returned for complete replies when the list scroll position stopped short of 100 percent (98 percent seen; a very tall last message keeps it lower) (IR-04 and IR-09). `Read-CopilotReply` now reports `NearEnd` and the wrapper returns Done with a caveat when the footer was read.
