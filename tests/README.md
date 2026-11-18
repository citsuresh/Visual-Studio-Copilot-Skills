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
