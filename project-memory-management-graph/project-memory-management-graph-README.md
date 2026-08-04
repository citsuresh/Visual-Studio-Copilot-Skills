# project-memory-management-graph — README

## What this is
The graph-enabled sibling of `project-memory-management`. Does everything that skill does,
plus builds and maintains a Roslyn-based code knowledge graph via the standalone `GraphTools`
executables. Intended for large/complex solutions where a call-graph/symbol-dependency view
adds real value beyond the four memory docs (e.g. Itron's FDM solution — 24 projects, ~2M
LOC), but the user decided to use it for all .NET projects (small ones too), since the value
is Copilot being able to query it when needed, not the user consuming it directly — the extra
build time (~1 min even at FDM scale) was judged an acceptable tradeoff.

## Skill self-versioning (introduced 2026-08-04)
Independently of any single project's code/graph, the SKILL.md file itself has a version
(`CURRENT_SKILL_VERSION`, currently `1`). Every time any of the four workflows runs against a
project, it first does a cheap "Workflow 0: Version Check": read a marker
(`<!-- project-memory-management-graph: skill-version=<N> -->`) stored as the first line of
that project's `.github/copilot-instructions.md` "Persistent Project Memory" section, and
compare it to the skill's current version. If the project is behind (or has no marker at all —
treated as version 0), the user is told what changed (from the in-skill changelog) and asked
whether to re-run Bootstrap now before continuing — no manual per-project file edits needed.
This solves the problem of the skill being updated (e.g. a workflow step added/changed) while
many already-bootstrapped projects are still running against the old behavior with no way to
know that without manually diffing SKILL.md against what was last run per project.

## Location
`C:\Users\sveluswa\.copilot\skills\project-memory-management-graph\SKILL.md`

