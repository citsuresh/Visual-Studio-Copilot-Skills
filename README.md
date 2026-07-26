# Visual Studio Copilot Skills

Personal GitHub Copilot Agent Skills for Visual Studio — persistent, low-token project memory
across sessions, with an optional Roslyn-based code knowledge graph for larger solutions.

## What's in this repo

| Folder | Purpose |
|---|---|
| `project-memory-management/` | Core skill: maintains `docs/CODE_SUMMARY.md`, `DESIGN_DECISIONS.md`, `PROJECT_STATE.md`, `ROADMAP.md`, and wires them into `.github/copilot-instructions.md`. |
| `project-memory-management-graph/` | Everything the core skill does, plus builds/updates a code knowledge graph via [GraphTools](https://github.com/citsuresh/GraphTools) and copies a visual graph viewer into the project. |
| `Install-Skills.ps1` | Copies both skills into your personal Copilot skills folder. Auto-discovers any skill folder in this repo (containing a `SKILL.md`), so new skills added later need no script changes. |

Each skill has three workflows: **Bootstrap** (start of session / first-time setup),
**End Session** (cheap end-of-session snapshot), and **Initialize** (one-time setup that wires
the skill into a project's own short trigger prompts).

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

## Installing

Skills must live in your personal Copilot skills folder
(`%USERPROFILE%\.copilot\skills\<skill-name>\SKILL.md`) to apply automatically across every
project on your machine — this is a manual copy step; nothing about cloning this repo installs
anything automatically.

**Option 1 — script (recommended):**
```powershell
git clone <this-repo-url>
cd visual-studio-copilot-skills
.\Install-Skills.ps1
```
Shows exactly what's changed per skill and asks for confirmation before copying anything. Use
`-Force` to skip the prompts once you trust it.

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

Both apply automatically to every project once installed — pick per project based on whether
you want the knowledge graph:

- **`project-memory-management`** — any project, including non-.NET (it never touches code
  itself, only docs/instructions). No GraphTools dependency.
- **`project-memory-management-graph`** — .NET projects with a `.sln`/`.slnx` where a call
  graph adds value, or where you simply want Copilot to have queryable structural context
  without re-exploring the codebase each session. Requires GraphTools to be built locally.

Switching a project from one to the other: re-run Initialize with the skill you're switching
to — it detects the existing trigger files and asks before overwriting, so both files always
stay pointed at the same skill rather than drifting apart.

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
