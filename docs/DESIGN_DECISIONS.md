# Design Decisions

Append-only, dated log of non-obvious architectural/design choices. Never delete or rewrite
prior entries — if a decision is reversed, add a new entry referencing the old one instead of
removing it.

## 2026-08-07 — Skills distributed via a per-user copy, not a symlink or package

**Decision:** `Install-Skills.ps1` copies each skill folder's files into
`%USERPROFILE%\.copilot\skills\<skill-name>\`, rather than symlinking or installing via a package
manager.

**Rationale:** Keeps installation simple (plain file copy, no elevated permissions or package
registry needed) and makes it obvious when a locally-installed skill is stale relative to the
repo (the script hashes each file and only copies changed ones, prompting per-skill unless
`-Force` is passed).

**Alternatives considered:** Symlinking the skills folder directly into `.copilot\skills\` was
considered but rejected — Windows symlinks require elevated permissions/developer mode in some
environments, which would complicate first-time setup.

## 2026-08-07 — Each skill is versioned independently via `CURRENT_SKILL_VERSION`

**Decision:** Each skill's `SKILL.md` embeds its own `CURRENT_SKILL_VERSION` constant and a
changelog, and stores the last-synced version as an HTML comment marker in a target project's
`.github/copilot-instructions.md`. A cheap "Workflow 0: Version Check" compares the two on every
invocation.

**Rationale:** Lets a project that was set up under an older version of a skill detect that the
skill's workflows have since changed in a way that would benefit from (or require) re-running
Bootstrap — without the user needing to remember or manually track this per project.

**Alternatives considered:** None recorded (this is the mechanism as originally designed).

## 2026-10-16 — Reusable per-project scripts added to project-memory-management-graph (v15–v22)

**Decision:** The `project-memory-management-graph` skill gained a reusable-scripts feature across
v15–v22 (main branch; commits `0fc850e`, `9384fac`, `e0a31a4`, `90485eb`, `48395a6`, `d838aaa`,
`9b178b8`; none pushed at the time of writing). Scripts live in `scripts/agent/` in each project
and are indexed in `docs/SCRIPTS.md`. Copilot saves a missed script at End Session (Step 5a) and
extends an existing script with a backward-compatible parameter instead of copying it. The index
date is the last run or change date. End Session Step 5b lists scripts not run for more than 60
days and asks the user to keep, archive or delete each; Copilot never deletes a script or index
row on its own.

**Version history:** v16 every varying part of a saved script must be a parameter; v17 a one-line
reason when a qualifying script is not saved; v18 End Session asks before saving when the task
forbids file changes; v19 the file-rule check runs before any save or index change; v20 Bootstrap
checks the Reusable scripts bullet after writing it (instruction only; did not work); v21 that
check is a string comparison Bootstrap runs and quotes; v22 the date rule, Step 5b, and the
file-rule check in both. `9b178b8` aligned the changelog wording with what was actually tested.
Note: the shelved `poc/subagent-planner` branch also uses v15/v16 for different changes, so those
version numbers differ between that branch and main.

**Tested (Keka repo, Copilot):** non-qualifying snippet not saved; qualifying one saved (csproj
script); new switch added to an existing script rather than copied; Bootstrap bullet drifted at
v20 and matched exactly at v21 (checked on disk); a forbidding task left the date unchanged and a
permitted task updated it to today; the unused-script review flagged the test script, archived it
on request to `scripts/agent/archive/` and updated its row; a modifying script asked for
confirmation before running.

**Not tested:** v18 ask-before-save branch for a task that forbids file changes; v19 file-rule
check before an index-line change; v22 whether an archived script is skipped on a later End
Session. The v21 requirement of five-column index rows (after an End Session reported the index
consistent despite a stray row) was not retested.

**Known problems:** the editing tool repeatedly cut index rows short, so index files should be
edited only through scripts that assert exact text. Bootstrap wording drift occurred three times
(v16, v19, v20) before v21's comparison. The version check detects only projects behind the skill,
not ahead of it.

**Project state at the time:** Keka is at v22 with test files removed; its six modified files
(copilot-instructions, PROJECT_STATE and four graph JSONs) are uncommitted and were modified before
testing, and its `docs/PROJECT_STATE.md` still holds test-session notes. Its
`.github/copilot-instructions.md` is LF, not CRLF. The obj/bin default for
`report-csharp-metrics.ps1` was decided yes, but that script was deleted in cleanup, so no artefact
carries the decision.

**Out of scope:** the sub-agent planner is shelved on `poc/subagent-planner`.
`agent-orchestrator/`, `ui-interaction/` and `ui-navigation-orchestrator/` have uncommitted changes
that are not part of this work and were left alone.
