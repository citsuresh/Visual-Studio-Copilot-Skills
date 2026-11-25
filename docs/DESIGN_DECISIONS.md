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

## 2026-11-13 — Read-aloud became its own small skill; ducking is opt-in and compiled in memory

**Decision:** The "enable tts" / "start tts" rules moved out of the graph skill into a new `read-aloud`
skill (about 2.5 KB) that owns `scripts\Speak-Text.ps1` and `scripts\AudioDucker.cs`. Its description names
the trigger phrases, so it works in any project without Bootstrap. Graph v27 turns Step 7c into one pointer
bullet (no path) and leaves `project-memory-management-graph\scripts\Speak-Text.ps1` as a forwarder, so the
absolute path written by v25 and v26 keeps working. Ducking lowers other applications' audio sessions on the
default output device to `duckPercent` (default 25) of their volume while speaking, only when
`%USERPROFILE%\.copilot\tts-settings.json` has `"duck":true`. The helper is C# compiled in memory by
`Add-Type` (no build, no toolkit), only when ducking is on or a leftover state file has to be undone. The
original volumes are written to `tts-duck-state.txt` before lowering, restored in `finally`, and restored by
the next run if a run was killed. A session whose volume no longer equals the value that was set is left
alone. Any ducking failure means speech at normal volume.

**Rationale:** The v25 bullet only existed in bootstrapped projects, so "enable tts" silently failed
elsewhere. Putting the rules in the 113 KB graph skill would have loaded all of it for ten lines of rules and
tied TTS to the graph skill's version and install. Ducking needs the Core Audio session API, which is awkward
from pure PowerShell and simple from C#. Compiled in memory keeps it a script, not a toolkit. The C# is kept to
C# 5 syntax because Windows PowerShell 5.1 compiles with the old compiler.

**Alternatives considered:** TTS rules inside the graph skill (cost and coupling above). A toolkit with a built
executable (a build step and a repo for about 200 lines). Always-on ducking (changes behaviour for everyone).
Lowering the master volume (affects everything, including the speech). A named mutex for two overlapping
speaks: not added; the changed-volume check keeps the worst case harmless.

**Found while testing:** session instance identifiers contain `|`, so the first state-file delimiter broke;
the file now uses tabs.

**Not tested:** `NoVoice` with ducking on (the duck call comes after the voice check, by reading); PowerShell 7;
exclusive-mode audio apps; a real chat triggering the skill from "enable tts".

## 2026-11-18 - Independent generic-only pushes and ready user handoffs

**Decision:** Push notifications are a separate current-chat opt-in skill, independent of both
speech modes. Completed/Question/Blocker titles stay fixed for MacroDroid; bodies contain only
fixed generic text and an explicitly approved non-sensitive repository label. Required work and
question preparation finish before the qualifying push, active TTS and immediate user handoff.
The graph skill's generated pointer delegates timing to read-aloud rather than duplicating it.

**Rationale:** An alert during preparation can summon the user to a nonexistent question.
Pushbullet self-pushes were observed sharing the Android category `Me`, so stable titles support
the user's phone-side rules without claiming separate Android categories. No task details are
sent to the external service.

**Implementation:** Reuse the canonical sender/setup scripts in `scripts/agent/` through the
installer's `skills-source.json`, not duplicate implementations in skill folders. Credential XML
stays outside Git/the installed skill tree, Windows-user encrypted. A setup-helper copy sits
beside it. Missing XML leaves pushes disabled with brief masked-prompt instructions and an
explicit request to issue start/enable again; setup never silently enables notifications.

**Alternatives rejected:** Coupling push enablement to TTS, arbitrary message summaries,
committing even encrypted credentials, and sharing one encrypted XML across machines. Incoming
phone replies require a separate receiver and are not implemented by this one-way sender.

## 2026-11-18 - Bundle notification runtime with the installed skill

