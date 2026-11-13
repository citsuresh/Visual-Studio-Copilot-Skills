---
name: install-skills
description: 'Install or update the Copilot skills in the Visual-Studio-Copilot-Skills repo on this machine by running the repo''s Install-Skills.ps1: clone or pull the repo, check what is new or outdated, install or update every skill into %USERPROFILE%\.copilot\skills\, optionally remove files no longer in the repo, and report missing companion tools (GraphTools, AgentDebugToolkit, VsChatHistoryToolkit). Use for: "install skills from <repo url>", "check the repo and update all the skills", "are my skills up to date", "update my skills". Never commits or pushes.'
---

# Install or update skills from the repo

All commands are PowerShell. Never write outside the repo clone and `%USERPROFILE%\.copilot\skills\`.
Never commit or push.

## 1. Locate or clone the repo

- URL given: the clone folder is `C:\MyFiles\Git\<repo name>` (companion tools live in the same parent
  folder). If a folder with that name exists, check `git -C <folder> remote get-url origin` matches
  the URL; if it does not match, stop and ask.
- No URL given (update request): use `C:\MyFiles\Git\Visual-Studio-Copilot-Skills`; if it is missing,
  ask for the URL.
- Not cloned yet: `git clone <url> <folder>`.
- Already cloned: do not pull by hand. `Install-Skills.ps1 -Remote` (steps 2 and 3) fetches from GitHub,
  reports what is new, and pulls fast-forward only, never when tracked files have uncommitted changes.
- If `<folder>\Install-Skills.ps1` does not exist, stop and say this repo is not a skills repo.

## 2. Check first (read-only)

Run `<folder>\Install-Skills.ps1 -Check -Remote` and read its output. The `REMOTE:` line says whether
GitHub has commits the clone does not (`UpToDate`, `Behind N commit(s)`, `Diverged`, `Unreachable`, ...),
with the commit subjects and the skills they touch. The last line is `RESULT: UpToDate` or
`RESULT: UpdatesAvailable (...)`. Summarise: what is new on GitHub, which skills are new or changed,
installed files that are no longer in the repo, and any companion tool folders reported missing.

- `REMOTE: Unreachable`: say GitHub could not be checked and that the result covers the local clone only.
- `REMOTE:` ending in `NOT pulled: uncommitted changes to tracked files` or `Diverged`: the clone cannot
  be updated automatically; report it and let the user decide.
- A request that only asks to check ("are my skills up to date", "check the repo") stops here.
- `UpToDate` with a reachable remote: say so and stop.

## 3. Install or update

Run `<folder>\Install-Skills.ps1 -Remote -Force`. Asking to install or update is the confirmation for
the pull and the copy. If the pull changed `Install-Skills.ps1` itself, the script runs the new copy.

- If the check listed installed files that are no longer in the repo, ask the user once whether to
  remove them. Only if they agree, run `<folder>\Install-Skills.ps1 -Force -Prune`. Never add
  `-Prune` on your own.
- If the script fails, report the full error and stop; do not retry automatically.

## 4. Report

Say which skills were installed or updated, then run `Install-Skills.ps1 -Check` once more and quote
its `RESULT:` line as proof. Tell the user that new or updated skills may only appear in a new chat
session (restart Visual Studio if they still do not show).

Companion tools reported missing: list them with the clone command the script printed. Do not clone or
build them unless the user asks; the skills that use them will not work until they exist.
