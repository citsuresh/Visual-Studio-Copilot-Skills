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
| V2-10 | Chat stays busy past `-TimeoutSeconds` | `State` Timeout, returns within a few seconds of the limit; `Note` reports no terminal state and observed busy/footer/quiet facts | Historical live state/timing pass (30 s, 90 s runs); updated note passes offline 2026-11-22, not rerun live |
| V2-11 | Any end state with `-NoDetail` | No Question/Options/AwaitingReply (null), returns in about 1 s, no V1 run | Pass |
| V2-12 | Idle or Pending with `-ExePath C:\nope\agentdebug-ui.exe` | State still correct, `DetailNote` explains the missing exe, no exception | Pass |
| V2-13 | Idle chat with `-CrossCheck` | `Mismatches` 0 | Not run on a clean idle chat (every idle chat probed was NotVisible or gone); card cases give 0 |
| V2-14 | Probe cost on a long chat, 10+ polls | median probe well under 1 s | Pass: median 164 ms, max 1.5 s (8 polls, toolkit chat) |
| V2-15 | Wait ends | one beep (880 Hz); `-NoBeep` silent; the beep comes before the detail step | Not verified by ear; code path only |
| V2-16 | `-RequireBusyFirst` right after a send | Idle not reported until the stop button was seen or `-StartGraceSeconds` passed | Pass in all send-then-wait runs |
| V2-17 | Light probe says Idle but the full tree has an open prompt | `Upgraded` true, `State` Pending, `Note` says the light probe missed it | Pass 2026-11-01, by accident of the trust card: the light probe missed the open card, the detail step found it, result Pending, PermissionPrompt, `Upgraded` true, note says the light probe missed it. This is the first time the upgrade path ran; it was the trust card, not another unknown shape |
| V2-18 | Tool permission prompt open | Pending, `PromptKind` PermissionPrompt (`Allow this time` found in the input area or last message) | Pass 2026-11-01 (toolkit window, twice: Pending, PermissionPrompt, Options Allow this time / Deny from the detail step). The permission prompt appeared for a read outside the workspace, once the user's approvals were set to ask |
| V2-18b | Permission prompt whose button is a plain `Allow` next to `Deny` | Pending, `PromptKind` PermissionPrompt, even while the stop button is visible; a lone `Allow`, an off-screen pair or a plain Cancel button does not make Pending | Offline mock pass (`scripts\agent\Test-WatcherProgress.ps1`); not yet seen on a live prompt |
| V2-19 | Card open while the list is scrolled up more than about 10 % from the end | Known limit: not detected while polling (Timeout), detail step cannot help because it never runs | Pass 2026-11-01 (toolkit window; a Yes/No card open, list scrolled up to about 34 %): V2 returned Timeout ("Still busy after 45 seconds") and detected the card (Pending, ChoiceCard) once the list was scrolled back to the end. A first attempt where the scroll did not move was discarded. Scrolling with ScrollPattern.Scroll(LargeDecrement) works; SetScrollPercent did not move the list |
| V2-20 | Workspace-mismatch / trust banner showing | `Banners` lists it with Id, Text, Buttons (from the detail step) | Pass 2026-11-01 (skills window, session folder differs from the open folder): `Banners` = HarnessWorkspaceMismatchBanner with its text and buttons `Update working directory` / `Close message`; State Idle; nothing clicked |
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
| V2-23 | `-TitleContains` that matches no window, and with neither `-Hwnd` nor `-TitleContains` | Throws "No window title contains '...'. Nothing was touched." / "Pass -Hwnd or -TitleContains." | Pass 2026-11-02 (temp copy of v15) |
| V2-24 | `-TitleContains` that matches several windows | Throws the candidate list | Pass 2026-11-02 for the shared helper; not run through V2 |
| V2-25 | `-TitleContains '<solution> - '` against a live chat, and `-Hwnd` given as well | Same result as with the hwnd; `-Hwnd` wins when both are given | Not run (needs a live chat) |

## Already-idle timeout regression (2026-11-22)