**Decision:** Reverse the source-checkout dependency in the preceding entry. The canonical
sender and standalone setup helper now live in `push-notifications/scripts/`, copied by the
existing installer without installer changes. Old `scripts/agent/` entry points forward with
the same named parameters. The credential location and nearby standalone setup copy stay unchanged.

**Rationale:** An installed skill must contain its runtime helpers and work without the source
checkout. Forwarders preserve manual calls without maintaining duplicate implementations.
Offline privacy/setup tests target the bundled setup implementation and exercise the sender
through the compatibility entry point. Installation still requires hash verification and a
separate live dry run; passing mocked transport tests does not establish phone delivery.

## 2026-11-19 - Keep notification credentials beside installed scripts

**Decision:** Reverse v2's preserved credential default: bundled runtime scripts now default to
their own folder, and repo compatibility forwarders explicitly pass that installed location.
The installer excludes the exact case-insensitive filename `pushbullet-token.xml` from both
source copying and orphan/prune handling. It copies only enumerated non-credential files rather
than using a recursive wildcard. Custom credential filenames belong outside the installed tree.

**Rationale:** The user expects credentials near the setup scripts. Without both installer
exclusions, an update could distribute a source credential or prune a locally created one.
Filtering the source list alone would not protect a subsequent wildcard copy. Existing XML is
never silently reused, moved or overwritten; any same-account migration requires separate consent.
The user explicitly requested leaving the new location empty for the enable-command test.

**Verified:** Offline privacy/setup tests and a disposable fake-profile installer test pass.
The latter checks nested script updates, case-insensitive credential exclusion, local credential
hash preservation, ordinary orphan pruning and a final up-to-date check. No real XML is involved.
Separately approved installation has exact source/installed hashes and `RESULT: UpToDate`.
The user's missing-XML start command kept pushes disabled and returned setup guidance, without
legacy fallback. After a separately authorized same-account credential copy and fresh enable
command, the user confirmed receipt of the requested [TEST] notification. That confirms phone
delivery, not normal-title MacroDroid routing for v3.

## 2026-11-19 - Gate skill workflows on the exact executable, not checkout versions

**Decision:** UI v22, debugger v11 and orchestrator v22 check the selected executable's `info`
identity/capability IDs before using new features. Explicit portable packages also report their
manifest verification status; a missing manifest is not a match. Keep CLI identity separate
from the running MCP server's advertised schema. This does not auto-update, restart, or grant
mutation permissions, and unknown/legacy builds use only already-verified legacy behavior.

**Rationale:** An installed source clone can be current while a selected portable binary or
running server is older. A checkout version or installer marker alone cannot establish verb
support. Per-feature checks avoid imposing a single minimum version on unrelated workflows.
Provider support, cooperative budgets and non-atomic observations remain explicit limitations.
Verified UIA selection does not prove a chat app submitted that answer: preserve the existing
click/submit/fresh-echo contract. Bundled watcher/transcript scripts are not retrofitted by docs.

**Verified:** Both installed CLI identities advertise the documented capability IDs at source
commit `68bbd1c`; static VS help confirms aliases, targeting/context options and wait metadata.
The three applied skills hash-match their approved temporary drafts. These doc checks do not
establish real WinForms/x86/hardware coverage; no application or debugger action was performed.
After separate installation approval, all three installed skill hashes match source and the
post-install check reports `RESULT: UpToDate`; toolkit executables were not rebuilt.

## 2026-11-19 - Observability without claiming recovery or overall completion

**Decision:** Reuse AgentDebugToolkit's existing successful-build marker for exact managed tool
paths; do not introduce a competing install manifest or infer identity from checkout status.
Keep RDP session observations distinct from external client state and from a verified fix.
Preserve legacy Git-unavailable builds and their empty marker commit, while requiring the four
reported binary commits to agree. Consistency does not establish a match to unknown checkout
identity; do not turn an unavailable source fact into verified provenance.
V2 progress is opt-in and reuses ordinary probes; it reports operational facts and cleanup
ownership, never device progress or overall task completion. Preserve silent defaults and the
single-watcher/stable-result contract rather than repeated short polls or early-Idle cancellation.