Personal/global skill, same as the plain variant — applies to every project unless you
deliberately keep using the plain skill for a non-.NET project instead (this skill requires a
`.sln`/`.slnx`, since Bootstrap's graph step needs one to hand to GraphTools).

## Companion tool: GraphTools
Standalone solution at `C:\MyFiles\Git\GraphTools\GraphTools.sln`, built independently, NOT
copied into the skill folder (deliberately — avoids the same version-drift problem the
original sync-tool project existed to solve; the skill just references the built exe by
absolute path, so rebuilding GraphTools automatically updates what the skill uses next run).

- `GraphTools.Core` — shared models, JSON serialization, Roslyn workspace-loading logic.
- `GraphTools.Builder.exe` (`GraphTools.Builder\bin\Debug\net8.0\`) — builds/updates the graph.
  Modes: `--mode full` (complete rebuild), `--mode incremental` (only reanalyzes changed
  files), `--diff` (compares two graph JSON files, no Roslyn needed).
- `GraphTools.Query.exe` (`GraphTools.Query\bin\Debug\net8.0\`) — queries a symbol without
  loading the whole graph. Supports `--symbol`, `--direction callers/callees`, and
  `--list-symbols --project <name>` for browsing.

## Output files
`docs/full-graph.json` and `docs/project-dependencies.json` — deliberately placed inside
`docs/` alongside the four memory markdown files, so all Copilot inputs live in one folder.
**Not meant to be committed to git** — regenerable in ~1 minute even at large scale, and
`full-graph.json` can be tens of MB with noisy diffs on every regeneration. Add both to
`.gitignore` (or gitignore the whole `docs/` folder if the project's docs shouldn't be shared
yet — e.g. FDM, until the team formally adopts this workflow).

- `project-dependencies.json` — small, project-level only (which project references which).
  Meant to always be loaded in full.
- `full-graph.json` — symbol/method-level call graph. NEVER meant to be read wholesale —
  always query it via `GraphTools.Query.exe` for a specific symbol ("query, don't dump").
- `docs/graph-viewer.html` — a static, self-contained HTML file (D3.js via CDN) that lets a
  developer visually explore the graph in a browser: opens showing a project-to-project
  dependency view (from `project-dependencies.json`), click a project to drill into its
  type-level dependency graph (aggregated from `full-graph.json`), click a type to see its
  members in a side panel. Search box filters by name; nodes are draggable.
  - This file is **static and generic** — it contains no per-project data, it just reads
    whichever `full-graph.json`/`project-dependencies.json` sit next to it at open time. So it
    never needs regenerating from the codebase, only copying. The skill bundles one copy of
    it (`graph-viewer.html`, alongside `SKILL.md` in the skill's own folder) and Bootstrap
    Step 10 copies it into each project's `docs/` folder if missing or outdated.
  - **Local-file CORS restriction**: opening the HTML file directly (double-click / `file://`)
    blocks `fetch()` of the neighboring JSON files in most browsers. The viewer detects this
    and falls back automatically to either manual file pickers or drag-and-drop of the two
    JSON files onto the page — both are built in, no server needed.
  - **Visual Studio's built-in "Internal Web Browser" cannot render this file** — it uses a
    legacy IE-era engine with no support for the modern JS (fetch/async/D3 v7) this viewer
    needs, and there is no setting or upgrade path for it (confirmed: it's fixed into the IDE,
    not a swappable component; WebView2 is Microsoft's modern alternative but only applies to
    apps that embed their own browser control, not this built-in tool window). Use "Browse
    With" → Edge or Chrome instead (set as default there to skip the picker dialog next time),
    or View → Other Windows → Web Browser typing the `file:///` path, still selecting a real
    browser engine, not the Internal one.

## What it does — three workflows
Same as the plain skill's Bootstrap/End Session/Initialize, plus:
- **Bootstrap Step 9**: runs `GraphTools.Builder.exe --mode full`, always a fresh full rebuild
  even if a graph already exists.
- **Bootstrap Step 10**: ensures `docs/graph-viewer.html` exists (copied from the skill's own
  bundled copy, not regenerated) — see Output files below.
- **End Session Step 5**: runs `--mode incremental` against the existing graph, but only if
  one already exists (skips silently otherwise — building one fresh is Bootstrap's job).
- Both GraphTools steps require printing the exact resolved command before running it, and
  require stopping (not silently continuing) on any non-zero exit code or error.

## Key design decisions / lessons learned during build & testing
- **ID scheme for graph nodes**: fully-qualified name, with parameter types included for
  methods/indexers (to distinguish overloads) and return type included specifically for
  `op_Implicit`/`op_Explicit` conversion operators (the one case C# allows overloading by
  return type alone). Generic methods get a `` `N `` arity suffix. Three real ID-collision
  bugs were found and fixed in sequence this way (indexers, conversion operators, generic
  arity) before a comprehensive audit + direct duplicate-ID scan confirmed none remain.
- **Incremental mode change-detection excludes `obj/`/`bin/` paths** — MSBuildWorkspace
  triggers a design-time build on load for WPF/XAML projects, which regenerates `.g.cs` files
  under `obj/` every time regardless of real edits, making every incremental run falsely
  detect those as "changed." Fixed by excluding `obj`/`bin` path segments from the scan.
- **Timing is not a concern at real scale** — full-mode took ~60 seconds on FDM (24 projects,
  ~2M LOC, 34,695 nodes / 65,550 edges). Originally estimated 15-60+ minutes; actual
  performance was far better. No need to treat this as a background/overnight job.
- **Legacy/non-SDK projects degrade gracefully, not silently** — FDM had ~9 projects with
  MSBuild workspace-evaluation warnings or one genuine build misconfiguration (a
  `TargetFrameworkVersion=v4.0` project referencing a 4.5+-only assembly). Verified via
  per-project node-count comparison against clean-build baselines that none of this caused
  meaningful data loss — Roslyn's partial-failure recovery still produced usable output in
  every case.
- **NuGet**: this environment's org NuGet feed initially returned 401 for
  `Microsoft.CodeAnalysis.*` packages; worked around with a local `NuGet.Config` scoped to the
  GraphTools folder pointing at nuget.org. Confirmed installable via VS's Package Manager UI
  with all sources enabled — worth periodically re-checking whether the org feed issue was a
  stale credential rather than a policy block.

## Known limitations
- Requires a `.sln`/`.slnx` — won't work on non-.NET projects (use the plain skill instead).
- Only tested on Windows/.NET Framework+.NET 8 mixed solutions so far; not stress-tested
  across multiple developer machines or non-WPF/non-legacy project shapes.
- The 664-vs-572 node-count discrepancy seen once during testing on GitContextSwitcher was
  traced to the user's own uncommitted, later-reverted local code changes between test runs —
  not a GraphTools bug (confirmed via git history showing no relevant commits, and by process
  of elimination against known bug classes already fixed).

## Tested on
- Synthetic 2-class sample project (initial mechanics validation)
- GitContextSwitcher (full/incremental/diff/query modes; skill-driven Bootstrap/End Session
  end-to-end, including a switch-from-plain-skill scenario)
- FDM (Itron.Fdm.Mobile.SystemWorkflows.OpenWayCOSEM.PC.sln — 24 projects, ~2M LOC): full-mode
  timing/feasibility, incremental mode, diff mode, all three ID-collision bug fixes
- `graph-viewer.html`: manually placed next to real GitContextSwitcher output and confirmed
  working in Edge (auto-load and drag-and-drop fallback both verified); confirmed broken in
  VS's Internal Web Browser (expected, documented above) — not yet tested via the automated
  Bootstrap Step 10 copy path itself, worth confirming on the next real Bootstrap run.
