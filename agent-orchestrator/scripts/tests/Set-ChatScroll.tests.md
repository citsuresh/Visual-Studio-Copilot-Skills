# Set-ChatScroll.ps1 and Resolve-CopilotWindow.ps1: test cases

Scripts: `..\Set-ChatScroll.ps1`, `..\Resolve-CopilotWindow.ps1`. Read [README.md](README.md) first. Set-ChatScroll changes
only the chat list's scroll position. "Last result" is from 2026-11-02 unless stated.

| ID | Setup / action | Expected | Last result |
| --- | --- | --- | --- |
| SC-01 | Long chat, `-Hwnd <h> -Direction Up -Pages 2` | `PercentAfter` lower than `PercentBefore`, `Moved` true, `Steps` 2 | Partial 2026-11-02 (skills window, `-Pages 1`): `Moved` true, 100 to 73.3. A run by Copilot a few minutes earlier, while its reply was being written, reported 100 to 100, `Moved` false: the list may jump back to the end while the chat updates. Repeat with the chat idle |
| SC-02 | After SC-01, `-Direction Down -ToEnd` | Pages until the percent stops changing; `PercentAfter` at or near 100, `Moved` true | Partial 2026-11-02: `Success` true, but `PercentBefore` was already 100 (the list had returned to the end by itself after SC-01), so `Moved` false. Needs a start well above the end |
| SC-03 | List already at its end, `-Direction Down -Pages 1` | `Success` true, `Moved` false (a scroll that did nothing is reported, not hidden) | Not run |
| SC-04 | Window without the chat list (chat tab hidden) | `Success` false, "No chat list (AutomationId 'session') ...", nothing changed | Not run |
| SC-05 | Compare with `scroll-container --verticalPercent 100` on a chat where `SetScrollPercent` did not move the list | `Set-ChatScroll` moves it (the reason the script exists) | Observed in live testing before this version; not re-run against the script |
| RW-01 | `Resolve-CopilotWindow.ps1 -TitleContains` text that matches no window | `Hwnd` empty, `Error` "No window title contains '...'. Nothing was touched." | Pass |
| RW-02 | `-TitleContains ' '` (matches many windows) | `Hwnd` empty, `Error` lists each `Hwnd 'Title'` | Pass |
| RW-03 | `-TitleContains '<solution> - '` matching exactly one window | `Hwnd` set (for example `0x1310E4`), `Error` empty | Not run |