**Speech:** Keep the legacy NoVoice/exit-code contract but report sanitized reason/stage/host
facts, not spoken text or raw exception messages. Non-speaking availability is not an audible
test. Voice choice, default output/settings, and push mode remain unchanged. Preserve both the
failure marker and diagnostics through auto-TTS. User-confirmed audible recovery remains separate.

**Handoffs:** Classify the overall request at every error/final exit: running work is not
Completed; a user-action blocker gets Blocker, an approval gets Question. Fixed generic payloads,
approved labels, deduplication and server-acceptance versus phone-delivery distinctions remain.

**Verification limits:** Mock speech/progress tests, parsing, an invalid-window progress check
and unchanged sender privacy tests pass against external drafts. No restored/minimized/disconnected
RDP reproduction, remote audible recovery, hardware test or agent-compliance improvement is claimed.

## 2026-11-19 - Separate native UI self-renaming from stored-session CLI renaming

**Decision:** In vs-chat-history v12, allow explicitly requested current-chat renaming through
Visual Studio's own session-list UI, composed with ui-interaction. Require an unambiguous VS
instance/session, an approved title, typed-text read-back, saved-title verification and reopening
the same conversation. Preserve drafts and stop on ambiguous identity or interrupted navigation.

**Rationale:** The old absolute self-rename prohibition was more restrictive than the recorded
CLI evidence: the 2026-10-30 active-chat rename/undo/restart test succeeded. That does not verify
the proposed UI route, which avoids direct external metadata writes and lets VS own the change.
Do not silently force a CLI rename if UI verification fails. Keep CLI activity/force safeguards,
restart caveats and undo logs route-specific; UI renames do not produce toolkit undo entries.

**Validation:** The approved draft's metadata, version and whitespace checks passed. Live UI
self-renaming remains unverified until the controlled session-list rename/reopen test completes.

## 2026-11-19 - Defer self-renaming until idle and bundle its runtime

**Decision:** vs-chat-history v13 supersedes v12's direct running-chat procedure. Require an
explicitly approved independent worker and exact final-message/stable-idle gate for this
responding chat; another verified idle chat retains the direct native UI route. Commit once,
verify clipboard/foreground/title/context/cursor state and stop on uncertainty, without a
forced CLI fallback or automatic VS restart. Generation state is not the selected-row label.

**Packaging:** Keep one canonical runtime under `vs-chat-history/scripts/`, copied by the
existing recursive installer. Preserve the root script as a parameter-compatible forwarder;
tests stay repository-only. Do not distribute private live-test controllers, packets or logs.

**Evidence:** Direct self-renaming left the editor open twice; a tracked worker prevented idle.
The independent optimized temporary rename/restore passed all checks. The other-chat recovery
restored its title/context but did not fully verify the caller context; the user accepted that
limitation. This supports a workaround, not a proven VS root cause or universal speed guarantee.

## 2026-11-20 - Separate Chat Voice policy from unavailable production transport

**Decision:** Keep the `vs-copilot-chat-voice` companion source in this skills repository,
separate from the application. Start with explicit prototype one-shot consent and policy;
gate automatic final/progress delivery on a verified bridge and authoritative Speaker state.

**Rationale:** The current reader auto-plays one prepared reply per launch; the initialized
VSIX shell supplies neither a persistent feed nor remembered automatic state. Installation
is not activation, and a prerequisite check is not working voice integration.

**Alternatives:** Do not build an application bridge here, emulate a feed by repeated launches,
reuse generic TTS, invent a toolkit path or persist a second Speaker preference. Reuse existing
installer autodiscovery and index generation; defer helpers until their contracts are verified.

