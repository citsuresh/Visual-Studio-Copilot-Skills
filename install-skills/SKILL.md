---
name: install-skills
description: 'Install or update the Copilot skills in the Visual-Studio-Copilot-Skills repo on this machine by running the repo''s Install-Skills.ps1: clone or pull the repo, check what is new or outdated, install or update every skill into %USERPROFILE%\.copilot\skills\, optionally remove files no longer in the repo, and clone, update and build the companion toolkits (GraphTools, AgentDebugToolkit, VsChatHistoryToolkit) under %USERPROFILE%\.copilot\toolkits\. Use for: "install skills from <repo url>", "check the repo and update all the skills", "are my skills up to date", "update my skills". Never commits or pushes.'
---

# Install or update skills from the repo

All commands are PowerShell. Never write outside the repo clone, `%USERPROFILE%\.copilot\skills\`,
`%USERPROFILE%\.copilot\toolkits\` and `%USERPROFILE%\.copilot\skills-source.json`. Never commit or push.

## 1. Locate or clone the repo

- The clone folder is recorded by `Install-Skills.ps1` in `%USERPROFILE%\.copilot\skills-source.json`
  (`skillsRepo`); read it first:
  `(Get-Content "$env:USERPROFILE\.copilot\skills-source.json" -Raw | ConvertFrom-Json).skillsRepo`.
- URL given: if `skillsRepo` exists and `git -C <folder> remote get-url origin` matches the URL, use it.
  Otherwise ask the user where to clone (suggest `C:\MyFiles\Git\<repo name>` if they have no
  preference). If the chosen folder already exists, check that its origin matches the URL; if it does
  not match, stop and ask. The companion toolkits no longer live next to the clone: the installer puts
  them under `%USERPROFILE%\.copilot\toolkits\`.
- No URL given (update request): use `skillsRepo`; if the file or folder is missing, ask for the URL.
- Not cloned yet: `git clone <url> <folder>`.
- Already cloned: do not pull by hand. `Install-Skills.ps1 -Remote` (steps 2 and 3) fetches from GitHub,
  reports what is new, and pulls fast-forward only, never when tracked files have uncommitted changes.
- If `<folder>\Install-Skills.ps1` does not exist, stop and say this repo is not a skills repo.

## 2. Check first (read-only)

Run `<folder>\Install-Skills.ps1 -Check -Remote` and read its output. The `REMOTE:` line says whether
GitHub has commits the clone does not (`UpToDate`, `Behind N commit(s)`, `Diverged`, `Unreachable`, ...),
with the commit subjects and the skills they touch. The last line is `RESULT: UpToDate` or
`RESULT: UpdatesAvailable (...)`. Each toolkit has a `TOOLKIT: <Name> <Status> (...)` line
(`UpToDate`, `NotInstalled`, `NeedsBuild`, `Behind`, `Diverged`, `NotAClone`, `NoDotnetSdk`, `NoGit`).
Summarise: what is new on GitHub, which skills are new or changed, installed files that are no longer
in the repo, and every toolkit that is not `UpToDate`.

- `REMOTE: Unreachable`: say GitHub could not be checked and that the result covers the local clone only.
- `REMOTE:` ending in `NOT pulled: uncommitted changes to tracked files` or `Diverged`: the clone cannot
  be updated automatically; report it and let the user decide.
- A request that only asks to check ("are my skills up to date", "check the repo") stops here.
- `UpToDate` with a reachable remote: say so and stop.

## 3. Install or update

Run `<folder>\Install-Skills.ps1 -Remote -Force`. Asking to install or update is the confirmation for
the pull, the copy, and the toolkit clone, fast-forward and build (a first install builds three toolkits
and takes about a minute; it needs git and a .NET SDK 8 or later). A toolkit with uncommitted changes,
local commits or no git history is left alone and reported. If the pull changed `Install-Skills.ps1`
itself, the script runs the new copy. `-SkipToolkits` leaves the toolkits out.

- If the check listed installed files that are no longer in the repo, ask the user once whether to
  remove them. Only if they agree, run `<folder>\Install-Skills.ps1 -Force -Prune`. Never add
  `-Prune` on your own.
- If the script fails, report the full error and stop; do not retry automatically.

## 4. Report

Say which skills were installed or updated, then run `Install-Skills.ps1 -Check` once more and quote
its `RESULT:` line as proof. Tell the user that new or updated skills may only appear in a new chat
session (restart Visual Studio if they still do not show).

Toolkit statuses that are not `UpToDate` after the run (`NoDotnetSdk`, `NotAClone`, `Diverged`, `CloneFailed`,
`PullFailed`, `BuildFailed`, ...): quote the `TOOLKIT:` line and say what it needs. The skills that use that
toolkit will not work until it is `UpToDate`.
