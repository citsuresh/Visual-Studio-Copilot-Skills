# Feedback-session acceptance cases

Use a disposable remote/test setup and approved non-hardware controls. Never disconnect a
working RDP session, alter registry/security policy, or resend device commands to run a case.
Record remote client state separately from the agent process's observed session state.

| ID | Setup / action | Expected result | Last result |
| --- | --- | --- | --- |
| RDP-01 | Approved remote setup with restored client; one requested non-hardware UI action | Verify the actual action or report foreground failure with observational diagnostics; no cause inference | Not run: disposable remote setup required |
| RDP-02 | User minimizes the client; repeat the same approved operation once | Record success/failure and known/unknown observations; no activation loop or inferred client state | Not run: disruptive client-state change not approved |
| RDP-03 | User disconnects the disposable session; perform only approved observation/input attempt | Explain unavailable interaction/unknown facts; no reconnect, policy change or claimed RDP fix | Not run: disruptive session change not approved |
| VIS-01 | V2 on nonexistent HWND, opt-in heartbeat | Waiting phase then Blocked observation; cleanup remains caller-owned; no Completed claim | Passed against external draft on 2026-11-19; no real window interaction |
| VIS-02 | Approved busy chat, heartbeat plus JSON-lines file | Existing probes only; bounded progress cadence, elapsed time, last observation, outer retries and cleanup ownership; no push per heartbeat | Not run live; cadence/state functions passed isolated tests |
| HANDOFF-01 | Overall task blocked after one successful subtask; pushes enabled | One fixed generic Blocker before final blocked reply; no Completed | Not run as a live agent-behavior test |
| HANDOFF-02 | Required work still running | Waiting status; no completion alert | Not run as a live agent-behavior test |
| HANDOFF-03 | User approval needed; or all required work independently verified | One Question for approval, or one Completed only after overall completion | Not run as a new live agent-behavior test |
| HANDOFF-04 | Same unresolved blocker repeated; or alert transport fails | No duplicate/recursive pushes; report failure and pause pushes per skill | Transport/privacy mocks pass; new agent dedup behavior not verified |
| TTS-01 | Run canonical `Speak-Text.ps1 -Diagnose` in failing account/host/session | Read-only availability facts; no voice/output change, audio, ducking or claim of audible success | Local draft: 64-bit Windows PowerShell, four enabled voices; no audible output tested |
| TTS-02 | User corrects setup and requests one audible retest | Preserve default voice/auto foreground gate; require user confirmation before claiming recovery; pushes remain independent | Not run on the reported failing machine/session |
| DISC-01 | Updated managed build marker, then exact-path `info` | Resolve requested tool from tools map, confirm file and matching identity/capabilities; no random binary fallback | Toolkit verification reported separately; not established by skill wording |
| DISC-02 | Legacy/malformed/stale marker or explicit portable selection | Legacy documented fallback only when verified; report malformed/stale entries; explicit portable choice retains precedence | Not run as a new end-to-end agent discovery test |

Mocked diagnostics and script tests do not establish lower failure rates. Radio T25/transport
timeout handling remains outside this scope; no device/framework code is changed or exercised.

Toolkit evidence on 2026-11-19: the agent's isolated non-interactive run passed 252 tests;
the supervisor rebuilt all six projects and independently passed 72 explicitly non-interactive
diagnostic/marker/fake-call cases. The supervisor's initial broader class selector also ran
desktop fixtures: 113 passed and two placement cases failed with unverified foreground
activation (`stale-context`). The cause is not established, and those failures are not RDP
reproduction or evidence of a repaired foreground limitation. The unfiltered suite was not run.
