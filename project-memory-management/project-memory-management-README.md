# project-memory-management — README

## What this is
A GitHub Copilot Agent Skill (personal/global, applies across all projects) that manages
persistent, low-token project memory for any .NET repo. Replaces the older manual copy-paste
prompt-file workflow and the abandoned CopilotToolkit WPF sync-tool idea — Copilot's native
Agent Skills feature (Visual Studio Professional/Enterprise, v18.5+) made both unnecessary.

## Location
`C:\Users\sveluswa\.copilot\skills\project-memory-management\SKILL.md`

Personal/global skills folder — anything placed here applies automatically to every project
on this machine, no per-project copying needed.

## What it does — three workflows
1. **Bootstrap** — start of session / first-time setup. Discovers project structure, creates
   or updates four memory files in `docs/`:
   - `CODE_SUMMARY.md` — overview, Mermaid dependency graph, symbol index, key flows.
   - `DESIGN_DECISIONS.md` — append-only, dated log of non-obvious architectural decisions.
   - `PROJECT_STATE.md` — current focus/open tasks, overwritten each session.
   - `ROADMAP.md` — planned work, updated only when priorities change.
   Also ensures `.github/copilot-instructions.md` has three sections: Persistent Project
   Memory, Project Guidelines (3 bullets: manual commit review, build/test verification, no
   auto-commit/push), and Response Guidelines (concise by default, with 5 stated exceptions).
2. **End Session** — cheap end-of-session snapshot. Overwrites `PROJECT_STATE.md` only;
   touches `DESIGN_DECISIONS.md`/`CODE_SUMMARY.md` only if something genuinely non-obvious
   happened. Does NOT re-scan the whole codebase (low-token by design).
3. **Initialize** — one-time setup per project. Creates two tiny local pointer files:
   - `.github/prompts/bootstrap.prompt.md`
   - `.github/prompts/end-session.prompt.md`
   Each just says "invoke this skill, run workflow X" — no logic duplicated locally, so the
   skill remains the single source of truth. Asks before overwriting if either file already
   exists with different content.

## How to invoke (short local triggers, after Initialize has run once per project)
- `/bootstrap` (or whatever your local prompt-file trigger convention is)
- `/end-session`
- One-time setup: "Use the project-memory-management skill, run Initialize."

## Key design decisions (why it's built this way)
- **Personal/global, not per-repo** — solves the original version-drift problem entirely:
  there's only ever one copy, so there's nothing to sync or fall out of date.
- **Scope restriction** — the skill will never create a new repository and never touches
  anything outside the current project folder or its own skill folder. Added after an early
  build attempt accidentally created files at `C:\CopilotBootstrapTemplates\` (a stale
  reference from an abandoned earlier design).
- **Path resolution via `git rev-parse --show-toplevel`** — all paths (`docs/`,
  `.github/...`) are resolved to the actual repository root via a real terminal command, not
  guessed relative to whichever project folder happens to be active. Added after Bootstrap
  once wrote `copilot-instructions.md` into a nested project subfolder instead of the true
  repo root, on a solution with a `RepoRoot/RepoRoot/*.csproj`-style nested layout.
- **Frontmatter `description` kept under 1024 characters** — Copilot silently disables a
  skill (shows a red error icon in the Skills panel) if the description exceeds this limit.
  Found the hard way after an early version grew too long from added detail.
- **"Do not commit/push automatically" is its own explicit bullet**, separate from "manual
  commit review" — the two aren't the same guarantee (review-after vs. gatekeeping-before),
  and this project's owner had a prior incident of Copilot corrupting code unexpectedly on
  another project, so an explicit stop-before-committing rule was added deliberately.
- **Global personal `copilot-instructions.md` can bleed into generated files** — e.g. git
  commit identity rules defined globally will appear in a project's Project Guidelines section
  even though the skill's own spec only calls for 3 specific bullets. This is expected
  behavior (Copilot blending global + local context), not a bug — decide per-project whether
  that's wanted.
- **No Solution Items registration** — an earlier version of this skill added `docs/` as a
  Solution Items folder in the `.slnx`/`.sln` on its own initiative (never requested). Removed
  deliberately — the skill should never modify solution/project files, only `docs/` and
  `.github/`.

## Known limitations
- Requires a `.git` directory (or a top-level `.sln`/`.slnx` as fallback) to resolve the repo
  root — works for any repo type, not just .NET, since this skill itself doesn't touch code.
- Doesn't know or care about git identity per-project — that's left in the global personal
  `copilot-instructions.md` (`C:\Users\sveluswa\copilot-instructions.md`), not this skill.

## Tested on
- GitContextSwitcher (clean init, and re-init/switch scenarios)
- VoiceType (recovery-from-corrupted-.github scenario, with `.github.bak` handling)
