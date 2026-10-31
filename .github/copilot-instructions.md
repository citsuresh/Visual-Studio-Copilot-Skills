<!-- project-memory-management-graph: skill-version=23 -->
## Persistent Project Memory

This section is fully regenerated (overwritten) on every Bootstrap run. It is NOT merge-safe,
unlike "Project Guidelines" and "Response Guidelines" below.

This repository is in docs-only mode: no `.sln` or `.slnx` files are present. No code graph or
`docs/KEY_FLOWS.md` is generated here. If a real C# solution is added, rerun Bootstrap to register
and build its graph.

### Solution graph registry

No tracked C# solutions; the registry is intentionally empty in docs-only mode. Each tracked
solution would have `docs/full-graph.<slug>.json` and `docs/project-dependencies.<slug>.json`.

| Solution path relative to repo root | Slug | Graph file | Dependencies file |
| --- | --- | --- | --- |

- If it exists, read `docs/CODE_SUMMARY.md` and `docs/DESIGN_DECISIONS.md` before exploring the
  codebase with search tools for a new task. If these files do not exist, fall back to normal
  exploration — their absence is not an error.
- If it exists, read `docs/PROJECT_STATE.md` and `docs/ROADMAP.md` when the user asks
  "do you remember", references prior work, or asks what's next.
- If it exists, read `docs/domain-lookup-patterns.md` when a task requires domain conventions,
  naming schemes, or business logic that the graph doesn't represent — check it before falling
  back to manual exploration or a fresh graph query.
- If it exists, read `docs/FEATURE_CHECKLIST.md` when planning or adding a new feature.
- Registered graphs should be queried via the GraphTools wrapper script (located at
  `C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1`, invoked as
  `C:\MyFiles\Git\GraphTools\tools\Invoke-GraphTools.ps1 -Tool Query -- <args>`) (never read
  wholesale). This is a default, not a judgment call: before using a general-purpose search tool
  (text search, symbol search, grep, or similar) to locate a class/interface/enum, find a
  method's definition, find its callers, find its callees, check how two types relate, or
  otherwise answer "where is X" / "what uses X" for anything that is a C# symbol, first check
  the registry for the registered per-solution graphs, and query them via the wrapper
  instead of a general search tool. This applies even to a simple "find this file/class"
  request, not only explicit call-graph or architecture questions. This preference applies
  regardless of how the question is phrased: conceptual/explanatory framings ("explain X",
  "walk me through X", "how does X work", "describe the Y flow") are NOT exempt just because
  they aren't literally worded as a find/locate request. The test is whether answering the
  question requires locating, identifying, or relating specific named C# classes/interfaces/
  methods — not whether the question is phrased as a lookup. If it does, query the graph first.
  (Not applicable while this repo remains docs-only — no graph exists to query.)
- Resolution order: query the graph of the solution currently open in the IDE first, only if
  that solution can be determined from context (do not invent a detection capability; otherwise
  treat it as unknown). If the symbol is not found there, check the other registered graphs.
  Label every result with its solution, and say so if it is found in more than one solution.
- Fallback: if no registered graph exists, a registered graph file is missing, a query errors or
  exits non-zero, or no registered graph answers the question, say so explicitly (report the full
  error for failures; a "symbol not found" result may only mean the graph is stale), then fall
  back to normal search and proceed. This is never a blocking error; fallback is never silent.
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
- `docs/KNOWN_OPEN_FINDINGS.md` is user-controlled. Never add, edit, or remove entries without an
  explicit user request. When adding, check for a similar existing item and ask the user whether it
  is a recurrence or a new issue.
- `docs/FEATURE_CHECKLIST.md` is optional and user-curated; never create or change it unless the
  user explicitly asks. Read it when planning or adding a feature.
- Reusable scripts: before writing code for a repeatable mechanical step (filtering a log, applying the same edit to many files, extracting data from several files), check `docs/SCRIPTS.md` if it exists and run a script that fits, as its index line says; if the index line says it modifies or deletes files, ask the user before each run, and check its output before relying on it. If you wrote working code for such a step that is likely to be reused with different inputs, is more than a one-liner, can take its inputs as parameters, and contains no credentials, tokens, customer data or personal details, save it as `scripts/agent/<verb-noun>.ps1` with a header comment (purpose, parameters, whether it modifies anything), add one line to `docs/SCRIPTS.md` (table: script | purpose | how to call | read-only or modifies | date; create the file with the table header if it is missing), and say so in your reply. Before saving, check whether an existing script in `scripts/agent/` can take the new case as a parameter. If one can, extend that script with a backward-compatible parameter (its default keeps the current behaviour, and existing parameter names, order and output format stay unchanged), update its header comment, index line and date, and say so, rather than saving a near-copy. If the task's file rules forbid changing the existing script, do not save a near-copy; say in your reply which parameter the existing script needs. Every part that varies between uses (paths, patterns, comment markers, row counts, exclusions) must be a parameter. For C# projects, skip `obj` and `bin` folders by default, with a switch to include them. Before finishing a task, check once whether you wrote any script worth saving. If a script fails or is out of date, fix it in place and update its date, or do the step normally; never loop on a broken script. When a task runs a listed script, set its date in `docs/SCRIPTS.md` to today if the task's file rules allow editing that file; otherwise leave the date unchanged and say so in your reply. The user curates these files: never delete scripts or index lines on your own.
- At End Session, check only the context from the session for a qualifying unsaved reusable script and check script/index consistency when either exists. Respect any file restrictions given for tasks in the session; ask before prohibited changes, and never delete or rewrite scripts or existing index entries. If `docs/SCRIPTS.md` exists, ask which scripts older than 60 days to keep, archive, or delete; make only requested changes. Ask separately whether anything should be added to `docs/KNOWN_OPEN_FINDINGS.md`.

## Project Guidelines

- Manual commit review before any commit.
- Build/test verification after every change.
- Do not commit or push automatically — wait for explicit user confirmation first.
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
