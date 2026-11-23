# Send-CopilotPrompt.ps1: test cases

Script: `..\Send-CopilotPrompt.ps1`. Read [README.md](README.md) first. It types into a real chat, so use a window
and chat you own and a harmless prompt ("Test only, change nothing ..."). "Last result" is from 2026-10-31
unless stated.

| ID | Setup / action | Expected | Last result |
| --- | --- | --- | --- |
| S-01 | Chat tab showing, empty input: `-Hwnd <h> -Quiet -AsJson -Text '<prompt>'` | `Sent` true, `Attempts` 1, `InputText` empty (quiet), the prompt appears as a user message | Pass (many sends) |
| S-02 | `-TitleContains '<solution> - '` instead of `-Hwnd` | Window resolved by title; `-Hwnd` wins when both are given | Pass |
| S-03 | `-TitleContains` that matches no window | `Sent` false, error names the title, nothing typed | Pass (v6 testing) |
| S-04 | `-TitleContains` that matches several windows | `Sent` false, error lists the candidates, nothing typed | Pass (v6 testing) |
| S-05 | Stale `-Hwnd` (Visual Studio restarted) | `Sent` false, error says the window no longer exists, nothing typed | Pass (v6 testing) |
| S-06 | Neither `-Hwnd` nor `-TitleContains` | Throws "Pass -Hwnd or -TitleContains." | Pass (v6 testing) |
| S-07 | Chat tab hidden behind another tab (Git Changes) in the same pane | The script selects the `Chat` tab itself and sends | Pass 2026-10-31 (toolkit window, V2 said NotVisible before the send) and 2026-11-01 (send ok after the chat was shown) |
| S-08 | Chat tab selected but only the session list shows (no input) | Clicks "Create new session", waits up to 30 s for the input, sends | Pass 2026-11-01 (toolkit chat: Back to the session list, then send: the script created a session itself, the reply was S08) |
| S-09 | `-NewSession` | Creates a session first, waits up to 30 s for its input, sends | Pass 2026-11-01 (toolkit chat: new session, first attempt, reply S09) |
| S-10 | `-NoNavigate` with the chat input missing | `Sent` false, "The chat input is not showing (-NoNavigate was given). Nothing was typed." | Pass 2026-11-01 (toolkit chat: session list showing, Sent false, "The chat input is not showing (-NoNavigate was given). Nothing was typed.", the prompt never appeared) |
| S-11 | Workspace banner showing | `Sent` false, names the banner, nothing typed, unless `-IgnoreBanners` | Pass (v4 testing) |
| S-12 | Another app holds the foreground and focus stealing is blocked | `Sent` false, "Could not bring the target window to the foreground ... Nothing was typed" after retries; never types into the wrong window | Pass: seen repeatedly, nothing typed in any failure |
| S-15 | Same as S-12 on v15 | The foreground step is tried once more after a second; if it still fails, `Error` says to click the target Visual Studio window and run it again (nothing typed); no loop | Not run (needs another app holding the foreground; the wording is a code change only) |
| S-13 | Input already holds a draft, including whitespace-only text or with `-NewSession` | Refuses with `InputNotEmpty`, zero attempts and no input changes; `-OverwriteInput` permits replacement | Pass 2026-11-21: offline guards and overwrite bypass included in 67 assertions on the v26 draft; live replacement not run |
| S-14 | Prompt with a newline | Throws "-Text must be a single line" | Pass |
| S-16 | Prompt containing literal double quotes, quoted spaces, backslashes before quotes and trailing backslashes | Native arguments arrive unchanged; independent input read must match before Send | Pass 2026-11-21: offline native round trips and mocked read-back, included in 47 assertions on the v25 draft; live send not run |
| S-17 | CLI paste reports success but independent input text differs, is missing/ambiguous or lacks readable patterns | Never clicks Send; mismatch retries are bounded; unknown read fails explicitly | Pass 2026-11-21: offline mocked input reads and send gating, included in 47 assertions on the v25 draft; live send not run |
| S-18 | Input appears during navigation, or disappears before the final draft check | Rechecks before clearing; refuses a non-empty, missing or ambiguous input without replacing it | Pass 2026-11-21: offline recheck coverage included in 67 assertions on the v26 draft; live navigation not run |
| S-19 | Target window belongs to the calling script's own process chain, a different devenv process, a non-devenv process, a stale handle, or an unreadable window list/process chain | Own host is refused with `OwnHostWindow` before any input read; `-AllowOwnHost` bypasses; other processes pass; unreadable inputs fail closed | Pass 2026-11-21: 85 offline assertions plus a read-only real-window check (host refused, two other VS windows allowed); live send not run |
| S-20 | Mock ValuePattern and TextPattern with space, newline, zero-width/BOM-only text, placeholder-like text, attachment-like text, repeated supplementary code points and an unpaired surrogate; also disagreeing pattern reads and 40 distinct codes | Every non-empty draft is still refused; Error gives UTF-16 length, code-point count and at most 32 distinct codes/counts without draft text; ValuePattern still wins, empty reads pass, overwrite/rechecks remain unchanged | Pass 2026-11-23: 172 assertions in expanded offline sender suite on v31 draft; no live window read or send |
| S-21 | Mock a busy input-area Stop before paste and SteerButton after paste; matching/mismatching read-back, a corrected paste retry, NoSend and Quiet | Steer submits only after exact read-back; retries remain bounded; NoSend suppresses submission; Quiet suppresses successful text; existing parameter positions stay unchanged | Pass 2026-11-23: expanded v31 offline suite, 258 assertions total; no live script send |
| S-22 | Mock idle/unverified target, NewSession conflict, whitespace draft, final draft recheck, own-host target and lost input while Steer is requested; isolate actual navigation statements | Refuses before input actions; Steer never bypasses draft or own-host guards and never creates/navigates a chat; default Send navigation is unchanged | Pass 2026-11-23: offline preflight/recheck and navigation assertions; live navigation/banner checks not rerun |
| S-23 | Mock missing, disabled, off-screen, duplicate or wrong-name SteerButton, missing InvokePattern, busy lost after paste, visible SendButton, and failed CLI click containing prompt text | Sent=false with text-free availability/click reason; no Stop or Send click/fallback; verified unsent text remains a protected draft | Pass 2026-11-23: offline readiness and actual send-loop tests; live control transitions not rerun |
| S-24 | Input under WpfTextViewHost with CancelButton (Name Cancel), SteerButton and SendButton as direct GenericPane/Chat siblings; nested message-list button decoys, message-list input ancestor, ambiguous inputs and cyclic/missing ancestry; real UIA conditions | Scan Chat pane Children only, not host/message descendants; direct Cancel confirms busy, Steer is ready, Send refuses steering; historical controls cannot prove busy/readiness; ancestry remains bounded to 32 reads | Pass 2026-11-23: regression fails against old host-descendant scope, then passes corrected scope; 14 scoping assertions included in 266 total; corrected sender not rerun live |

