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
| S-13 | Input already holds a draft | Script clears the input first, destroying the draft: callers must check (Invoke-CopilotReview does) | Known behavior; guarded in the wrapper |
| S-14 | Prompt with a newline | Throws "-Text must be a single line" | Pass |
