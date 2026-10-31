# Install-Skills.ps1: test cases

Script: `..\Install-Skills.ps1`. The destination is hard-coded to `%USERPROFILE%\.copilot\skills`; there is no temporary-target parameter. Do not run against the real user skills folder. All cases below are not run as of 2026-10-31 for that reason.

| ID | Setup / action | Expected result | Last result |
| --- | --- | --- | --- |
| I-01 | With an empty isolated destination, run the installer without `-Force` and approve each skill | Each repo subfolder containing `SKILL.md` is listed and copied with its files to the destination; the installer finishes with its completion message | Not run (2026-10-31; no temporary destination supported, real user folder not used) |
| I-02 | Put an older copy of a skill in the isolated destination, update a source file in the repo, run without `-Force` and approve that skill | The changed file is listed and copied; its installed SHA-256 matches the repo copy afterward | Not run (2026-10-31; no temporary destination supported, real user folder not used) |
| I-03 | Have multiple skills with changed files; run without `-Force`, decline one skill and approve another | The installer prompts separately for each changed skill; declining leaves that destination unchanged, while approval copies the approved skill and processing continues | Not run (2026-10-31; no temporary destination supported, real user folder not used) |
| I-04 | Have multiple skills with changed files and run with `-Force` | Copies each changed skill without per-skill confirmation prompts | Not run (2026-10-31; no temporary destination supported, real user folder not used) |
| I-05 | Edit a file only in an installed skill, then run without `-Force` and approve that skill | The destination hash mismatch is reported as a changed file; approval overwrites the local edit with the repo version | Not run (2026-10-31; no temporary destination supported, real user folder not used) |
| I-06 | Remove a file from the repo copy of a skill while that file remains in the installed copy, then install the skill | The installer copies changed/new source files but does not remove destination-only files; the removed file remains installed | Not run (2026-10-31; no temporary destination supported, real user folder not used) |
| I-07 | Make an unrelated, uncommitted edit to a file inside a skill folder, then approve installation of that skill | The installer includes the uncommitted repo content; it copies the edited source file without checking Git status | Not run (2026-10-31; no temporary destination supported, real user folder not used) |
| I-08 | Interrupt a copy to an isolated destination, then rerun the installer with `-Force` | The interrupted run may leave a partial destination; the rerun detects missing/different source files and copies them so installed source files match the repo | Not run (2026-10-31; no temporary destination supported, real user folder not used) |

## Findings

- Destination-only files are not removed: the installer enumerates and copies source files but does not compare the destination for files absent from the repo. Thus, a script removed from the repo (such as the old `Watch-CopilotChat.ps1`) can remain in the installed skill and may need manual deletion. This is confirmed by reading the installer; the case was not run.
