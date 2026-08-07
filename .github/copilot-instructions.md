<!-- project-memory-management-graph: skill-version=8 -->
## Persistent Project Memory

This section is fully regenerated (overwritten) on every Bootstrap run. It is NOT merge-safe,
unlike "Project Guidelines" and "Response Guidelines" below.

This repo is in **docs-only mode**: no C# solution (`.sln`/`.slnx`) exists to build a code
knowledge graph from (the only solution file found, `.vs\Visual-Studio-Copilot-Skills.slnx`, is
Visual Studio's auto-generated, gitignored, empty open-folder scaffolding — not a real checked-in
solution). `docs/full-graph.json` and `docs/project-dependencies.json` will never exist here, and
`docs/KEY_FLOWS.md` was intentionally not created. The graph-related guidance below only applies
if this repo ever gains a real C# solution and Bootstrap is re-run.

- If it exists, read `docs/CODE_SUMMARY.md` and `docs/DESIGN_DECISIONS.md` before exploring the
  codebase with search tools for a new task. If these files do not exist, fall back to normal
  exploration — their absence is not an error.
- If it exists, read `docs/PROJECT_STATE.md` and `docs/ROADMAP.md` when the user asks
  "do you remember", references prior work, or asks what's next.
- If it exists, read `docs/domain-lookup-patterns.md` when a task requires domain conventions,
  naming schemes, or business logic that the graph doesn't represent — check it before falling
  back to manual exploration or a fresh graph query.
- If it exists, mention `docs/full-graph.json`/`docs/project-dependencies.json` are available and
  should be queried via the GraphTools wrapper script (located at
  `C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1`, invoked as
  `C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1 -Tool Query -- <args>`) (never read
  wholesale). This is a default, not a judgment call: before using a general-purpose search tool
  (text search, symbol search, grep, or similar) to locate a class/interface/enum, find a
  method's definition, find its callers, find its callees, check how two types relate, or
  otherwise answer "where is X" / "what uses X" for anything that is a C# symbol, first check
  whether `docs/full-graph.json` exists in this project, and if so, query it via the wrapper
  instead of a general search tool. This applies even to a simple "find this file/class"
  request, not only explicit call-graph or architecture questions. This preference applies
  regardless of how the question is phrased: conceptual/explanatory framings ("explain X",
  "walk me through X", "how does X work", "describe the Y flow") are NOT exempt just because
  they aren't literally worded as a find/locate request. The test is whether answering the
  question requires locating, identifying, or relating specific named C# classes/interfaces/
  methods — not whether the question is phrased as a lookup. If it does, query the graph first.
  (Not applicable while this repo remains docs-only — no graph exists to query.)
- Fallback: if `docs/full-graph.json` does not exist, if `GraphTools.Query.exe` errors or exits
  non-zero, or if the graph doesn't contain an answer to the specific question (e.g. the
  question is about non-code content, file layout, or something the graph doesn't track), fall
  back to normal search tools and proceed — do not treat a missing/failed graph query as a
  blocking error.
- If, during graph-first or domain-lookup work, you notice a recurring friction point (e.g. a
  manual step done more than once that a structural tool could answer instead), mention it
  briefly at the end of your response — don't act on it, just note it. Skip this if nothing
  recurring was noticed; don't proactively search for optimization opportunities outside of
  graph/domain-lookup work.
- Update `docs/CODE_SUMMARY.md` when: a new skill/component is added, a component's
  responsibility changes, or structure otherwise changes. Do not update for routine bug fixes or
  small edits that don't affect structure.
- Update `docs/DESIGN_DECISIONS.md` (append-only, dated entries) when: a non-obvious
  architectural/design choice is made, an alternative approach is rejected with a reason, or a
  past decision is reversed. Never delete prior entries.
- Update `docs/PROJECT_STATE.md` at the end of a working session to reflect current focus, open
  tasks, and recently changed files (overwrite, not append).
- Update `docs/ROADMAP.md` only when priorities/plans deliberately change, not automatically each
  session.
- Keep all memory files concise — they exist to reduce token usage on future re-reads, not to
  serve as exhaustive documentation.

## Project Guidelines

- Manual commit review before any commit.
- Build/test verification after every change.
- Do not commit or push automatically — wait for explicit user confirmation first.
- Any commit made in this repo must use the git identity email `citsuresh@rediffmail.com` (set
  via local `git config user.email`, not the global default). Verify `git config user.email`
  resolves to this before committing; if it doesn't, set it locally first rather than committing
  under the wrong identity.
- Skill update workflow: when asked to change a skill's `SKILL.md` (or other skill file) in this
  repo, follow this sequence and do not skip or reorder steps:
  1. Make the change in a temporary copy of the file (not the real `SKILL.md`), and show a
     unified diff against the current `SKILL.md`. If a unified diff can't be rendered in this
     environment, save it to a file instead and give the exact path.
  2. Ask for explicit confirmation before saving/applying the change to the real `SKILL.md`. Do
     not apply anything until confirmed.
  3. After confirmation, apply the change to the real `SKILL.md` (and clean up the temp
     file/diff).
  4. Ask whether to install the skill now. If yes, run `Install-Skills.ps1` to copy the updated
     skill into `%USERPROFILE%\.copilot\skills\`, then verify the installed copy matches the
     repo's version exactly (e.g. compare file hashes) — don't just assume the copy succeeded.
  5. Ask whether to commit and push. Never commit or push without an explicit yes to this
     specific question, even if the user already asked for the change and the install.

## Response Guidelines

Default to concise, minimal replies (no filler, no restating the question, no unnecessary
preamble), EXCEPT in these cases where full detail is required:
- Design rationale discussions.
- Build/error diagnosis.
- Before any destructive action.
- When multiple approaches exist.
- When generating docs/*.md content itself.