## 2026-11-21 - Sender native argument transport and independent input verification

**Decision:** The sender uses ProcessStartInfo with Windows argument escaping and separately
reads the input through ValuePattern or TextPattern before Send. Unsupported/ambiguous reads fail.

**Rationale:** Windows PowerShell 5.1 native invocation stripped embedded quotes or split quoted
spaces. CLI verification can only compare against the already-corrupted native argument; it does
not establish that the input equals the original PowerShell string.

**Alternatives considered:** Escaping only double quotes in a native splat was rejected because
backslashes adjacent to quotes and trailing backslashes also require Windows argument escaping.
Offline native round trips and mocked read-back were tested; no live chat send was performed.

## 2026-11-21 - Sender refuses its own host Visual Studio by default

**Decision:** The sender compares the target window's process id (from the window list) with the
script's own process id and its parent chain, and refuses a match unless `-AllowOwnHost` is passed.
An unreadable window list or process chain refuses too.

**Rationale:** An agent that targets its own chat would clear or send into the conversation it runs
in. The process chain identifies exactly that host without restricting targets to Exp: other main
or Insiders devenv processes remain valid.

**Alternatives considered:** Allowing only Experimental instances was rejected because main and
Insiders targets are legitimate. A parent chain broken by a detached launch cannot be detected, which
is documented. Mocked checks and a read-only real-window check were run; no live send was performed.

## 2026-11-21 - Reply classification uses structural markers before name patterns

**Decision:** The transcript script tags each message item with a `Kind` derived from AutomationIds
below it (PART_FlowScrollViewer body, toolCallExpander/HeaderSite tool, PART_LikeButton footer).
The reader keeps bodies, drops tool items and headers, and applies the old footer/chrome regexes to
unmarked items. Only when markers are present in the reply region is a short single-line item with at
most two children treated as a file chip. A body viewer inside a tool expander does not make a body.

**Rationale:** Names such as `Worked on 7 tasks` and file chips vary by build and escaped the
name-based pattern. A legitimate one-word reply has one child, so child-count rules alone would drop
it; the body marker must win. Turns can hold several bodies and tool items before the footer.

**Alternatives considered:** Replacing the regex outright was rejected because builds without the
markers would regress. `IsFooter` was left unchanged to keep the transcript's default output stable.
Fake-UI tests and a read-only real-tree check were run; the scrolling reader was not run live.

## 2026-11-21 - V2 treats a plain Allow as a permission only beside a visible Deny

**Decision:** `Watch-CopilotChatV2.ps1` already reported `Allow this time`. It now also reports a
button named exactly `Allow` as a pending permission, but only when that button and a `Deny` button
under the same parent are both enabled and on screen. Any read failure counts as not a prompt. No
Cancel button is ever a permission: `CancelButton` still means busy only, and a pending approval that
keeps the stop button visible is reported Pending because Pending is decided before Busy.

**Rationale:** Some builds label the approval button `Allow`, so the watcher waited out its timeout. A
bare name match would also catch historical approvals and unrelated dialogs, so the Deny sibling and
the on-screen check keep the match tied to a live prompt. This mirrors the sibling rule in V1.

**Alternatives considered:** Matching any Allow name was rejected as too loose. Treating Cancel as a
permission signal was rejected because it is also the normal streaming state. Offline mock tests were
run; no live approval prompt was available, so the exact structure is assumed from V1's rules.

## 2026-11-25 - Do not ship the cached UI sender or the folder mailbox; measure and trim the shipped sender

**Decision:** Do not add the agent-comm feedback bundle's cached UI sender (`Send-ChatMessageFast.ps1`)
or its folder-mailbox scripts to any skill. Keep `Send-CopilotPrompt.ps1` as the sender. It gains an
opt-in `-Trace` switch that returns per-stage milliseconds with no chat or draft text. Speed-ups for it
are candidates to be checked live one at a time, not decisions. The bundle files stay outside the repo
(they hold machine-specific handles and paths).

