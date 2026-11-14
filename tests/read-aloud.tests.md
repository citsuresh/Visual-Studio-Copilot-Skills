# read-aloud test cases

Manual cases for the `read-aloud` skill. Run in a temp folder with `$env:USERPROFILE` pointed at a scratch
folder, so the real `%USERPROFILE%\.copilot` settings and state files are untouched. Ducking changes other
applications' volume for a few seconds; the volumes are restored at the end of each case.

| ID | Case | Expected | Result |
|---|---|---|---|
| R-01 | `AudioDucker.cs` compiled with `Add-Type` in Windows PowerShell 5.1, `ListSessions()` | Compiles; lists the other applications' sessions (none for this process) | Pass 2026-11-13 |
| R-02 | `Duck(0.5, state)` then `Restore(state)` | Every listed session at 0.50 while ducked, back to 1.00 after; state file deleted | Pass 2026-11-13 |
| R-03 | Duck, then edit one session's recorded value (a user changed that volume), `Restore` | The changed session is left alone, the rest are restored | Pass 2026-11-13 |
| R-04 | `Speak-Text.ps1` with no settings file | Speaks, exit 0, no state file, volumes unchanged, helper not compiled | Pass 2026-11-13 (volumes unchanged and no state file seen; not compiled was not checked directly) |
| R-05 | Settings `{"duck":true,"duckPercent":25}`, speak a long sentence | During speech: state file exists and other sessions at 0.25; afterwards: exit 0, state file gone, volumes 1.00 | Pass 2026-11-13 |
| R-06 | As R-05, but kill the PowerShell process mid-speech | State file remains and sessions stay at 0.25 | Pass 2026-11-13 |
| R-07 | Next run after R-06, with `"duck":false` | Leftover state is undone first: volumes back to 1.00, state file gone, text spoken | Pass 2026-11-13 |
| R-08 | Graph skill's `Speak-Text.ps1` forwarder, with the `read-aloud` skill installed and not installed | Installed: speaks, exit 0. Not installed: message `The read-aloud skill is not installed; run Install-Skills.ps1.`, exit 1 | Pass 2026-11-13 (sandbox profile) |
| R-09 | No installed voice, with ducking on | Output `NoVoice`, exit 2, no volume change (the duck call is after the voice check) | Not run (by reading only) |
| R-10 | PowerShell 7 | Same as R-04 to R-07 | Not run (only Windows PowerShell 5.1 installed) |
| R-11 | In a new chat in a project that was never bootstrapped, with the skill installed, say "enable tts" | The `read-aloud` skill is invoked; "TTS on" is said; each reply is followed by a spoken summary; "stop tts" ends it | Not run |
| R-12 | In a project bootstrapped at v27, check `.github\copilot-instructions.md` | One `- Read-aloud (TTS)` bullet naming the `read-aloud` skill, no path, no voice name | Not run |
| R-13 | Looping audio in a browser while speaking with ducking on | Browser audio drops to a quarter, then returns | Not run (the sessions were only observed through the API) |
| R-14 | Parse check (`Parser.ParseFile`) of `Test-HostVsActive.ps1` and `Speak-IfAway.ps1` | No parse errors | Pass 2026-11-14 |
| R-15 | `Test-HostVsActive.ps1` with no parameters, from the agent shell inside the hosting Visual Studio | Finds the `devenv.exe` ancestor; prints `Active` with Visual Studio in front, exit 0 (about 3 s) | Pass 2026-11-14 (`Active`; an earlier run printed `Inactive` with another window in front) |
| R-16 | `-HostPid` set to the process id that owns the foreground window | `Active`, exit 0 | Pass 2026-11-14 (about 1.1 s) |
| R-17 | `-HostPid` set to a live process that does not own the foreground window (the test shell) | `Inactive`, exit 0 | Pass 2026-11-14 |
| R-18 | `-HostPid` of a process that does not exist (999999), and 0 | `Unknown`, exit 3 | Pass 2026-11-14 |
| R-19 | Error path: `-HostPid abc` and `-HostPid 1e30` (cast fails inside the try) | `Unknown`, exit 3, never empty output | Pass 2026-11-14 |
| R-20 | R-18 without `-HostPid`, from a process started through WMI so it has no `devenv.exe` ancestor | `Unknown` | Pass 2026-11-14 (output only; exit code not captured in that run, exit 3 seen in R-18) |
| R-21 | `Speak-IfAway.ps1` with the check returning `Inactive` (`-HostPid` of the test shell) | Speaks, prints `Spoken (Inactive)`, exit 0 | Pass 2026-11-14 (output and exit code; hearing the speech not confirmed by the agent) |
| R-22 | `Speak-IfAway.ps1` with `Active`, with a missing pid, and with `-HostPid abc` | Silent; prints `Silent (Active)`, `Silent (Unknown)`, `Silent (Unknown)`; exit 0 | Pass 2026-11-14 |
| R-23 | `Speak-IfAway.ps1` error paths: sibling scripts missing; check printing something else; `Speak-Text.ps1` stub exiting 2 with `NoVoice` | `Silent (Error: ...)`; exit 1, 1, 2; nothing spoken | Pass 2026-11-14 (scratch folders with stub scripts) |
| R-24 | Say `enable auto tts` in a chat, then switch to another window while a reply runs | Auto TTS on said once; `Speak-IfAway.ps1` runs last in every reply, including the one that turns it on; speech only when away; `stop auto tts` says Auto TTS off, is not spoken, and stops the calls | Not run (needs a real chat and window switching) |
| R-25 | Auto tts and plain tts both on | Every reply is spoken by plain tts, no `Speak-IfAway.ps1` call | Not run (needs a real chat) |
| R-26 | `Test-HostVsActive.ps1` and `Speak-IfAway.ps1` in PowerShell 7 | Same as R-15 to R-23 | Not run (only Windows PowerShell 5.1 installed) |

## Findings

- Session instance identifiers contain `|`; the state file therefore uses tabs (found in R-02's first run).
- Windows PowerShell 5.1 compiles `Add-Type -Path` with the old C# 5 compiler, so the helper avoids newer syntax.
