---
name: project-memory-management
description: 'Manage persistent, low-token project memory (docs/CODE_SUMMARY.md, DESIGN_DECISIONS.md, PROJECT_STATE.md, ROADMAP.md) for any repo, wired into copilot-instructions.md. Use for: Bootstrap (start of session or first-time setup), End Session (cheap end-of-session snapshot), Initialize (one-time setup creating local bootstrap/end-session prompt files). Scoped to the current project only; never creates a repo.'
---
# Project Memory Management

This skill has three workflows: **Bootstrap** (start of session / first-time setup),
**End Session** (end of session, cheap snapshot), and **Initialize** (one-time project setup
that wires this skill into a project's own prompt files). Use Bootstrap when the four memory
files don't exist yet, or when the user asks to (re)initialize project memory. Use End Session
at the close of a working session to record what happened. Use Initialize when the user asks
to set up this skill / project memory prompts in a new project.

## Scope restriction (applies to all workflows)

- Never create a new repository, anywhere, under any circumstance.
- Never read from, write to, or delete any file or folder outside of: (a) the current
  project's own folder, or (b) this skill's own folder under the personal skills directory
  (`~/.copilot/skills/project-memory-management/`).
- If a step would require touching a path outside this scope, stop and ask the user first
  instead of proceeding.

## Path resolution (applies to all workflows)

- All paths referenced in this skill (`docs/`, `.github/copilot-instructions.md`,
  `.github/prompts/`) are relative to the **repository root** — the folder containing the
  `.git` directory, or, if `.git` isn't visible/accessible, the folder containing the top-level
  `.sln`/`.slnx` file.
- Do NOT resolve these paths relative to the currently active/focused project's own subfolder.
  This matters especially for solutions with a nested layout (e.g. `RepoRoot/RepoRoot/*.csproj`),
  where the repo root and an individual project folder can easily be confused.
- Before writing any file, state the resolved absolute path you are about to write to, so the
  user can confirm it is correct before the write happens.

## Workflow 1: Bootstrap (Project Memory Bootstrap)

Bootstrap persistent project memory for this codebase so future chat sessions can be
resumed cheaply (low token usage) instead of re-exploring the codebase or re-summarizing
conversation history every time.

This workflow is project-agnostic and idempotent: if the target files already exist, review
and update them incrementally instead of overwriting/duplicating content.

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

6. Update (or create) the repo-scoped `.github/copilot-instructions.md` to add or refresh a
   "Persistent Project Memory" section stating:
   - If it exists, read `docs/CODE_SUMMARY.md` and `docs/DESIGN_DECISIONS.md` before exploring
	 the codebase with search tools for a new task. If these files do not exist, fall back to
	 normal exploration — their absence is not an error.
   - If it exists, read `docs/PROJECT_STATE.md` and `docs/ROADMAP.md` when the user asks
	 "do you remember", references prior work, or asks what's next.
   - Update `docs/CODE_SUMMARY.md` when: a new project is added, a new structural class/service
	 is added, a component's responsibility changes, or a project/component dependency changes.
	 Do not update for routine bug fixes or small edits that don't affect structure.
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
   step is merge-safe: if the section already exists, only add the following 2 bullets if
   they are missing — do not touch or remove any other content already in that section
   (e.g. project-specific instructions that may already be there). If the section does not
   exist, create it with exactly these 2 bullets:
   - Manual commit review before any commit.
   - Build/test verification after every change.

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

9. If any of the target files already exist from a prior bootstrap, do not overwrite blindly:
	read them first, then merge/update only what's missing or outdated.

10. Report back a short summary of what was created/updated and confirm the build still
	succeeds.

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

4. Do not modify `docs/ROADMAP.md` unless the user explicitly discussed a priority/plan change in
   this session.

5. Report back a short (2-5 line) summary of what was updated (or confirm nothing needed
   updating).

## Workflow 3: Initialize

One-time setup that wires this skill into a project via its own prompt files, so the user can
invoke Bootstrap/End Session through short project-local prompts.

### Steps

1. Determine the target content for `.github/prompts/bootstrap.prompt.md`: an instruction to
   invoke the project-memory-management skill and run its Bootstrap workflow exactly as
   defined.

2. Determine the target content for `.github/prompts/end-session.prompt.md`: an instruction to
   invoke the project-memory-management skill and run its End Session workflow exactly as
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