**Evidence (one machine, one remote session, Windows PowerShell 5.1, five timed runs each, Send-CopilotPrompt
vs cached sender, median sender time):** 12.5 s vs 4.0 s. The cached sender passed its validation with a
draft present and deleted it (`^a{DEL}`), delivered `Path C:\temp\"x" end` as `Path C:\temp\x"` while
reporting submitted, and has no banner check, own-host refusal or read-back (stray characters were seen
in earlier messages sent with it). `Send-CopilotPrompt.ps1` refused the draft and delivered the text
exactly. A six-run trace of the shipped sender (median ms): banner 2820, paste 1435, foreground 1277,
clear 1083, second draft check 1011, first draft check 953, own-host 773, input check 749, send 732, tab
check 677, read-back 478; total 12216. Much of the gap sits in repeated lookups, not in the safeguards.
The mailbox's wake of an idle chat was not demonstrated; its router counts a listener by process, so an
untracked listener looks alive (v31 records 5.4 hours lost to an untracked watcher); inbox files have no
authentication; `processed` and `archive` keep chat text on disk.

**Alternatives considered:** Shipping the cached sender with a draft refusal, exact read-back and
banner check added was deferred until the shipped sender's speed-ups are measured. A separate mailbox
skill was deferred until wake-up, listener liveness and retention limits are resolved. Both stay out
for now. Limits: small samples, remote session, off-screen behaviour of the cached sender not measured,
speed-up gains not yet measured.

## 2026-11-25 - Sender speed-ups adopted after a local measurement: one process snapshot, targeted banner lookup, single draft search

**Decision:** Keep three changes to `Send-CopilotPrompt.ps1` (agent-orchestrator v32), each leaving a
safeguard in place: the own-host check reads one process snapshot instead of one lookup per ancestor;
the banner check searches for the two banner IDs instead of dumping the tree with `inspect`, and a failed
banner read now refuses (`BannerCheckFailed`) instead of reading as no banner; the draft check reuses the
input element it has just found. Not adopted yet, pending their own runs: dropping the first draft check,
skipping the first clear when the input was just verified empty, and reusing the tab check's result.
Follows the 2026-11-25 entry above, whose speed-up gains were then unmeasured.