User-reported live diagnosis, not rerun here: an idle footer, no stop button and no prompt gave
Timeout at 15 s with all four probes showing busy=0 and footerAtEnd=1; V1 simultaneously said Idle.
A 45 s wait returned Idle at 21 s through the quiet rule. The old timeout note incorrectly claimed busy.

Run the repository's `scripts\agent\Test-WatcherProgress.ps1 -WatcherPath <V2-source-or-draft>`
offline. It extracts the actual polling loop, mocks flag sequences, window existence and V1 detail,
and advances a virtual clock instead of sleeping. These tests do not exercise live UIA discovery.

| ID | Setup / action | Expected | Last result |
| --- | --- | --- | --- |
| V2-26 | Already-idle footer on consecutive polls, no stop/card/permission; no `RequireBusyFirst`; timeout 15 s, quiet 20 s, interval 5 s. Also timeout 10 s, quiet 300 s, interval 2 s | Idle on poll 2 at 5 s / 2 s, BusySeen false; no detail with NoDetail | Draft offline pass 2026-11-22; not run live |
| V2-27 | Footer, no footer, footer, no footer before timeout | No fast Idle; Timeout on poll 4, note says busy seen no, footer at end no, quiet countdown 15 of 20 | Draft offline pass 2026-11-22 |
| V2-28 | Footer, failed probe, footer, footer | Failed probe resets streak; Idle only after two fresh successful polls (11 s, 3 successful probes, 4 attempts) | Draft offline pass 2026-11-22 |
| V2-29 | Old footer on every poll with RequireBusyFirst; timeout 15 s, grace 30 s, quiet 20 s | Timeout, BusySeen false, footer at end yes, quiet countdown 0 of 20; no fast Idle | Draft offline pass 2026-11-22 |
| V2-30 | Same gated footer with timeout 60 s; also grace 0 with timeout 15 s | Grace 30 plus quiet 20 still gives Idle at 50 s, not at grace expiry; zero grace still waits quiet and times out at 15 s | Draft offline pass 2026-11-22 |
| V2-31 | No footer and no prompt throughout; separately busy then quiet without footer | Existing no-footer quiet fallback gives Idle at 20 s; busy then quiet resets countdown (10 of 20 at 15 s timeout), BusySeen true | Draft offline pass 2026-11-22 |
| V2-32 | Busy then footer with RequireBusyFirst; separately footer, busy+footer, footer; persistent busy+footer | Existing busy-to-footer Idle remains immediate; stop button blocks fast Idle; persistent busy times out with quiet countdown 0 | Draft offline pass 2026-11-22 |
| V2-33 | Footer followed by footer+card, footer+permission, or hidden chat; separately busy then changed title without footer | Pending ChoiceCard / PermissionPrompt wins over second footer; hidden chat gives NotVisible; existing ChatSwitched remains | Draft offline pass 2026-11-22 |
| V2-34 | Probe fails at timeout; separately three consecutive failed probes | Timeout note names latest probe failure, never claims busy; three failures still give ProbeError | Draft offline pass 2026-11-22 |
| V2-35 | Two idle footer probes, detail enabled; mocked V1 finds a permission prompt | Exactly one detail call; Pending, PermissionPrompt, Upgraded true | Draft offline pass 2026-11-22; real detail/UIA not exercised |

Any live check for this change must be read-only against an already-idle chat: run the watcher
with `-NoBeep` and optionally `-NoDetail` / `-CrossCheck`. Do not send prompts, type, click, scroll
or activate a window to arrange these cases. Busy/prompt/switch cases above are offline only here.

## Procedure after changing V2

Run V2-01, V2-02, V2-04, V2-05, V2-08, V2-09, V2-11, V2-12 and V2-14 at least. For a change to what the light
probe looks at, also V2-06 and V2-07, and always with `-CrossCheck` (`Mismatches` 0).
For this read-only idle-timeout change, run V2-26 through V2-35 offline; the restriction above takes
precedence over historical live setup procedures. Leave unrun live cases explicitly unverified.
