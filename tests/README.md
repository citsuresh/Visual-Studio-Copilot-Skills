# Repository script test cases

These documents describe manual scenarios in the four-column format `ID | setup / action | expected result | last result`. Record when and where a case was run, or mark it `Not run` with the reason; never mark an unrun case as passing.

| Script | Test cases |
| --- | --- |
| `Install-Skills.ps1` | [Install-Skills.tests.md](Install-Skills.tests.md) |

`Install-Skills.ps1` always targets `%USERPROFILE%\.copilot\skills` and has no temporary destination option. Do not run manual cases against the real user skills folder.

For isolated automated credential-safety checks, run
`.\scripts\agent\Test-InstallSkillsCredential.ps1`. It copies the installer to its own disposable
source fixture and temporarily redirects process `USERPROFILE` to a fake profile, with toolkits
disabled. Dummy markers verify source credential exclusion, installed credential preservation,
nested script updates, ordinary orphan pruning and a final up-to-date check. It restores the
environment and removes its fixture in `finally`; it never reads real credentials or uses network.
Passing this test does not mark the separate manual scenarios as passing.

`scripts\agent\Test-ReadAloud.ps1` mocks speech and checks preserved failure markers/exit codes,
stage-specific bounded diagnostics without text disclosure, non-speaking `-Diagnose`, and
auto-TTS Active/Unknown silence, plus the meeting guard (`Test-MeetingActive.ps1` with faked microphone consent entries; mute/duck/off, defaults, fail-open). It creates/removes only its own wrapper fixture and never
produces audio or notifications. `scripts\agent\Test-WatcherProgress.ps1` extracts the progress
functions through the PowerShell AST and checks silent defaults, throttling, operational facts
and terminal states without UI calls, file writes or waiting. Both accept external draft paths.
Neither test proves remote audio, RDP foreground behavior, or agent compliance with handoff rules.

Additional live acceptance cases are in [Feedback-session.tests.md](Feedback-session.tests.md).
