---
name: project-memory-management-graph
description: 'Manage persistent, low-token project memory (docs/CODE_SUMMARY.md, DESIGN_DECISIONS.md, PROJECT_STATE.md, ROADMAP.md) plus a Roslyn-based code knowledge graph (full-graph.json, project-dependencies.json via GraphTools), wired into copilot-instructions.md. For large/complex solutions. Use for: Bootstrap (start of session or first-time setup, builds full graph), End Session (cheap snapshot, incremental graph update), Initialize (one-time setup creating local prompt files). Scoped to the current project only; never creates a repo.'
---
# Project Memory Management (Graph-Enabled)

This skill has three workflows: **Bootstrap** (start of session / first-time setup),
**End Session** (end of session, cheap snapshot), and **Initialize** (one-time project setup
that wires this skill into a project's own prompt files). Use Bootstrap when the four memory
files don't exist yet, or when the user asks to (re)initialize project memory. Use End Session
at the close of a working session to record what happened. Use Initialize when the user asks
to set up this skill / project memory prompts in a new project.

This is the graph-enabled variant, intended for large/complex solutions. It does everything
the plain `project-memory-management` skill does, plus building and maintaining a Roslyn-based
code knowledge graph via the standalone `GraphTools` executables.

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

- GraphTools executables are located at:
  - `C:\MyFiles\Git\GraphTools\GraphTools.Builder\bin\Debug\net8.0\GraphTools.Builder.exe`
  - `C:\MyFiles\Git\GraphTools\GraphTools.Query\bin\Debug\net8.0\GraphTools.Query.exe`
- The graph output files (`full-graph.json`, `project-dependencies.json`) live inside `docs/`,
  alongside the four memory markdown files — this keeps all Copilot inputs in one place.
- Before running `GraphTools.Builder.exe`, confirm the executable exists at the path above; if
  it doesn't, stop and tell the user rather than attempting to build or locate it yourself.
- Print the exact command being run (with resolved absolute paths) before executing it, and
  report the wall-clock time taken and the resulting node/edge counts afterward.
- If `GraphTools.Builder.exe` exits with a non-zero exit code or prints an error, stop and
  report the full error to the user — do not treat a partial/failed graph as success, and do
  not retry automatically.
- To check whether `docs/full-graph.json` exists before querying it, do NOT use `file_search`
  or any filename-index/workspace search tool as the existence check — an empty result from
  those tools is not reliable evidence of absence (the file can be excluded from search
  indexing, or the query string may not match how the tool tokenizes paths). Instead, confirm
  existence with a direct file read (`get_file`) or a terminal existence check (e.g.
  `Test-Path`), or simply invoke `GraphTools.Query.exe` directly and treat a file-not-found
  error from the tool itself as the existence signal. If any document already read this session
  (e.g. `docs/PROJECT_STATE.md`) states the graph was recently built or rebuilt, that is
  stronger evidence than an ambiguous or empty search result — do not fall back to search/grep
  tools without first reconciling that contradiction.

### GraphTools.Query.exe usage (for on-demand graph lookups, not just Bootstrap/End Session)

Use these whenever the Persistent Project Memory rule above says to prefer the graph over a
general search tool:

```
GraphTools.Query.exe --graph "<repo root>\docs\full-graph.json" --symbol "<fully-qualified-id>"
GraphTools.Query.exe --graph "<path>" --symbol "<id>" --direction callers
GraphTools.Query.exe --graph "<path>" --symbol "<id>" --direction callees
GraphTools.Query.exe --graph "<path>" --list-symbols --project "<project name>"
```

- Use `--list-symbols --project` first if the exact symbol ID isn't already known, to discover
  it before querying it directly.
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
   equivalent) the actual current absolute path of `GraphTools.Query.exe` on this machine (see
   "GraphTools invocation" above). Use that confirmed path inline in the template text — do not
   write the section referencing the tool by name alone, since a future session reading only
   `copilot-instructions.md` (not this skill file) has no other way to find it.

   Update (or create) the repo-scoped `.github/copilot-instructions.md` to add or refresh a
   "Persistent Project Memory" section stating: this section must be fully regenerated
   (overwritten) on every Bootstrap run, regardless of whether `copilot-instructions.md` or this
   section already exists — unlike "Project Guidelines" (Step 7) and "Response Guidelines"
   (Step 8), which ARE merge-safe/additive-only, this section is NOT merge-safe and should not
   be skipped just because the file already exists.
   - If it exists, read `docs/CODE_SUMMARY.md` and `docs/DESIGN_DECISIONS.md` before exploring
	 the codebase with search tools for a new task. If these files do not exist, fall back to
	 normal exploration — their absence is not an error.
   - If it exists, read `docs/PROJECT_STATE.md` and `docs/ROADMAP.md` when the user asks
	 "do you remember", references prior work, or asks what's next.
   - If it exists, read `docs/domain-lookup-patterns.md` when a task requires domain
	 conventions, naming schemes, or business logic that the graph doesn't represent — check it
	 before falling back to manual exploration or a fresh graph query.
   - If it exists, mention `docs/full-graph.json`/`docs/project-dependencies.json` are
	 available and should be queried via `GraphTools.Query.exe` (located at `<confirmed absolute
	 path>`) (never read wholesale). This is a default, not a judgment call: before using a
	 general-purpose search tool (text search, symbol search, grep, or similar) to locate a
	 class/interface/enum, find a method's definition, find its callers, find its callees, check
	 how two types relate, or otherwise answer "where is X" / "what uses X" for anything that is
	 a C# symbol, first check whether `docs/full-graph.json` exists in this project, and if so,
	 query it via `GraphTools.Query.exe` (located at `<confirmed absolute path>`) instead of a
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
   `GraphTools.Builder.exe --solution "<resolved repo .sln/.slnx path>" --output "<repo root>\docs\full-graph.json" --mode full`.
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
   `GraphTools.Builder.exe --solution "<resolved repo .sln/.slnx path>" --output "<repo root>\docs\full-graph.json" --mode incremental --graph "<repo root>\docs\full-graph.json"`.
   If `full-graph.json` does not exist, skip this step silently (do not build it fresh here —
   that is Bootstrap's job).

7. Report back a short (2-5 line) summary of what was updated (or confirm nothing needed
   updating), including the graph's changed-file count and updated node/edge counts if step 6
   ran.

## Workflow 3: Initialize

One-time setup that wires this skill into a project via its own prompt files, so the user can
invoke Bootstrap/End Session through short project-local prompts.

### Steps

1. Determine the target content for `.github/prompts/bootstrap.prompt.md`: an instruction to
   invoke the project-memory-management-graph skill and run its Bootstrap workflow exactly as
   defined.

2. Determine the target content for `.github/prompts/end-session.prompt.md`: an instruction to
   invoke the project-memory-management-graph skill and run its End Session workflow exactly as
   defined.

3. Before writing either file, check if it already exists:
   - If it does not exist, create it with the target content.
   - If it exists and its content matches the target content, leave it as-is.
   - If it exists and its content differs from the target content, do NOT overwrite it
     silently — tell the user the file already exists (with its current content or a summary
     of the difference) and ask whether to overwrite it. Only overwrite if the user confirms.

4. After both files are created/confirmed, show the user the final content of both
   `.github/prompts/bootstrap.prompt.md` and `.github/prompts/end-session.prompt.md`, and
   confirm both were created (or left unchanged, per user's choice).

5. Ask the user: "Do you want to run Bootstrap now?"
   - If yes, run the Bootstrap workflow immediately, in this same session.
   - If no, stop and wait for further instructions — do not run Bootstrap automatically.
