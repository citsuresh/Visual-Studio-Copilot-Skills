# Visual Studio Copilot Skills

Personal GitHub Copilot Agent Skills for Visual Studio. Two families:

- **Project memory** (`project-memory-management-graph`, and the deprecated `project-memory-management`):
  persistent, low-token project memory across sessions, with an optional Roslyn-based code knowledge
  graph for larger solutions.
- **UI automation and supervision** (`ui-interaction`, `vs-debug`, `ui-navigation-orchestrator`,
  `agent-orchestrator`, `vs-chat-history`): drive and read other Windows applications and the Visual
  Studio debugger, supervise a Copilot chat running in another Visual Studio window, and search the
  local Copilot chat history.

## What's in this repo

| Folder | Purpose |
|---|---|
| `project-memory-management/` | Core skill: maintains `docs/CODE_SUMMARY.md`, `DESIGN_DECISIONS.md`, `PROJECT_STATE.md`, `ROADMAP.md`, and wires them into `.github/copilot-instructions.md`. |
| `project-memory-management-graph/` | Everything the core skill does, plus builds/updates a code knowledge graph via [GraphTools](https://github.com/citsuresh/GraphTools) and copies a visual graph viewer into the project. |
| `ui-interaction/` | Generic Windows UI automation primitives (click, inspect/read, wait/poll, selector fallback) via [AgentDebugToolkit](https://github.com/citsuresh/AgentDebugToolkit)'s `agentdebug-ui.exe`. A pure mechanism skill — never decides whether an action succeeded; that judgment belongs to whichever skill calls it. |
| `vs-debug/` | Drives the Visual Studio debugger (attach, breakpoints, step, read call stack) via AgentDebugToolkit's debugger bridge. Independently useful; can call `ui-interaction` to trigger UI actions while attached. |
| `ui-navigation-orchestrator/` | Experimental, still-maturing orchestration layer that composes `ui-interaction` + `vs-debug` to navigate a target app's UI, maintaining a lightweight per-target-app navigation-tree cache. Replaces the retired `ui-debug-map` skill. |
| `agent-orchestrator/` | Drives and supervises a Copilot chat agent running in a *different* Visual Studio window via AgentDebugToolkit's UIA CLI — attach, assign tasks, poll state, detect/answer prompts, run the Decomposition → implement → Audit → review → approve → commit loop. Ships helper scripts in `scripts/`: `Send-CopilotPrompt`, two chat watchers (`Watch-CopilotChatV2`, the light default, and `Watch-CopilotChatV1`, the full-tree one), `Select-ChoicePromptOption`, `Read-CopilotReply`, `Invoke-CopilotReview` and others, with manual test cases in `scripts/tests/`. |
| `vs-chat-history/` | Searches and reads the Visual Studio Copilot Chat history stored on this machine through the `chathistory` CLI of [VsChatHistoryToolkit](https://github.com/citsuresh/VsChatHistoryToolkit): word search, session lists and filters, capped excerpts of turns and checkpoints, counts, and (only on request) rename and undo. Read-only except rename and undo-rename; covers `session-store.db` only; chat text is treated as sensitive. |
| `read-aloud/` | Optional text-to-speech for the current chat: say "enable tts" or "start tts" and Copilot speaks a short summary of each reply with the Windows default voice until you say "disable tts" or "stop tts". Works in any project (no Bootstrap needed). Ships `scripts/Speak-Text.ps1` and `scripts/AudioDucker.cs`; optionally lowers other applications' audio while speaking (opt-in through `%USERPROFILE%\.copilot\tts-settings.json`, `{"duck":true,"duckPercent":25}`; the C# is compiled in memory, so no build step). Has no version and is not listed in `skills-index.json`. |
| `install-skills/` | Lets Copilot install| `install-skills/` | Lets Copilot install or update all the skills in this repo for you ("install skills from `<repo url>`", "check the repo and update all the skills"): `Install-Skills.ps1 -Check -Remote`, then `-Remote -Force` (and `-Prune` only after asking you). Installed by `Install-Skills.ps1` like the others. |
| `Install-Skills.ps1` | Copies all skills into your personal Copilot skills folder. Auto-discovers any skill folder in this repo (containing a `SKILL.md`), so new skills added later need no script changes. Also records this clone's path in `%USERPROFILE%\.copilot\skills-source.json` and clones, updates and builds the companion toolkits under `%USERPROFILE%\.copilot\toolkits\` (see "Toolkits" below). |
| `skills-index.json` | Generated, about 2 KB: each skill's current `version` and a one-line `whatsNew` (taken from its changelog). The skills' first-use update check reads this instead of the whole `SKILL.md` (up to 113 KB). Never edit it by hand. `install-skills` has no version and is not listed. |
| `scripts/Update-SkillsIndex.ps1` | Regenerates `skills-index.json` from the `SKILL.md` files (no AI, no commit message). `-Check` only compares and exits 1 if the index is out of date; `-Stage` also runs `git add`. `Install-Skills.ps1 -Check` prints the result as an `INDEX:` line. |
| `.githooks/` | `pre-commit` regenerates and stages `skills-index.json` whenever a `SKILL.md` is committed. `pre-push` warns (never blocks) if a `SKILL.md` in the pushed commits changed but its `CURRENT_SKILL_VERSION` did not, judged over the whole push so several commits before the final bump are fine. Enable once per clone: `git config core.hooksPath .githooks`. |
| `tests/` | Manual test cases for `Install-Skills.ps1`. Test cases for the other scripts sit next to them, in each skill's `scripts/tests/` folder. |

Each of the two project-memory skills has three workflows: **Bootstrap** (start of session /
first-time setup), **End Session** (cheap end-of-session snapshot), and **Initialize** (one-time
setup that wires the skill into a project's own short trigger prompts). The UI automation and
supervision skills have no such workflows: they are used when a task needs them (see "Which skill
to use" below), and their helper scripts and test cases live in each skill's `scripts/` folder.

## Prerequisites

- Visual Studio 2026, **Professional or Enterprise** (Agent Skills is not available in the free
  Community edition), version 18.5 or later.
- **git** and the **.NET SDK 8 or later**: `Install-Skills.ps1` uses them to clone and build the
  companion toolkits below. Without the SDK a toolkit that needs a build is reported as `NoDotnetSdk`
  and left alone; the skills themselves still install.
- For `project-memory-management-graph` specifically: [GraphTools](https://github.com/citsuresh/GraphTools).
  `Install-Skills.ps1` clones and builds it at `%USERPROFILE%\.copilot\toolkits\GraphTools`, and the
  skill calls `tools\Invoke-GraphTools.ps1` there. Nothing needs editing in the `SKILL.md`. If GraphTools
  is missing or not built, the skill's Step 0 toolkit check says so and offers to run the installer.
- For `ui-interaction`, `vs-debug`, `ui-navigation-orchestrator`, and `agent-orchestrator`:
  [AgentDebugToolkit](https://github.com/citsuresh/AgentDebugToolkit) (`agentdebug-ui.exe` and, for
  `vs-debug`, the debugger-bridge CLI), cloned and built by the installer at
  `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit`. `ui-interaction`, `vs-debug` and
  `agent-orchestrator` check it in Step 0; `ui-navigation-orchestrator` relies on the checks of the
  first two.
- For `vs-chat-history`: [VsChatHistoryToolkit](https://github.com/citsuresh/VsChatHistoryToolkit)
  (`chathistory.exe`), at `%USERPROFILE%\.copilot\toolkits\VsChatHistoryToolkit`, checked in the skill's Step 0.

## Installing

Skills must live in your personal Copilot skills folder
(`%USERPROFILE%\.copilot\skills\<skill-name>\SKILL.md`) to apply automatically across every
project on your machine — this is a manual copy step; nothing about cloning this repo installs
anything automatically.

**Option 0 — ask Copilot (new machine):** the `install-skills` skill is not installed yet on a new
machine, so spell the first request out once, for example:

> Clone `<this-repo-url>` to `<a folder you choose>` and run
> `.\Install-Skills.ps1 -Check`, show me the result, then run `.\Install-Skills.ps1 -Force`.

The first real run records where the clone is (`%USERPROFILE%\.copilot\skills-source.json`), so the
skills and `install-skills` find it afterwards, and builds the three toolkits (about a minute, once).

After that, the short forms work in any chat: "install skills from `<repo url>`" and "check the repo
and update all the skills" (also "are my skills up to date"). The skill clones the repo if needed, runs
`-Check -Remote` (which asks GitHub what is new), installs with `-Remote -Force` (which pulls, then
installs), asks before it deletes anything (`-Prune`), and finishes with a second `-Check` as proof.

**Option 1 — script (recommended):**
```powershell
git clone <this-repo-url>
cd visual-studio-copilot-skills
.\Install-Skills.ps1
```
Shows exactly what's changed per skill and asks for confirmation before copying anything. Use
`-Force` to skip the prompts once you trust it. Files that were removed from the repo but remain in
an installed skill are listed and left in place; add `-Prune` to delete them (same confirmation).
`-Check` changes nothing: it lists what is new or outdated and ends with a `RESULT:` line
(`UpToDate` or `UpdatesAvailable`). Every run also prints one `TOOLKIT:` line per companion toolkit and
an informational `SOURCE:` line for `skills-source.json`; see "Toolkits" below. `-SkipToolkits` leaves
the toolkits out entirely.

`-Remote` checks GitHub first (`git fetch`) and prints a `REMOTE:` line (`UpToDate`, `Behind N commit(s)`,
`Pulled N commit(s)`, `Diverged`, `Unreachable`, ...) with the commit subjects and the skills they touch.
With `-Check` it only reports. Without `-Check`, if the clone is only behind and has no uncommitted
changes to tracked files, it pulls (`--ff-only`) and then installs; if the pull changed
`Install-Skills.ps1` itself, the new copy runs. `-MaxAgeHours N` skips the fetch when the clone was
fetched less than N hours ago. If GitHub cannot be reached, the `RESULT:` line says
"GitHub not checked".

**Option 2 — manual:**
Copy each folder's contents into the matching path under `%USERPROFILE%\.copilot\skills\`.

## Using a skill in a project

One-time setup per project:
```
Use the project-memory-management skill, run Initialize.
```
(or `project-memory-management-graph`, for the graph-enabled variant)

This creates two tiny local trigger files — `.github/prompts/bootstrap.prompt.md` and
`.github/prompts/end-session.prompt.md` — each just a one-line pointer back to the skill, so
day-to-day you only need short local triggers rather than repeating the full skill name.

Start of a working session:
```
Use the project-memory-management skill, run Bootstrap.
```

End of a working session:
```
Use the project-memory-management skill, run End Session.
```

## Which skill to use

**`project-memory-management-graph` is the recommended default for every project**, regardless
of whether it has a `.sln`/`.slnx`. Since v8 it includes a "docs-only mode" that handles
non-.NET/docs-only repos itself (skipping the graph build, no GraphTools dependency needed in
that case), and it also has versioning/staleness-checking and the Regression Auditor Protocol
that the plain `project-memory-management` skill never had.

`project-memory-management` (no graph) is **deprecated in favor of the graph skill's docs-only
mode** — see the deprecation notice at the top of its own README and SKILL.md. It's kept in this
repo for reference only, not actively maintained, and should not be used for new projects.

As of this writing, no project under this machine's usual repo root (`C:\MyFiles\Git`) has
been verified to still use the plain skill — the two repos its own README lists as "tested on"
(GitContextSwitcher, VoiceType) have both since moved to the graph skill's marker convention.
This is not an absolute guarantee: repos outside that path, or any repo using the plain skill
without leaving a graph-skill trace, can't be ruled out from here.

Switching a project from the plain skill to the graph skill: re-run Initialize with
`project-memory-management-graph` — it detects the existing trigger files and asks before
overwriting, so both files always stay pointed at the same skill rather than drifting apart.

**UI automation skills** (`ui-interaction`, `vs-debug`, `ui-navigation-orchestrator`,
`agent-orchestrator`) are a separate family unrelated to project memory. `ui-interaction` and
`vs-debug` are stable, independent mechanism skills; `ui-navigation-orchestrator` composes them
for UI navigation/mapping tasks and replaces the retired `ui-debug-map` skill; `agent-orchestrator`
composes them to drive a Copilot chat session in another VS window. Each has its own
`CURRENT_SKILL_VERSION` and changelog (see each `SKILL.md`).

**Update check at first use:** every skill except `install-skills` (which always checks GitHub itself)
checks once per chat session, the first time it is used, whether a newer version exists: it runs
`git fetch` on the local clone, compares its own `CURRENT_SKILL_VERSION` with its entry in the
clone's and the GitHub upstream's `skills-index.json` (a 2 KB read; it falls back to reading just the
version line of `SKILL.md` if there is no index), and, if one is newer, tells you what's new and asks
whether to run `Install-Skills.ps1 -Remote -Force`. It never updates without asking, and it is not
periodic. The memory skills also keep their separate per-project marker check. The skills that use a
toolkit run a second, read-only check in the same step (`Install-Skills.ps1 -Check -Remote
-MaxAgeHours 6`, filtered to their own `TOOLKIT:` line), also when the skill version matches: a missing,
unbuilt or outdated toolkit is reported and the skill asks before running the installer.

## Toolkits

Several skills call three companion command-line tools. Each is a public git repo; the installer
clones it under `%USERPROFILE%\.copilot\toolkits\<Name>` and builds it there with the repo's own
`scripts\agent\Build-Toolkit.ps1`. Nothing binary is shipped: every machine builds its own copy.

| Toolkit | Used by | Entry point after the build |
|---|---|---|
| [GraphTools](https://github.com/citsuresh/GraphTools) | `project-memory-management-graph` | `tools\Invoke-GraphTools.ps1` |
| [AgentDebugToolkit](https://github.com/citsuresh/AgentDebugToolkit) | `ui-interaction`, `vs-debug`, `agent-orchestrator`, `ui-navigation-orchestrator` | `src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe` and `src\AgentDebugToolkit.Debugger.VisualStudio\bin\Debug\net8.0-windows\agentdebug-vs.exe` |
| [VsChatHistoryToolkit](https://github.com/citsuresh/VsChatHistoryToolkit) | `vs-chat-history` | `src\VsChatHistoryToolkit.Cli\bin\Debug\net8.0\chathistory.exe` |

Each toolkit repo has an integer `VERSION` file and a `scripts\agent\Build-Toolkit.ps1`. A successful
build writes the built commit to `.built-version` (git-ignored). The installer prints one line per
toolkit, `TOOLKIT: <Name> <Status> (...)`:

| Status | Meaning | What the installer does |
|---|---|---|
| `UpToDate` | Cloned, built from the current commit, nothing newer upstream | nothing |
| `NotInstalled` | No folder yet | clones it, then builds |
| `NeedsBuild` | The built commit differs from the checked-out one | builds |
| `Behind` | `-Remote` only: upstream has newer commits | fast-forwards, then builds |
| `Diverged` | Local commits that upstream does not have | nothing; reported |
| `NotAClone` | The folder exists but is not a git clone | nothing; reported |
| `NoDotnetSdk` | A build is needed but no .NET SDK is installed | nothing; reported |
| `CloneFailed`, `PullFailed`, `NoBuildScript`, `BuildFailed` | A step of a real run failed | reported; exit code 1 |

`-Check` never changes anything; any status except `UpToDate` is added to the `RESULT:` line. A
fast-forward never overwrites uncommitted changes to tracked files. Without `-Force` the installer asks
before cloning or building. `-ToolkitBaseUrl` changes where the repos come from (default
`https://github.com/citsuresh`; a folder path or a fork also works).

To work on a toolkit, use a separate clone elsewhere (this machine uses `C:\MyFiles\Git`), not the
folder under `.copilot\toolkits`, which belongs to the installer. A toolkit change reaches other
machines when it is pushed; bump the toolkit's `VERSION` so the change is visible in its history. The
locally built, unsigned executables may be flagged by antivirus software on some machines; this has not
been verified.

## Design notes

- **Scope-restricted**: both skills are explicit that they never create a new repository and
  never touch files outside the current project folder or the skill's own folder.
- **Path resolution**: all file operations resolve the true repository root via
  `git rev-parse --show-toplevel` (falling back to the top-level `.sln`/`.slnx`'s folder) rather
  than assuming the currently active project's folder — this matters for solutions with a
  nested layout (e.g. `RepoRoot/RepoRoot/*.csproj`).
- **Merge-safe**: re-running Bootstrap never blindly overwrites existing content — it only adds
  what's missing (e.g. required Project Guidelines bullets) and leaves any other existing
  content in a section untouched.
- **Frontmatter `description` kept under 1024 characters** — Copilot silently disables a skill
  that exceeds this (shown as a red error icon in the Skills panel), so this is a hard ceiling
  to watch when editing either skill's description.

## Updating a skill

Edit the `SKILL.md` (or `graph-viewer.html`) directly in this repo, commit, then re-run
`Install-Skills.ps1` to push the update into your personal skills folder — the script only
copies files that actually changed (compared by hash), so this is safe to re-run at any time.

When a change affects behaviour, bump `CURRENT_SKILL_VERSION` and add a changelog entry whose first
sentence says what's new: that sentence becomes the index's `whatsNew`. With the hooks enabled
(`git config core.hooksPath .githooks`, once per clone) the index is regenerated on commit and a
missing bump is warned about on push. Without the hooks, run `scripts\Update-SkillsIndex.ps1` before
committing; `Install-Skills.ps1 -Check` reports `INDEX: OutOfDate` if you forget. Edits made on
github.com bypass the hooks, so run the script afterwards.