**Evidence (this machine, local session, Windows PowerShell 5.1, one idle chat in a Visual Studio
Insiders window, build `66ecbfc`, `-Trace` timings in ms):**
- Baseline, six traced sends of the earlier script: median 13.8 s in-script (agent's machine: 12.2 s).
- Interleaved before/after, 4 runs each in the order before, after, after, before, before, after,
  after, before; all 8 sent on the first attempt. Median total 21.3 s before (16.0 to 26.7) and 12.6 s
  after (10.1 to 22.1). Stage medians before and after: banner 4970 to 610, ownHost 3583 to 1238,
  draft2 1618 to 546, draft1 1314 to 1057. Stages left unchanged (foreground, paste, send) were alike in
  both variants.
- Read-only timings of the functions in isolation: own-host chain 2.1 to 2.3 s with a lookup per ancestor
  against 0.34 to 0.43 s with one snapshot, identical chain; banner `inspect --maxDepth 25` 2.5 to 2.9 s
  (85,558 characters) against 0.37 to 0.46 s for one targeted lookup.
- The full-tree dump grows with the chat: the banner stage rose from about 2.0 s to about 5.0 s as the test
  chat reached about 25 messages, while the targeted lookup stayed at 0.3 to 0.6 s.
- 277 offline assertions pass, including a check that the snapshot chain equals the per-lookup chain on
  the real process tree.

**Alternatives considered:** Keeping the full-tree banner dump was rejected because its cost scales with
chat length and its failure looked like "no banner". A cached click point was deferred: the remaining gap
to the unsafe cached sender is mostly repeated lookups by name, to be measured after the pending changes.

**Limits:** Four runs per variant, one machine, free memory about 1.6 GB of 15.8 GB, so absolute times are
noisy. Banner detection was later confirmed live with a real working-directory mismatch banner: the new
lookup and the old `inspect` method found the same banner (1.7 s against 7.0 s on that tree, under load)
and the real script refused with `Sent=false`, nothing typed and the input still empty. The trust banner
could not be raised and is untested live. The own-host refusal has not been rerun from inside a Visual
Studio chat. One earlier send failed at the final click with
`foreground-activation-failed` (the draft was kept and no message was sent); it did not recur in the later
8 sends and its cause is unknown. The numbers have not been reproduced on the agent's machine.

## 2026-11-25 - Refuse at once when the chat input is off-screen; do not move the window

**Decision:** `Send-CopilotPrompt.ps1` (agent-orchestrator v33) compares the chat input's centre with each
monitor's working area before any draft check, clear, paste or click, and returns `Sent: false` with an
`InputOffScreen` error that says what to do. It does not move the window. If the screen geometry cannot be
read the check returns nothing and the send proceeds as before, because it is a convenience check and not a
safety guard.

**Rationale:** A window pushed partly below the screen still reports `IsOffscreen: false`, and the input
verbs then fail only with `foreground-activation-failed` after three attempts (15 to 17 s on the agent's
machine), with no hint of the cause. The selector click has no screen-bounds check, so a failed attempt can
move or click the pointer near the screen edge. The check shares the single input search with the second
draft check, so it adds no lookup.

**Evidence:** Live on this machine, with the window moved so the input sat at y=1479 on a 1008-pixel working
area and UIA still reporting `IsOffscreen: false`: the check returned `InputOffScreen` in 29 ms in isolation,
and the real script refused in 5.8 s with `Attempts: 0`, nothing typed or clicked and the input empty; the
pointer moved from (1118,625) to (1104,612). The window was restored exactly. Offline tests (296 assertions)
cover single and dual monitors, the taskbar band, a partly visible input, an empty rectangle, the fail-open
paths and the ordering before the send loop.

**Alternatives considered:** Moving the window back automatically (as the agent's cached sender did with
`SetWindowPos`) was not adopted: it moves the user's own window and was tested by the agent only on the docked
main window. It remains a possible opt-in switch. Relying on `IsOffscreen` was rejected because it reports
false for this case. **Limits:** one machine, one monitor, one window; the dual-monitor and empty-rectangle
cases are offline tests only; a floating (undocked) chat window is not handled by this script at all.

## 2026-11-25 - UI scripts wait for a quiet keyboard and hand the person's window back

**Decision:** `Send-CopilotPrompt.ps1` and `Select-ChoicePromptOption.ps1` (agent-orchestrator v34, shared helpers in
ui-interaction v25) take the foreground only after a quiet moment and only for the input steps. They queue
behind other agents with one session-wide lock, wait until there has been no typing, click or scrolling for 3 s
(moving the pointer alone is ignored, because people move the mouse for many reasons and a jittery pointer would
otherwise keep every wait going; 6 s
while the foreground editor holds text), and wait while a mouse button or modifier key is held or Windows
reports a presentation, a full-screen app, quiet time, a locked session or a menu or drag in progress, or a manual
pause is set. The wait is capped at 120 s (`UserActive`, `DoNotDisturb`, `SessionNotPresent`) and the scripts then
type nothing. A cursor dot (amber for waiting, red for acting) and one short sound mark the wait; after 30 s the
person is asked once to pause, spoken only when the caller says speech is on. Before every foreground, clear,
paste and send step the scripts check that the person has not used the keyboard or mouse since the previous
agent step, and stop with the pasted text left as a draft if they have. Afterwards the person's window, focused
control and pointer are restored when it is still theirs to give back, and the result reports whether that was
verified. The read-only checks now run first with the person's window still in front, and card answers no longer
call UIA `SetFocus` before the foreground is taken.

**Rationale:** The user reported many times that their keystrokes landed in the other agent's chat input, even
before the paste, because the sender took the foreground at the start and held it for about 8 s. The shared
Alt tap that wins the foreground can also open a menu in the person's application. Idle time alone cannot see a
held mouse button (no new event while held), so held buttons and modifiers are checked separately. Several
orchestrators run at once on this machine, so input blocks must queue and must not treat each other's input as the
person's. No keyboard hook is used (security tools treat it as a keylogger) and `BlockInput` is not used (it needs
elevation and can lock the person out if the script dies).

