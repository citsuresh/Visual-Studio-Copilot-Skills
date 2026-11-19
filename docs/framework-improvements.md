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
