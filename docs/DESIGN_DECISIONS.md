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

## 2026-11-13 — Read-aloud (TTS) rule goes in the regenerated memory section; the skill never sets a voice (v25)

**Decision:** Bootstrap Step 7c writes one generic bullet into the regenerated "Persistent Project
Memory" section, pointing at the installed `Speak-Text.ps1` by absolute per-user path (confirmed
with `Test-Path`, like the GraphTools wrapper path; skipped if not installed). The script lives in
`project-memory-management-graph/scripts/`, so `Install-Skills.ps1` ships it unchanged. It takes
only `-Text`, speaks with the Windows default voice through System.Speech, and prints `NoVoice`
(exit 2) when no voice is installed or the default voice cannot speak.

**Rationale:** That section is overwritten every run, so a bullet put there by hand would be lost;
Step 7c rewrites it every run instead. "Project Guidelines" is merge-safe/add-if-missing and would
not be refreshed with the version. The user decided the skill must not set, select or prefer a
voice, which also keeps voice names out of a committed file.

**Alternatives considered:** a first version picked a voice by name (`-Voice`, else Andrew, else
Guy) — rejected by the user. Falling back to another voice when `-Voice` matched nothing — rejected
before that, as it would silently ignore an explicit request. A bullet in "Project Guidelines" —
rejected as above.

**Not tested:** a machine with no installed voice (the path was simulated with a fake synthesizer);
PowerShell 7; whether a later chat obeys "enable tts" in practice.
## 2026-11-13 — A generated skills index makes the update check cheap; warn-only hooks keep it current

**Decision:** The repo root holds skills-index.json (per skill: ersion and a one-line whatsNew).
scripts/Update-SkillsIndex.ps1 generates it from each SKILL.md: the version from
`CURRENT_SKILL_VERSION` and the first sentence of that version's changelog entry. Each skill's
Step 0 reads its own entry from the clone's copy and from `git show "@{u}:skills-index.json"` (about
2 KB) instead of the whole `SKILL.md` (up to 113 KB), falling back to a filtered read of the version
line. A `pre-commit` hook regenerates and stages the index; a `pre-push` hook warns (never blocks)
when a `SKILL.md` changed in the pushed commits without a version bump, judged over the whole push.
`Install-Skills.ps1 -Check` prints an `INDEX:` line. `install-skills` has no version and is not
indexed. The graph skill's Step 0 text changed without a version bump (wording only, so projects are not
flagged stale); it reaches installed copies via `Install-Skills.ps1`.

**Rationale:** The old check printed the whole file to read one number, and the fetch itself is cheap.
The text comes from the changelog deterministically: no AI (not reproducible), and no commit message
(a pre-commit hook runs before it exists and one commit can touch several skills). No date or SHA in the
index, as they would change on every run and break the "matches" check. The bump warning sits on push,
not commit, so several commits before the final bump stay quiet. It only warns because some edits
(wording) legitimately skip a bump.

**Alternatives considered:** A GitHub Action (check-only or auto-commit): not added yet; it would catch
web-UI edits and skipped hooks, but cannot block a push. Blocking on a missing bump: rejected by the
user (false positives, bypassable). Version-only detection means an upstream change without a bump is
not noticed by the check.

**Not tested:** the new Step 0 in a real chat; hooks on a clone that did not run `git config core.hooksPath .githooks`.

## 2026-11-13 — Toolkits are cloned and built per machine under `.copilot\toolkits`; `skills-source.json` replaces typed paths

**Decision:** The three companion tools (GraphTools, AgentDebugToolkit, VsChatHistoryToolkit) are public
repos. `Install-Skills.ps1` clones each into `%USERPROFILE%\.copilot\toolkits\<Name>`, fast-forwards it with
`-Remote`, and builds it in place with the toolkit's own `scripts\agent\Build-Toolkit.ps1`, which writes the
built commit to `.built-version`. Each toolkit carries an integer `VERSION`. The installer prints a
`TOOLKIT: <Name> <Status>` line per toolkit, and the skills that use one run a read-only
`Install-Skills.ps1 -Check -Remote -MaxAgeHours 6` in Step 0 and ask before running the installer. Every real
installer run also writes `%USERPROFILE%\.copilot\skills-source.json` (`{"schema":1,"skillsRepo":"<path>"}`),
which every skill reads to find the skills clone. The skills' hardcoded `C:\MyFiles\Git\...` paths are gone
(skill versions: vs-debug 9, ui-interaction 20, agent-orchestrator 19, ui-navigation-orchestrator 8,
vs-chat-history 11, project-memory-management 3, graph 26). Toolkit development stays in separate clones
(here `C:\MyFiles\Git`).

**Rationale:** Skills had to work on any machine, not only this one. Building on each machine needs a .NET SDK
and about a minute on first install, but avoids a release/publish step on every toolkit bump and avoids
downloading unsigned executables. A fresh clone beside the skills means the installer can fast-forward and
rebuild without touching anyone's working tree. `skills-source.json` is one per-user file, so no clone path is
typed into any `SKILL.md`. A toolkit counts as outdated when upstream has any newer commit or the built commit
differs from `HEAD`, so a missing `VERSION` bump cannot leave a stale build in place. Failures never overwrite:
uncommitted changes, local commits, and non-clone folders are reported and left alone.

**Alternatives considered:** Publishing built binaries on each toolkit version bump: not chosen (needs a release
pipeline per toolkit, and downloaded unsigned executables). Keeping fixed paths and asking the user to edit each
`SKILL.md`: rejected, not portable and edits are lost on every update. Using the development clone as the
toolkit: rejected, the installer would pull and build inside a working tree. Skills typing the clone path
themselves: replaced by `skills-source.json`. A minimum toolkit version per skill in `skills-index.json`:
skipped for now; any newer upstream commit already counts.

**Consequences:** graph v26 changes the wrapper path that Bootstrap writes into each project's
`copilot-instructions.md`, so bootstrapped projects are flagged stale and should re-run Bootstrap.

**Not tested:** the skills' Step 0 toolkit checks in a real chat; `SOURCE: Differs` and `NotRecorded`; real
Defender or SmartScreen behaviour on the locally built, unsigned executables. A review of the toolkit repos
found no secrets or committed binaries (see `PROJECT_STATE.md`); the three toolkits now carry an MIT LICENSE.