**Alternatives considered:** A corner overlay as a second cue was dropped in favour of a short sound. Filtering
by application was rejected; the draft check is generic. Detecting a shared (not full-screen) window is not
possible through Windows' supported state; a manual pause covers it, and the Windows screen-capture record is a todo to
test with a real Teams share. **Evidence (live, 2026-11-25, one machine, sender only):** a manual pause refused
with nothing typed; simulated typing for 8 s into a scratch window made the send wait and then send, with all 43
characters landing in the scratch window and the window handed back; a held mouse button kept the foreground away
until release; a lock held by another process made the send queue behind it; a normal send handed back the same
window and focused control; a key pressed in the gap before the first input step stopped the send with `UserInput`,
nothing sent. A first held-button run stopped falsely because the person's pointer jitter counted as input, which is
why pointer movement alone is now ignored. A real card (Red, Green, Blue, Other) was answered live with
`Select-ChoicePromptOption.ps1`: it closed, echoed `User entered: Green`, and the person's window and focused
control came back. **Limits:** a real presentation, several orchestrators sending at once and the person's window
after a `UserInput` stop are not tested live; a key that arrives during one
of the script's own steps is absorbed into that step (the exact read-back covers the pasted text); the amber dot is
invisible when Windows hides the pointer while typing, which is why a sound is played too.

## 2026-11-25 - Three more sender speed-ups, each with its guard kept, and an honest other-desktop message

**Decision:** `Send-CopilotPrompt.ps1` (agent-orchestrator v35) checks that the chat input is showing in its own
process (one UIA search) and falls back to the external wait only when that fails; it skips the early draft check for
a plain send (kept for a new session and for a steer); and it does not clear on the first attempt when the input was
just verified empty (a retry clears first, `-OverwriteInput` clears first). A target window on another virtual
desktop is refused with its own message, because it is absent from the default window list and used to be reported
as gone.

**Rationale:** The draft check after the quiet wait is the authoritative one, and the exact read-back before sending
catches stray text, so the early check and the first clear only cost time. The in-process lookup avoids launching
`agentdebug-ui.exe` for a yes/no question. Sending to another desktop would switch the person's whole desktop; the old
"no longer exists" wording sent people looking for a restarted Visual Studio.

**Evidence (one machine, local session, 4 interleaved pairs against the committed v34, 8 sends all on the first
attempt):** median total 13.9 s to 11.2 s; without the quiet wait, which varies with the person's typing, 9.9 s to
7.2 s (about 27%). Stage medians before and after: first draft check 589 to 0 ms, input wait 619 to 0 ms, first clear
1179 to 4 ms, chat-visible check inside the `foreground` stage 1704 to 1517 ms. 362 offline assertions pass.

**Alternatives considered / still open:** the `foreground` stage is still about 1.5 s, mostly loading the shared
helper script, which compiles three small C# types on every run (a prebuilt assembly would avoid it); the paste is
1.8 s (`type --paste --verify` adds a stability wait the independent read-back makes redundant); the own-host check
still launches a window listing (0.9 s); each foreground change waits 300 ms even when it succeeds; the final click
launches `agentdebug-ui.exe` where an in-process Invoke would do. Each is a separate change to measure. **Limits:** one
machine, 4 pairs, the quiet-wait stage is noisy.
