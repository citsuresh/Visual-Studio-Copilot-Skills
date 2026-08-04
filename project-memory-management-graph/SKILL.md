---
name: project-memory-management-graph
description: 'Manage persistent, low-token project memory (docs/CODE_SUMMARY.md, DESIGN_DECISIONS.md, PROJECT_STATE.md, ROADMAP.md) plus a Roslyn-based code knowledge graph (full-graph.json, project-dependencies.json via GraphTools), wired into copilot-instructions.md. For large/complex solutions. Use for: Begin Session (optional, cheap session-start readiness check), Bootstrap (start of session or first-time setup, builds full graph), End Session (cheap snapshot, incremental graph update), Initialize (one-time setup creating local prompt files). Every invocation first runs a cheap version check against a per-project marker and offers to re-run Bootstrap if the skill has been updated since that project was last synced. Begin Session is not a substitute for Bootstrap or End Session. Scoped to the current project only; never creates a repo.'
---
# Project Memory Management (Graph-Enabled)

This skill has four workflows: **Begin Session** (optional, cheap session-start readiness
check), **Bootstrap** (start of session / first-time setup), **End Session** (end of session,
cheap snapshot), and **Initialize** (one-time project setup that wires this skill into a
project's own prompt files). Use Begin Session to explicitly force project memory inputs into
context at session start when auto-load may be inconsistent. Use Bootstrap when the core memory
and graph files do not exist yet, or when the user asks to (re)initialize project memory. Use
End Session at the close of a working session to record what happened. Use Initialize when the
user asks to set up this skill / project memory prompts in a new project. Begin Session is not
a substitute for Bootstrap or End Session.

This is the graph-enabled variant, intended for large/complex solutions. It does everything
the plain `project-memory-management` skill does, plus building and maintaining a Roslyn-based
code knowledge graph via the standalone `GraphTools` executables.

## Skill Version

This skill is versioned independently of any project it's used in, so that when the skill
itself gains/changes a workflow step (not just when GraphTools or project code changes), every
previously-set-up project can detect it's running against stale instructions and offer to
re-sync — without the user having to remember or manually redo anything per project.

- `CURRENT_SKILL_VERSION = 3`. Bump this integer whenever an edit to this SKILL.md file changes
  what Initialize, Bootstrap, End Session, or Begin Session actually *do* in a way that a
  project set up under the old version would benefit from or require re-running one of them to
  pick up (e.g.: a new step is added/removed from Bootstrap, Initialize's generated prompt file
  content changes, the `copilot-instructions.md` template content materially changes, a new
  output file is introduced, a workflow's trigger conditions change). Do NOT bump for
  wording-only clarifications, typo fixes, or comment changes that don't alter behavior.
- Each project this skill has been run against stores the version it was last synced at, as an
  HTML comment marker on the first line of the "Persistent Project Memory" section of that
  project's own `.github/copilot-instructions.md`:
  `<!-- project-memory-management-graph: skill-version=<N> -->`
  This is the only per-project storage this mechanism needs — no other file or location is used
  to track this. Never hand-edit this marker; only Bootstrap writes/refreshes it (see Bootstrap
  Step 6, which now also owns writing this marker as the first line of that section).
- Changelog (append one entry per version bump; never delete prior entries):
  - v1 — introduced this versioning/staleness-check mechanism (this entry itself). Projects
    with no marker at all (set up before v1 existed) are treated as version 0 — always stale.
  - v2 — GraphTools invocation now goes through `tools\Invoke-GraphTools.ps1` (a wrapper script
    inside the GraphTools repo) instead of calling `GraphTools.Builder.exe`/
    `GraphTools.Query.exe` directly. Rationale: a shell launched from Visual Studio can inherit
    a `DOTNET_ROOT` override pinned to VS's own bundled runtime, which hides the machine-wide
    net8.0 runtime GraphTools targets and makes the raw exe fail to launch even though nothing
    is actually broken. The wrapper clears that override before delegating to the real exe.
    Every command template in "GraphTools invocation", Bootstrap Step 9, and End Session Step 6
    changed to call the wrapper. Projects bootstrapped under v1 have stale
    `copilot-instructions.md` text pointing at the raw `.exe` paths and should re-run Bootstrap.
  - v3 — Begin Session gains a new Step 2a: a cheap, read-only graph-staleness check. If
    `docs/project-dependencies.json` exists, read its `CommitSha` field and compare it against
    the repo's live `git rev-parse HEAD`, then report plainly whether the graph matches, is
    behind, or predates commit-tracking (field missing/null). This is a report-only comparison —
    no diffing, no commit-distance calculation, no automatic rebuild or Bootstrap suggestion.
    Bootstrap and End Session are unaffected; they already regenerate/update the graph directly
    and don't need this comparison.

**Before finishing any edit to this file that changes what a workflow does: did you bump
`CURRENT_SKILL_VERSION` and add a changelog entry above? If unsure, re-read the criteria above
before finishing.**

## Workflow 0: Version Check (runs automatically, first, for every workflow invocation)

Before running Begin Session, Bootstrap, End Session, or Initialize, always do this cheap check
first — it applies uniformly to all four, including Initialize itself (e.g. a first-time setup
should never be "stale," but should still record the current version).

### Steps

1. Resolve the repo root (see "Path resolution" above) and check whether
   `.github/copilot-instructions.md` exists.
   - If it does not exist (true first-time use), there is nothing to check yet — skip silently
     and proceed with whatever workflow was requested (this is normal for a first Initialize or
     first Bootstrap run).

2. If it exists, read it and look for the marker
   `<!-- project-memory-management-graph: skill-version=<N> -->` as the first line of the
   "Persistent Project Memory" section.
   - If the section exists but the marker is missing, treat the stored version as `0`.
   - If the section doesn't exist at all, treat the stored version as `0`.

3. Compare the stored version to `CURRENT_SKILL_VERSION` (defined above).
   - If stored version `== CURRENT_SKILL_VERSION`, proceed silently with the originally
     requested workflow — do not mention anything to the user.
   - If stored version `< CURRENT_SKILL_VERSION`, the project is stale. Tell the user plainly:
     the project was last synced at skill version `<stored>`, the skill is now at
     `<CURRENT_SKILL_VERSION>`, and list the changelog entries strictly after `<stored>` up to
     current so they know what changed and why it matters. Then ask (via the `ask_user` tool,
     not free text) whether to run Bootstrap now to re-sync before continuing. Recommended
     choice: re-run Bootstrap (it fully regenerates the "Persistent Project Memory" section,
     including the version marker, and is idempotent/merge-safe for the four memory docs per
     its own rules) — only suggest also re-running Initialize if a changelog entry between
     `<stored>` and current explicitly says the prompt-file templates changed.
   - If the user confirms, run Bootstrap (and Initialize too, only if indicated) now, then
     continue with whatever workflow was originally requested (unless the originally requested
     workflow *was* Bootstrap, in which case it has now already run — don't run it twice).
   - If the user declines, proceed with the originally requested workflow as-is without
     upgrading — do not force the upgrade, and do not ask again later in the same session for
     the same project.

4. This check must stay cheap: a single file read plus a string/regex comparison — no codebase
   scanning, no GraphTools invocation, regardless of outcome.

## Scope restriction (applies to all workflows)

- Never create a new repository, anywhere, under any circumstance.
- Never read from, write to, or delete any file or folder outside of: (a) the current
  project's own folder, or (b) this skill's own folder under the personal skills directory
  (`~/.copilot/skills/project-memory-management-graph/`), or (c) the GraphTools install
  location (`C:\MyFiles\Git\GraphTools\`), and only to invoke its executables — never to modify
  files inside it.
- If a step would require touching a path outside this scope, stop and ask the user first
  instead of proceeding.

## Path resolution (applies to all workflows)

- All paths referenced in this skill (`docs/`, `.github/copilot-instructions.md`,
  `.github/prompts/`, `full-graph.json`, `project-dependencies.json`) are relative to the
  **repository root** — the folder containing the `.git` directory, or, if `.git` isn't
  visible/accessible, the folder containing the top-level `.sln`/`.slnx` file.
- Do NOT resolve these paths relative to the currently active/focused project's own subfolder.
  This matters especially for solutions with a nested layout (e.g. `RepoRoot/RepoRoot/*.csproj`),
  where the repo root and an individual project folder can easily be confused.
- Before any file operation, resolve the repo root to an ABSOLUTE path using a terminal command
  (e.g. `git rev-parse --show-toplevel`, or, if `.git` isn't available, locate the parent folder
  of the top-level `.sln`/`.slnx` file). Do this once at the start of the workflow.
- Always pass the resulting ABSOLUTE path to file read/write tools and to GraphTools' `--solution`,
  `--output`, and `--graph` arguments. Do NOT pass paths relative to the solution/workspace
  directory — this differs from the repo root in nested layouts and will silently write to the
  wrong location without erroring.
- Before writing any file, state the resolved absolute path you are about to write to, so the
  user can confirm it is correct before the write happens.

## GraphTools invocation (applies to Bootstrap and End Session)

- GraphTools must be invoked through its wrapper script, not the raw executables directly:
  - `C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1 -Tool Builder -- <args>`
  - `C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1 -Tool Query -- <args>`
  - The wrapper clears any inherited `DOTNET_ROOT` environment variable before invoking the
    real exe underneath (`GraphTools.Builder\bin\Debug\net8.0\GraphTools.Builder.exe` /
    `GraphTools.Query\bin\Debug\net8.0\GraphTools.Query.exe`). This works around a real failure
    mode where a shell launched from Visual Studio (Insiders) inherits a `DOTNET_ROOT` override
    pinned to VS's own bundled runtime, which hides the machine-wide net8.0 runtime GraphTools
    targets and makes the raw `.exe` fail to launch even though nothing is actually wrong with
    it. Always use the wrapper — never call `GraphTools.Builder.exe`/`GraphTools.Query.exe`
    directly, even if it seems to work in a given session.
- The graph output files (`full-graph.json`, `project-dependencies.json`) live inside `docs/`,
  alongside the four memory markdown files — this keeps all Copilot inputs in one place.
- Before running the wrapper, confirm both it and the underlying exe it targets exist at the
  paths above; if either is missing, stop and tell the user rather than attempting to build or
  locate it yourself.
- Print the exact command being run (with resolved absolute paths) before executing it, and
  report the wall-clock time taken and the resulting node/edge counts afterward.
- If the wrapper/exe exits with a non-zero exit code or prints an error, stop and report the
  full error to the user — do not treat a partial/failed graph as success, and do not retry
  automatically.
- To check whether `docs/full-graph.json` exists before querying it, do NOT use `file_search`
  or any filename-index/workspace search tool as the existence check — an empty result from
  those tools is not reliable evidence of absence (the file can be excluded from search
  indexing, or the query string may not match how the tool tokenizes paths). Instead, confirm
  existence with a direct file read (`get_file`) or a terminal existence check (e.g.
  `Test-Path`), or simply invoke the Query wrapper directly and treat a file-not-found error
  from the tool itself as the existence signal. If any document already read this session
  (e.g. `docs/PROJECT_STATE.md`) states the graph was recently built or rebuilt, that is
  stronger evidence than an ambiguous or empty search result — do not fall back to search/grep
  tools without first reconciling that contradiction.

### GraphTools Query usage (for on-demand graph lookups, not just Bootstrap/End Session)

Use these whenever the Persistent Project Memory rule above says to prefer the graph over a
general search tool:

```
C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1 -Tool Query -- --graph "<repo root>\docs\full-graph.json" --symbol "<fully-qualified-id>"
C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1 -Tool Query -- --graph "<path>" --symbol "<id>" --direction callers
C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1 -Tool Query -- --graph "<path>" --symbol "<id>" --direction callees
C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1 -Tool Query -- --graph "<path>" --list-symbols --project "<project name>"
```

- Use `--list-symbols --project` first if the exact symbol ID isn't already known, to discover
  it before querying it directly.
- Use the exact command templates shown above verbatim, substituting only the path/symbol/project
  values — do not guess at flag names or invent flags (e.g. there is no `--callers` flag; use
  `--symbol "<id>" --direction callers` instead; there is no `--filter` flag on `--list-symbols`,
  only `--project`). Do NOT rely on `GraphTools.Query.exe --help` for syntax guidance — it does
  not reliably print usable usage text. If a command using the exact templates above still
  errors, report the full error rather than guessing at alternative flags.
- All output is JSON — parse it, don't dump it back verbatim to the user unless they ask to see
  the raw output.
- If the query returns a "symbol not found" error, do not assume the symbol doesn't exist in
  the codebase — the graph may be stale (e.g. a recent Bootstrap/End Session hasn't run yet).
  Mention this possibility before falling back to a general search tool.

## Domain lookup patterns capture (applies whenever graph-first lookups happen, not just Bootstrap)

- Trigger: during an exploratory or "how does this work" task, the graph alone was not
  sufficient to answer efficiently because the answer depended on domain conventions, naming
  patterns, or business logic — not just structural facts the graph represents (who calls
  what, what implements what). Example: understanding an OBIS-code lookup convention or a
  domain-specific naming scheme that required extra manual investigation beyond graph queries.
- When this happens, propose recording the pattern, then only add or update
  `docs/domain-lookup-patterns.md` (same location convention as the other docs files) after the
  user explicitly confirms the pattern is worth recording. Never record it unprompted.
- Do NOT create this file upfront or as an empty placeholder during Bootstrap or on any project
  regardless of size — it must only come into existence the first time a genuine domain lookup
  pattern is actually identified and confirmed. Small/simple projects should never end up with
  an empty version of this file.
- Unlike `docs/CODE_SUMMARY.md` and `docs/DESIGN_DECISIONS.md`, this file is NOT merge-safe or
  auto-refreshed during Bootstrap/End Session — it is manually curated. Do not scan for or
  regenerate its contents automatically; only touch it in direct response to the user
  confirming a specific pattern in the current session.
- Each entry should capture: the domain concept/convention, where/how it's implemented, and why
  a graph query alone wasn't enough to resolve it (so future sessions know when to expect this
  gap and reference the pattern instead of re-discovering it).

## Workflow: Begin Session

Optional, lightweight session-start readiness check. This is a cheap way to deterministically
force key project memory inputs into context when `.github/copilot-instructions.md` auto-load
may be inconsistent. It is not a required ritual, and it is explicitly NOT a substitute for
Bootstrap or End Session.

### Steps

0. Run "Workflow 0: Version Check" above first, before anything else in this workflow.

1. Explicitly read `.github/copilot-instructions.md` via a direct file read tool (`get_file`).
   Do this regardless of whether it appears to already be in context. Do not assume auto-load
   succeeded, and do not use `file_search` or any filename-index/workspace search tool first.

2. Directly check (via `get_file` or a terminal existence check such as `Test-Path`, never
   `file_search` or another filename-index/workspace search tool) whether each of these files
   exists:
   - `docs/CODE_SUMMARY.md`
   - `docs/DESIGN_DECISIONS.md`
   - `docs/PROJECT_STATE.md`
   - `docs/ROADMAP.md`
   - `docs/domain-lookup-patterns.md` (optional; absence is normal, not an error)
   - `docs/full-graph.json`
   - `docs/project-dependencies.json`

2a. If `docs/project-dependencies.json` was found in Step 2, do a cheap, read-only graph-staleness
    check:
    - Read the file (`get_file`) and extract its `CommitSha` field.
    - If `CommitSha` is missing or null (e.g. the graph was built before this field existed, or
      git resolution failed at build time), treat this as "unknown" — not an error, and do not
      attempt to fix or rebuild anything. Report it plainly, e.g. "graph predates
      commit-tracking".
    - If `CommitSha` is present, run `git rev-parse HEAD` in the repo root to get the current
      live commit SHA and compare:
      - Match: the graph is current relative to the last commit — mention this briefly (e.g.
        "graph is up to date with the current commit").
      - Mismatch: report plainly, e.g. "graph was built from commit `<short SHA>`; current
        commit is `<short SHA>`". Do NOT attempt to determine how many commits apart they are,
        run a diff, or judge whether this matters — that's for the user to decide.
    - This check is a single `get_file` read plus one `git rev-parse HEAD` call — no rebuilding,
      no `GraphTools.Builder.exe`/wrapper invocation, and no automatically suggesting Bootstrap
      because of what this check finds. If `docs/project-dependencies.json` was missing in Step
      2, skip this step entirely (already covered by Step 2's existence report).

3. Report back briefly: which of the files above were found and which were missing, the Step 2a
   graph-staleness result (if applicable), plus a one-line readiness summary (for example, the
   current focus line from `docs/PROJECT_STATE.md` if present). Keep this short: this is a
   readiness check only, not a full project-state summary and not a re-derivation of
   `CODE_SUMMARY.md` or End Session output.

4. Do NOT rebuild the graph, run `GraphTools.Builder.exe`, re-scan the codebase, or create any
   missing file as part of Begin Session. That work belongs to Bootstrap. If the core memory
   files are missing entirely, say so plainly and suggest running Bootstrap. Step 2a's staleness
   result is informational only — never let it push you toward auto-suggesting Bootstrap.

## Workflow 1: Bootstrap (Project Memory Bootstrap)

Bootstrap persistent project memory for this codebase so future chat sessions can be
resumed cheaply (low token usage) instead of re-exploring the codebase or re-summarizing
conversation history every time.

This workflow is project-agnostic and idempotent for the four memory files
(`docs/CODE_SUMMARY.md`, `DESIGN_DECISIONS.md`, `PROJECT_STATE.md`, `ROADMAP.md`): if they
already exist, review and update them incrementally instead of overwriting/duplicating content.
This incremental/merge-safe rule applies ONLY to those four files — it does not apply to the
"Persistent Project Memory" section of `.github/copilot-instructions.md` (see Step 6, which is
fully regenerated every run) nor override the merge-safe handling separately specified for
"Project Guidelines"/"Response Guidelines" in Steps 7-8.

### Steps

0. Run "Workflow 0: Version Check" above first, before anything else in this workflow (if the
   version check itself already ran Bootstrap as part of resolving staleness, skip re-running
   steps 1-12 below — that Bootstrap run already satisfies this invocation).

1. Discover structure: use `get_projects_in_solution` and `get_files_in_project` (or
   equivalent workspace exploration) to enumerate projects, key classes/services, and
   dependencies between components. Do not read every file — focus on structural/entry-point
   types (interfaces, services, view models, main windows/controllers).

2. Create or update `docs/CODE_SUMMARY.md` containing:
   - A short project overview (1-3 sentences: what the app/library does, tech stack, target
	 framework).
   - A Mermaid `graph LR` dependency graph of projects/components.
   - A symbol index table (`Symbol | File | Responsibility`) per project, limited to
	 structural/entry-point classes and services — not every file.
   - A "Key Flows" section describing 2-5 important end-to-end flows as short arrow chains
	 (e.g., `A -> B -> C`).
   - Keep this file concise: prefer tables/graphs over prose.

3. Create or update `docs/DESIGN_DECISIONS.md` (append-only, dated log) seeded with any
   non-obvious architectural/design choices you can infer from the existing code or recent
   changes. Each entry: Decision, Rationale, Alternatives considered (if any). Never delete or
   rewrite prior entries — only append new ones, and if a decision is reversed, add a new
   entry referencing the old one instead of removing it.

4. Create or update `docs/PROJECT_STATE.md`: current focus, open tasks/bugs, recently changed
   files. State explicitly in the file that it is overwritten (not appended) at the end of
   each working session.

5. Create or update `docs/ROADMAP.md`: upcoming planned work as a prioritized checklist
   (e.g., Near-term / Backlog sections). State explicitly that this file is edited
   deliberately when priorities change, not automatically overwritten each session.

6. Before writing the "Persistent Project Memory" section below, confirm via `Test-Path` (or
   equivalent) that the GraphTools wrapper script (`tools\Invoke-GraphTools.ps1`) exists at the
   path given under "GraphTools invocation" above. Use that confirmed wrapper path inline in the
   template text — do not write the section referencing the tool by name alone, since a future
   session reading only `copilot-instructions.md` (not this skill file) has no other way to
   find it.

   Update (or create) the repo-scoped `.github/copilot-instructions.md` to add or refresh a
   "Persistent Project Memory" section stating: this section must be fully regenerated
   (overwritten) on every Bootstrap run, regardless of whether `copilot-instructions.md` or this
   section already exists — unlike "Project Guidelines" (Step 7) and "Response Guidelines"
   (Step 8), which ARE merge-safe/additive-only, this section is NOT merge-safe and should not
   be skipped just because the file already exists.

   As the very first line of this section (before the `## Persistent Project Memory` heading
   itself), always write/refresh the skill version marker:
   `<!-- project-memory-management-graph: skill-version=<CURRENT_SKILL_VERSION> -->`
   (see "Skill Version" above). This is the only place this marker is written — every Bootstrap
   run stamps the version current at the time it ran, which is how "Workflow 0: Version Check"
   detects staleness in later sessions.
   - If it exists, read `docs/CODE_SUMMARY.md` and `docs/DESIGN_DECISIONS.md` before exploring
	 the codebase with search tools for a new task. If these files do not exist, fall back to
	 normal exploration — their absence is not an error.
   - If it exists, read `docs/PROJECT_STATE.md` and `docs/ROADMAP.md` when the user asks
	 "do you remember", references prior work, or asks what's next.
   - If it exists, read `docs/domain-lookup-patterns.md` when a task requires domain
	 conventions, naming schemes, or business logic that the graph doesn't represent — check it
	 before falling back to manual exploration or a fresh graph query.
   - If it exists, mention `docs/full-graph.json`/`docs/project-dependencies.json` are
	 available and should be queried via the GraphTools wrapper script (located at
	 `<confirmed absolute wrapper path>`, invoked as `<wrapper> -Tool Query -- <args>`) (never
	 read wholesale). This is a default, not a judgment call: before using a
	 general-purpose search tool (text search, symbol search, grep, or similar) to locate a
	 class/interface/enum, find a method's definition, find its callers, find its callees, check
	 how two types relate, or otherwise answer "where is X" / "what uses X" for anything that is
	 a C# symbol, first check whether `docs/full-graph.json` exists in this project, and if so,
	 query it via the wrapper (located at `<confirmed absolute wrapper path>`) instead of a
	 general search tool. This applies even to a simple "find this file/class" request, not only
	 explicit call-graph or architecture questions. This preference applies regardless of how the
	 question is phrased: conceptual/explanatory framings ("explain X", "walk me through X",
	 "how does X work", "describe the Y flow") are NOT exempt just because they aren't literally
	 worded as a find/locate request. The test is whether answering the question requires
	 locating, identifying, or relating specific named C# classes/interfaces/methods — not
	 whether the question is phrased as a lookup. If it does, query the graph first.
   - Fallback: if `docs/full-graph.json` does not exist, if `GraphTools.Query.exe` errors or
	 exits non-zero, or if the graph doesn't contain an answer to the specific question (e.g.
	 the question is about non-code content, file layout, or something the graph doesn't track),
	 fall back to normal search tools and proceed — do not treat a missing/failed graph query as
	 a blocking error.
   - If, during graph-first or domain-lookup work, you notice a recurring friction point (e.g.
	 a manual step done more than once that a structural tool could answer instead), mention it
	 briefly at the end of your response — don't act on it, just note it. Skip this if nothing
	 recurring was noticed; don't proactively search for optimization opportunities outside of
	 graph/domain-lookup work.
   - Update `docs/CODE_SUMMARY.md` when: a new project is added, a new structural class/service
	 is added, a component's responsibility changes, or a project/component dependency changes.
	 Do not update for routine bug fixes or small edits that don't affect structure. Also update
	 its "Key Flows" section when a new end-to-end flow spanning multiple C# symbols is fully
	 traced and confirmed during the session (e.g., via a graph query and/or a domain lookup
	 pattern investigation): add it as a short arrow-chain (e.g., `A -> B -> C -> D`), consistent
	 with the existing entries. Skip if no such flow was traced. Key Flows entries remain short
	 symbol arrow-chains only — no domain-specific details (e.g. specific config/XML file names
	 or device-specific values), which belong in `docs/domain-lookup-patterns.md` instead. If a
	 relevant `docs/domain-lookup-patterns.md` entry already exists for that specific flow (the
	 flow involves a domain convention already documented there), append a short one-line
	 pointer to the Key Flows entry referencing it, e.g. `ImageTransferInitiate ->
	 ImageBlockTransfer -> ImageVerify -> ImageActivate (see domain-lookup-patterns.md for OBIS
	 code mapping)` — this is a pointer only, never pull domain-specific details themselves into
	 CODE_SUMMARY.md. Only add the pointer if a relevant entry genuinely already exists; skip
	 silently (no pointer) if none exists — do not invent, infer, or speculatively cross-reference.
   - Update `docs/DESIGN_DECISIONS.md` (append-only, dated entries) when: a non-obvious
	 architectural/design choice is made, an alternative approach is rejected with a reason, or
	 a past decision is reversed. Never delete prior entries.
   - Update `docs/PROJECT_STATE.md` at the end of a working session to reflect current focus,
	 open tasks, and recently changed files (overwrite, not append).
   - Update `docs/ROADMAP.md` only when priorities/plans deliberately change, not automatically
	 each session.
   - Keep all four files concise — they exist to reduce token usage on future re-reads, not to
	 serve as exhaustive documentation.

7. Ensure a "Project Guidelines" section exists in `.github/copilot-instructions.md`. This
   step is merge-safe: if the section already exists, only add the following 3 bullets if
   they are missing — do not touch or remove any other content already in that section
   (e.g. project-specific instructions that may already be there). If the section does not
   exist, create it with exactly these 3 bullets:
   - Manual commit review before any commit.
   - Build/test verification after every change.
   - Do not commit or push automatically — wait for explicit user confirmation first.

8. Ensure a "Response Guidelines" section exists in `.github/copilot-instructions.md`
   instructing concise, minimal replies by default (no filler, no restating the question, no
   unnecessary preamble), EXCEPT in these cases where full detail is required:
   - Design rationale discussions.
   - Build/error diagnosis.
   - Before any destructive action.
   - When multiple approaches exist.
   - When generating docs/*.md content itself.
   This step is also merge-safe: if the section already exists, only add what's missing
   without removing or rewriting existing content.

9. Build the knowledge graph: run
   `<GraphTools wrapper path> -Tool Builder -- --solution "<resolved repo .sln/.slnx path>" --output "<repo root>\docs\full-graph.json" --mode full`.
   This also produces `project-dependencies.json` in the same `docs/` folder. If
   `full-graph.json` already exists from a prior Bootstrap run, this step still does a fresh
   full rebuild (Bootstrap always rebuilds fully; only End Session uses incremental mode).

10. Ensure `docs/graph-viewer.html` exists: this is a static, self-contained HTML file
	(reads whichever `full-graph.json`/`project-dependencies.json` sit next to it at open time
	— nothing is embedded per-project) that lets a developer open the graph in a browser and
	explore it visually (project-level dependency view, drill into a project's types, click a
	type to see its members). It never needs regenerating from the codebase, only copying.
	- Source file: this skill's own folder, `graph-viewer.html`
	  (`~/.copilot/skills/project-memory-management-graph/graph-viewer.html`).
	- If `docs/graph-viewer.html` does not exist in the target project, copy it there as-is.
	- If it already exists, compare file content against the source: if identical, leave it
	  alone; if different (e.g. an older version), copy the current version over it — this file
	  is fully owned by this skill, unlike the docs/*.md files, so overwriting it is always safe
	  and does not need a confirmation prompt.

11. If any of the four `docs/*.md` memory files already exist from a prior bootstrap, do not
	overwrite blindly: read them first, then merge/update only what's missing or outdated. This
	rule applies ONLY to those four files. It does NOT apply to `.github/copilot-instructions.md`:
	its "Persistent Project Memory" section (Step 6) must always be force-checked and fully
	regenerated/overwritten this run even if `copilot-instructions.md` already exists — never
	skip Step 6 on the grounds that the file already exists. Its "Project Guidelines" (Step 7)
	and "Response Guidelines" (Step 8) sections remain separately merge-safe/additive-only, as
	specified in those steps.

12. Report back a short summary of what was created/updated, the graph's node/edge counts and
	build time, and confirm the build still succeeds.

## Workflow 2: End Session

Cheap companion to the Bootstrap workflow. Run this at the end of a chat session to
snapshot what happened, using only the context already gathered in this session — do NOT
re-scan the whole codebase structure (no `get_projects_in_solution`/`get_files_in_project`
sweep). This keeps the closing update low-token.

### Steps

0. Run "Workflow 0: Version Check" above first, before anything else in this workflow (note:
   if the version check itself triggers a Bootstrap run to resolve staleness, that Bootstrap
   run already overwrites `docs/PROJECT_STATE.md` etc. — still proceed with steps 1-7 below
   afterward, since End Session's own updates reflect this session's work, which is a different
   concern from the version sync).

1. Overwrite `docs/PROJECT_STATE.md` (not append) with, based only on this session's context:
   - Current Focus: what was worked on in this session.
   - Open Tasks / Known Issues: anything left unresolved or explicitly deferred.
   - Recently Changed Files: files created/modified in this session.
   - If `docs/PROJECT_STATE.md` does not exist, skip silently (do not create the full docs set —
	 that is the Bootstrap workflow's job).

2. Only if a genuinely non-obvious design/architecture decision was made in this session and is
   not already captured, append one dated entry to `docs/DESIGN_DECISIONS.md` (Decision,
   Rationale, Alternatives considered). Skip this step entirely if no such decision occurred, or
   if the file does not exist.

3. Only if a structural change occurred in this session (new project, new structural
   class/service, changed responsibility, changed project dependency) and is not already
   reflected, update the relevant section of `docs/CODE_SUMMARY.md` inline. Do not re-derive the
   whole file or re-scan unrelated parts of the codebase. Skip if the file does not exist or if
   no structural change occurred.

   Also update the "Key Flows" section if a new end-to-end flow spanning multiple C# symbols
   was fully traced and confirmed during this session (e.g., via a graph query and/or a domain
   lookup pattern investigation): add it as a short arrow-chain (e.g., `A -> B -> C -> D`),
   consistent with the existing entries. Skip if no such flow was traced. Keep entries as short
   symbol arrow-chains only — no domain-specific details (e.g. specific config/XML file names or
   device-specific values), which belong in `docs/domain-lookup-patterns.md` instead. If a
   relevant `docs/domain-lookup-patterns.md` entry already exists for that specific flow (the
   flow involves a domain convention already documented there), append a short one-line pointer
   to the Key Flows entry referencing it, e.g. `ImageTransferInitiate -> ImageBlockTransfer ->
   ImageVerify -> ImageActivate (see domain-lookup-patterns.md for OBIS code mapping)` — this is
   a pointer only, never pull domain-specific details themselves into CODE_SUMMARY.md. Only add
   the pointer if a relevant entry genuinely already exists; skip silently (no pointer) if none
   exists — do not invent, infer, or speculatively cross-reference.

4. Do not modify `docs/ROADMAP.md` unless the user explicitly discussed a priority/plan change in
   this session.

5. If a domain lookup pattern was identified and explicitly confirmed by the user earlier in
   this session (per the "Domain lookup patterns capture" rule above) but has not yet been
   recorded in `docs/domain-lookup-patterns.md`, record it now as part of End Session wrap-up.
   This is a safety net only — do not scan the session to invent or retroactively identify new
   patterns; only cover a pattern the user already explicitly confirmed earlier but that wasn't
   yet written to the file. Skip this step entirely if no such already-confirmed-but-unrecorded
   pattern exists.

6. If `full-graph.json` exists in `docs/`, update the knowledge graph incrementally: run
   `<GraphTools wrapper path> -Tool Builder -- --solution "<resolved repo .sln/.slnx path>" --output "<repo root>\docs\full-graph.json" --mode incremental --graph "<repo root>\docs\full-graph.json"`.
   If `full-graph.json` does not exist, skip this step silently (do not build it fresh here —
   that is Bootstrap's job).

7. Report back a short (2-5 line) summary of what was updated (or confirm nothing needed
   updating), including the graph's changed-file count and updated node/edge counts if step 6
   ran.

## Workflow 3: Initialize

One-time setup that wires this skill into a project via its own prompt files, so the user can
invoke Begin Session/Bootstrap/End Session through short project-local prompts.

### Steps

0. Run "Workflow 0: Version Check" above first, before anything else in this workflow. Note:
   for a genuinely new project (no `.github/copilot-instructions.md` yet), this is a no-op —
   Initialize itself doesn't write the version marker (only Bootstrap does, in its Step 6), so
   there's nothing to detect as stale on a first-ever run.

1. Determine the target content for `.github/prompts/begin-session.prompt.md`: an instruction to
   invoke the project-memory-management-graph skill and run its Begin Session workflow exactly
   as defined.

2. Determine the target content for `.github/prompts/bootstrap.prompt.md`: an instruction to
   invoke the project-memory-management-graph skill and run its Bootstrap workflow exactly as
   defined.

3. Determine the target content for `.github/prompts/end-session.prompt.md`: an instruction to
   invoke the project-memory-management-graph skill and run its End Session workflow exactly as
   defined.

4. Before writing any of the three files, check if each file already exists:
   - If it does not exist, create it with the target content.
   - If it exists and its content matches the target content, leave it as-is.
   - If it exists and its content differs from the target content, do NOT overwrite it
     silently — tell the user the file already exists (with its current content or a summary
     of the difference) and ask whether to overwrite it. Only overwrite if the user confirms.

5. After all three files are created/confirmed, show the user the final content of
   `.github/prompts/begin-session.prompt.md`, `.github/prompts/bootstrap.prompt.md`, and
   `.github/prompts/end-session.prompt.md`, and confirm all three were created (or left
   unchanged, per user's choice).

6. Ask the user: "Do you want to run Bootstrap and Begin Session now?"
   - If yes, run the Bootstrap workflow first (since it creates the files Begin Session checks
     for), then run Begin Session immediately after, in this same session.
   - If no, stop and wait for further instructions — do not run either automatically.
