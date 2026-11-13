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
| `install-skills/` | Lets Copilot install or update all the skills in this repo for you ("install skills from `<repo url>`", "check the repo and update all the skills"): `Install-Skills.ps1 -Check -Remote`, then `-Remote -Force` (and `-Prune` only after asking you). Installed by `Install-Skills.ps1` like the others. |
| `Install-Skills.ps1` | Copies all skills into your personal Copilot skills folder. Auto-discovers any skill folder in this repo (containing a `SKILL.md`), so new skills added later need no script changes. |
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
- For `project-memory-management-graph` specifically: [GraphTools](https://github.com/citsuresh/GraphTools)
  cloned and built separately — this skill invokes `GraphTools.Builder.exe`/`GraphTools.Query.exe`
  by absolute path, so confirm that repo is built before using this skill.
  **`project-memory-management-graph/SKILL.md` hardcodes the GraphTools executable paths as
  `C:\MyFiles\Git\GraphTools\... Before installing this skill, edit
  the "GraphTools invocation" section of that `SKILL.md` to point at wherever you cloned/built
  GraphTools on your own machine.** If the paths are wrong or GraphTools hasn't been built, the
  skill will stop and tell you rather than silently failing or attempting to locate/build it itself.
- For `ui-interaction`, `vs-debug`, `ui-navigation-orchestrator`, and `agent-orchestrator`:
  [AgentDebugToolkit](https://github.com/citsuresh/AgentDebugToolkit) cloned and built separately
  (`agentdebug-ui.exe` and, for `vs-debug`, the debugger-bridge CLI). These skills hardcode
  `C:\MyFiles\Git\AgentDebugToolkit\...` paths and use an "ask, don't guess" fallback if that path
  doesn't exist on your machine — edit the relevant SKILL.md path(s) to match your own clone
  location before installing.

## Installing

Skills must live in your personal Copilot skills folder
(`%USERPROFILE%\.copilot\skills\<skill-name>\SKILL.md`) to apply automatically across every
project on your machine — this is a manual copy step; nothing about cloning this repo installs
anything automatically.

**Option 0 — ask Copilot (new machine):** the `install-skills` skill is not installed yet on a new
machine, so spell the first request out once, for example:

> Clone `<this-repo-url>` to `C:\MyFiles\Git\Visual-Studio-Copilot-Skills` and run
> `.\Install-Skills.ps1 -Check`, show me the result, then run `.\Install-Skills.ps1 -Force`.

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
(`UpToDate` or `UpdatesAvailable`). Every run also reports companion tool folders the skills refer to
(`C:\MyFiles\Git\GraphTools`, `AgentDebugToolkit`, `VsChatHistoryToolkit`) that are missing, with the
`git clone` command; it never clones or builds them.

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
periodic. The memory skills also keep their separate per-project marker check.

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
