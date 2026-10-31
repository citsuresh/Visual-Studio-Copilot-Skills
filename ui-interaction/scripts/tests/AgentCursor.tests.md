# AgentCursor.ps1: test cases

Script: `..\AgentCursor.ps1`. It changes the system cursor and uses `%TEMP%\agent-cursor-session.flag`; run only in a window/session you own, with no unrelated cursor session active. Record the normal cursor state first and use `-Restore` for cleanup if needed. Not run as of 2026-10-31.

| ID | Setup / action | Expected result | Last result |
| --- | --- | --- | --- |
| A-01 | With no active session, run `-Session Start`, then `-Session Stop` (default `Orchestrator`) | Start reports an Orchestrator session and shows the blue dot; the flag records `kind=Orchestrator`. Stop reports the session cleared, removes the flag and restores the user's cursor scheme | Not run: not exercised during this documentation task |
| A-02 | With no active session, run `-Session Start -Kind UiAutomation`, then `-Session Stop -Kind UiAutomation` | Start reports a UiAutomation session and shows the green dot; the flag records `kind=UiAutomation`. Stop clears the flag and restores the user's cursor scheme | Not run: not exercised during this documentation task |
| A-03 | Start the Orchestrator session, then run `-Session Start -Kind UiAutomation` and `-Session Stop -Kind UiAutomation` | The Orchestrator session retains ownership and the blue dot; the second start changes nothing, and the wrong-kind stop refuses to clear the session. `-Restore` clears it during cleanup | Not run: not exercised during this documentation task |
| A-04 | With no active session, run `-Session Stop` twice | Both calls complete without error; no session flag remains and the cursor is restored | Not run: not exercised during this documentation task |
| A-05 | With an Orchestrator session active, dot-source the script and run `try { Enable-AgentCursor -Mode Input -LeadMilliseconds 0; throw 'test-only' } finally { Restore-AgentCursor }` | The test-only exception occurs; the cursor returns from the red Input dot to the blue session dot, and the session flag remains intact | Not run: not exercised during this documentation task |
| A-06 | With an Orchestrator session active, run `-Show -Mode Input -Seconds 2` | Shows the red Input dot for two seconds, then restores the blue session dot; the command reports that the indicator was shown and the cursor restored | Not run: not exercised during this documentation task |
| A-07 | Start either session, then run `-Restore` | Reports all sessions cleared, removes the flag and restores the user's cursor scheme | Not run: not exercised during this documentation task |
