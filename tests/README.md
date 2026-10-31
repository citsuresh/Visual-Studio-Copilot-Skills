# Repository script test cases

These documents describe manual scenarios in the four-column format `ID | setup / action | expected result | last result`. Record when and where a case was run, or mark it `Not run` with the reason; never mark an unrun case as passing.

| Script | Test cases |
| --- | --- |
| `Install-Skills.ps1` | [Install-Skills.tests.md](Install-Skills.tests.md) |

`Install-Skills.ps1` always targets `%USERPROFILE%\.copilot\skills` and has no temporary destination option. Do not run these cases against the real user skills folder; leave them marked not run unless the installer is changed to support an isolated target.
