# Framework improvement candidates

Reported patterns from hardware-test debugging; not independently confirmed against framework
source in this skills repository. These are investigation candidates, not implemented fixes.
Changing framework behavior requires a separate explicit request and target-repository review.

| Candidate | Reported risk | Verification before proposing a change |
| --- | --- | --- |
| Timeout exception loses its contract | A transport timeout is re-wrapped in a generic exception, bypassing the caller's returned-timeout-code retry path. A trial retry matches message text only. | Trace the exception and return-code paths; test typed timeout preservation, retry limits and non-timeout failures. Do not extend message-text matching as a substitute for a stable error contract. |
| Configuration-source mismatch | The repository timeout is 80 s while a machine-local copy uses 120 s; reading the wrong copy misstates the effective wait. | Identify the configuration actually selected by the runner, its path and effective value, including overrides. Do not change either value merely to make the copies agree. |
| Setter silently changes send mode | A setter changes later sends from direct mode to list mode without making that side effect clear in its name. | Trace all callers and state lifetime; assess explicit mode selection or naming/documentation while preserving existing send ordering. |
| Cleanup masks failure and leaves device secure | A cleanup block dereferences null after a radio timeout, can mask the original exception, and may leave the device in a secure state. | Exercise failure before initialization; preserve the primary failure, report cleanup failure separately, and independently verify the intended final security state. Never treat a null guard alone as successful cleanup. |

## AgentDebugToolkit UI automation candidates (2026-11-25)

Separate from the table above (a different tool). Reported from a cross-chat sender test on one
machine, one remote session, Windows PowerShell 5.1, toolkit build `66ecbfc`. Items 1 and 4 also rest
on reading the toolkit source and `docs/CLI_CONTRACT.md`. None is reproduced yet and none is
implemented; the toolkit's own `docs/KNOWN_OPEN_FINDINGS.md` is user-curated and was not edited.

| Candidate | Reported risk | Verification before proposing a change |
| --- | --- | --- |
| Selector click has no screen-bounds check | Windows clamps `SetCursorPos` to the screen, and no screen or work-area check was found in the click path, so an element centred outside the screen is likely clicked at the screen edge (possibly the taskbar). The pointer was seen ending near the bottom row; whether a click was dispatched is unverified. Coordinate clicks check the window rectangle only. | Reproduce with a throwaway window pushed partly off-screen; record `get-cursor-pos` and which window receives the click. Decide the error code and whether `--allowOutsideWindow` should cover it before changing anything. |
| `foreground-activation-failed` says nothing about an off-screen target | An input below the screen (y=1520 on a 1080-pixel screen) still reported `IsOffscreen: false` and the verb failed only with the generic foreground message. `foregroundDiagnostics` covers foreground window, minimized state and session, not the target's position against the monitor. The raw failure output was not retained, so whether the diagnostics appeared is unknown. | Capture the raw failure JSON on the installed build. If diagnostics are present, consider adding the target rectangle and monitor working area as read-only facts; keep existing codes and messages. |
| No verb to move or resize a window | The caller recovered with its own `SetWindowPos` (about 1.2 s, no mouse). The toolkit only restores a minimized window (`ShowWindow`). | Decide whether a mutating window verb fits a toolkit that only performs actions. If so, require an explicit `--hwnd`, validate bounds, read the rectangle back, and test minimized, maximized and DPI cases. |
| `boundingRect` missing from `ambiguous-match` candidates and `find-all` elements | A caller cannot choose between same-named controls by position. `inspect` returns `boundingRect`; per `CLI_CONTRACT.md` the ambiguity candidates and `find-all` elements list only name, automationId, controlType and className. | Confirm in source and live output. Add the field optionally, keeping existing fields and the omit-when-non-finite rule; test with a hidden and a clipped control. |