## Steer evidence and offline scope

The user reported a successful live POC: while busy, empty input showed Stop and entered text
showed Steer, Name Steer, AutomationId SteerButton, Button with InvokePattern; SendButton was
absent. An AutomationId click cleared the input, added the text to the transcript, and the agent
answered and continued without stopping. That proves the reported POC, not this new sender's
live integration. This change was tested offline only, using mocked ancestors/button states and
the actual sender loop. Initial test-fixture failures (stale mock handle, null-versus-empty Error,
and comparing UIA's integer control-type ID to a ControlType object) were corrected; no production
behavior was changed to accommodate them. That earlier suite passed 258 assertions, but its
input-area mock did not mirror the actual sibling layout.

A follow-up user live test of the repo sender refused with SteerRequiresBusy while busy: the
input's WpfTextViewHost and the action buttons were siblings directly under GenericPane/Chat.
The old code searched the host's descendants and found no buttons. S-24 now models that layout,
fails at CancelButton discovery against the old sender, and passes after changing discovery to
the Chat pane's direct Children. The corrected suite passed 266 assertions. It also excludes
historical message-list controls and retains visibility, uniqueness, InvokePattern, draft,
read-back and no-Stop/no-Send-fallback checks. No corrected live send was performed here.

## Reported empty-input refusal: cause not established

A live run reportedly returned InputNotEmpty despite an independent UIA read returning zero
characters; OverwriteInput then worked. Offline review found that Get-ChatInputText returns
ValuePattern.Current.Value first, falling back to TextPattern.DocumentRange.GetText(-1), without
normalization. No provider capture establishes which pattern or characters caused that refusal.
Whitespace, zero-width characters, placeholders and attachment chips remain hypotheses, not facts.
S-20 uses synthetic strings only: it verifies diagnostics and unchanged protection, not a live
provider bug. No normalization switch is added without a concrete, testable cause.
