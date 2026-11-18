# Project State

This file is overwritten (not appended) at the end of each working session.

## Current focus

2026-11-19 skill alignment is applied to source after temporary unified-diff review and explicit
approval: UI v22, debugger v11 and orchestrator v22. All three source hashes exactly match the
approved drafts. Exact-executable capability gates, bounded/paged UIA reads, state/selection/
restore safety, explicit VS targeting, break context and long waits are documented. Card-answer
submit/echo verification remains mandatory. Bundled helpers and toolkit binaries are unchanged.
Installed UI/VS identities are clean-source `68bbd1c`; capability IDs, static debugger help and
draft metadata/Markdown checks passed. After separate approval, all three skills were installed
with `-SkipToolkits`; installed hashes exactly match source and post-check is `RESULT: UpToDate`.
No app/UI/debugger mutation or new live provider test ran. Commit/push of this seven-file
alignment batch is explicitly approved; publication identity belongs in Git history.
Updated skill discovery may require a new chat.
Real WinForms/x86/hardware smoke coverage and the accepted intermittent desktop-test limitation
remain outstanding. A rebuilt MCP executable has not restarted any running server.

Notification v3 is published as `3dc61ec`, installed and hash-verified. Offline privacy/setup,
isolated installer credential copy/prune protection, and interactive missing-XML guidance passed.
After explicit same-account copy approval, XML is beside installed scripts; the original is
retained unchanged and neither is in Git. Fresh enable and user-confirmed [TEST] phone delivery
passed, not a new normal-title MacroDroid-routing confirmation. Pushes and auto TTS are ON for
this chat only. Historical notes below are superseded by this current-focus snapshot.

2026-11-18 closeout (supersedes historical pending statuses below): user explicitly accepted
the intermittent desktop-test limitation and authorized toolkit commit/push/install. Published
Batch B `ac3fd7b` and C `68bbd1c`; exact remote HEAD and installed clone/executable build identity
are independently verified as `68bbd1c27852c6ea403cc500ded77a932cfa0b6d`, clean-source build.
Installer rebuilt all four tools with 0 warnings/errors; final `RESULT: UpToDate`. Protected
pre-existing toolkit files remain uncommitted and unchanged. No portable release or MCP restart
was performed. New capabilities are present in installed UI/debugger `info` output.

Notification v2 packaging draft was shown and explicitly approved, then applied to source:
canonical unchanged sender/setup now ship under `push-notifications/scripts/`; old paths forward.
Approved skill/runtime hashes match; forwarders differ from drafts only by the existing EOF
newline. Offline compatibility-sender/privacy and bundled setup fixtures passed; setup forwarder
WhatIf passed. After separate explicit approval, v2 was installed and all three installed-file
hashes verified; post-check `RESULT: UpToDate` (`-SkipToolkits`). Installed sender offline checks
and setup WhatIf passed without reading real credentials. Actual XML stays unchanged outside Git.
The old current-chat flow is OFF; installed v2 alerts are ON for this chat under explicit user
consent. Auto TTS remains independently ON. The normal-title Question dry run used only the
installed sender; the server accepted it and the user confirmed phone delivery and correct
MacroDroid routing. The user then explicitly approved commit/push of the reviewed 17-file skills
batch; its final revision belongs in Git history rather than this self-referential snapshot.

AgentDebugToolkit Phase 1a was published as `6587af7`; Batch A as `75e2b4d`, with its exact ten-file
scope and remote hash independently verified. Batch A's independent full build had zero warnings/
errors and all 388 tests passed. Batch B is implemented; its final TRX independently confirms
106 passed / 0 failed / 0 skipped. The agent reported a successful build, without a warning count.
Its 25 exact source files are frozen outside Git and staged under explicit user approval;
staging is not commit approval. The primary cumulative B source audit found no confirmed new
defect. An isolated base-A checkout plus all 25 hash-verified B files independently built with
0 errors and 6 NU1900 warnings from unavailable configured vulnerability feeds; this was not a
warning-clean build. Its fresh-checkout missing-assets failure and successful restore/build logs
are preserved. Independent targeted runs passed 48 + 58 distinct cases, verified to match all
106 original case names exactly; the first selector omitted debugger classes named differently
from their source filename. No cases were repeated to hide a failure. Publisher syntax passed.
All five protected baseline hashes were independently unchanged before the C handoff.

Batch C Phase 3 bounded inspection is implemented in 14 unstaged files; its actual final reply
and 86-pass/0-failure/0-skip TRX were independently verified. Phase 4 structured paged UIA readers
is implemented; the actual final reply and 174 distinct passing TRX cases were independently
verified, including all 86 selected Phase 3 cases. CLI/MCP now have `read-rows` and
`read-tree-items`; successful live provider integration remains untested. Phase 5 verified
selection has reported implementation/build completion. Its original combined run was
267 passed / 33 failed; a corrected fake-resolution counter recheck passed the entire 58-case
selection-engine class. The primary independently verified 242 unaffected passes + those 58
corrected cases cover exactly the original 300 names, NOT one clean combined run. Failures stay
preserved. The 26-file cumulative C source snapshot is reviewed with no confirmed new production
defect. The actual `msg-provider-fixtures` reply and its new six-method WPF integration test
file were reviewed; its reported build succeeded, but tests were deliberately not run. Review
caught an incorrect tree-offset expectation before execution and a minor CLI budget-scope doc
ambiguity. The actual `msg-provider-corrections` completion and exact corrected lines are verified:
tree index 1 must be child B with its exact ID; grid selection must contain one item; docs allow
budgets on the other supported verbs. No assertions were weakened. Independent final full-solution
CLI build passed with 0 warnings / 0 errors. The host VS build tool could not build the external
project because it lacks an active configuration here; CLI validation succeeded instead. Source
hash comparison shows only the expected new test and contract-doc changes since the C audit;
the 124-file final baseline is saved. Frozen B index hash and its 25-path scope are verified.
The authorized final full suite ran with the desktop idle: 764 tests, 762 passed, 2 failed, 0 skipped.
Five of six new provider-fixture tests passed. The bounded inspect/text fixture failed because its
maxNodes=6 budget stops before the first TextBlock; this is a test expectation defect, not evidence
that bounded traversal returned a wrong value. An existing minimized coordinate double-click case
also failed while click and right-click variants passed; this needs a focused diagnosis before any
claim of full regression success. Full log is preserved externally. No retry or assertion weakening
was performed. No WinForms/x86/hardware or real publication claim is established. The B staged
fingerprint must remain unchanged, and C must remain unstaged. No commit/push/publication/toolkit
installation, production apps/debugger/hardware actions. The toolkit agent then fixed both failures in test scope: the bounded fixture uses maxNodes=8
so its first text node is reachable while the budget assertion remains; the minimized pointer
fixture waits for the native IsIconic state before invoking restore/double-click. Focused evidence
is 7 passed / 0 failed / 0 skipped and the covering test-project build succeeded. No production
code changed. The full-suite rerun cleared both original failures but reported four focus-sensitive failures
(760 passed / 4 failed): two window-input and two scroll cases returned foreground-activation-failed.
The agent suspected desktop foreground contention: fixtures use ShowActivated=false
and depend on SetForegroundWindow; the root cause is not proven. A focused run passed send-keys,
paste-text, vertical scroll and horizontal-left; horizontal-right delivered the CLI success response
but did not produce the expected fixture message. No reproducible production regression or contract-
correct fix was established, so no files changed in that diagnosis. Evidence is preserved in the
focused TRX and both full-suite logs. Do not claim a clean full suite or publish until the desktop
focus issue and horizontal-right behavior are separately resolved or explicitly accepted.
At the user's request, a single additional focused invocation passed all five affected cases
(send-keys, paste-text, vertical scroll, horizontal-left/right): 5 passed / 0 failed / 0 skipped.
The primary verified all five named TRX results and counters; log/TRX are preserved externally
as `focus-five-user-requested-once`. No source changes or repeated attempts accompanied that run.
This verifies this invocation only, not a clean full suite or resolution of intermittent failures.
Closeout verification: final solution build passed again with 0 warnings/errors. Frozen B index
still matches its approved fingerprint. Hash comparison against the pre-validation baseline
shows only the reviewed two test edits and two generated ignored TRX files; protected files
are unchanged. User authorized toolkit commit/push/install once changes are good; accepting
the remaining intermittent full-suite limitation versus further diagnosis is pending.
Notification packaging v2 is prepared only in an external draft: installed-relative bundled
sender/setup, unchanged runtime implementations, and compatibility forwarders for old paths.
Unified skill diff was shown; draft offline privacy/setup checks and PowerShell parsing passed.
Source/installed skill remain v1 pending explicit apply approval; install and live dry run follow.
Earlier watcher/activation failures did not establish that the agent stopped; host focus was
returned and the cursor indicator cleared after the successful handoff.



This repo remains docs-only. Its project marker is v27; applying source skill v28 does not itself
rerun Bootstrap. Five reusable scripts are indexed, including the notification helpers and a
read-only exact TRX coverage comparator saved from this verification.

## Recently changed

- Pending commit: four notification/handoff skills, generated index, script catalog, README,
  code summary/design notes, credential ignore rule and the three notification helper/test scripts.
- Added `scripts/agent/Compare-TrxCoverage.ps1`: read-only reference-versus-combined-run coverage
  verification, rejecting duplicates, missing/extra cases and non-passing/incomplete runs.
- Live Pushbullet tests reached the phone; the user confirmed MacroDroid routing works with the
  fixed titles. Current sender prefixes approved repository names without accepting arbitrary
  message bodies. Offline tests cover payload privacy and encrypted first-machine setup using
	disposable dummy credentials, not the real token. The authorized nearby-helper copy is now
  hash-verified. All three live-sender `-WhatIf` previews passed with no network sends or token
  reads; interactive enable/stop and actual-phone handoff tests remain pending. The nine approved
  draft/diff artifacts were cleaned up after exact-match verification.
- Bootstrap: `.github/copilot-instructions.md` and this file.
- Committed/pushed `99b9173`: `ui-interaction` v21, `vs-debug` v10,
  `agent-orchestrator` v20 and `skills-index.json`. Installed copies were hash-verified.
- Committed/pushed `3ce128e`: `read-aloud/SKILL.md` now requires hosting-repository identity
  and announcements before blocking questions in both speech modes. Installed copy matches
  the approved draft/source hash; post-install check reports `RESULT: UpToDate`.

## Secrets / personal-data review (2026-11-13)

All four repos, working trees and full history: no tokens, keys, passwords, databases or binaries. Fixed and
pushed to the public toolkit repos the same day (GraphTools 91e46d6, AgentDebugToolkit 67f28aa,
VsChatHistoryToolkit 65e7594): personal email line removed from GraphTools copilot-instructions.md;
session-state/ added to AgentDebugToolkit .gitignore; MIT LICENSE added to all three. Left as is: the
committed graph JSONs in AgentDebugToolkit and VsChatHistoryToolkit contain C:\Users\sveluswa\.nuget\...`npaths (username only; the graphs are those repos' own project memory, so they stay tracked).
In this repo only `.github/copilot-instructions.md` (Bootstrap-generated) holds a username path.

## Open tasks/bugs

- Notification v2 packaging, installed hash/offline checks and the user-confirmed phone/routing
	dry run are complete. The reviewed skills batch has explicit commit/push approval.
  The old flow is disabled and the installed skill enabled for this chat only. Enable/stop
  command/timing branches remain partly untested. Missing-XML skill guidance
  has been reviewed but not exercised interactively; the real credential was never moved/deleted.
  New skill discovery may require a new chat. No incoming-phone-reply bridge is implemented.
- TTS pre-question timing: user confirmed the repo-labelled auto-TTS announcement finished
  before the question card while this VS was inactive. Regular TTS, active-window silence,
  both-mode precedence and disabled-mode scenarios remain untested for this change.
- The graph skill's Step 0 toolkit check ran in this chat and reported `GraphTools UpToDate`;
  repair/error branches were not exercised.
- Not run: I-39 (missing `skills-source.json`),
  `SOURCE: Differs` / `NotRecorded`. Not observed: Defender/SmartScreen on locally built unsigned
  executables; PowerShell 7 (only 5.1 installed).
- TTS: new `read-aloud` skill (committed, installed, hashes verified) with `Speak-Text.ps1` plus
  opt-in ducking (`AudioDucker.cs`); graph skill v27 (Step 7c is now a pointer bullet; its `Speak-Text.ps1`
  is a forwarder). Tested in a temp folder: helper round trip, manual-change case, ducking during speech,
  kill mid-speech then recovery, stub installed and not installed; live ducking heard and accepted at
  `duckPercent` 10 (user's machine setting, not in the repo). Not tested: NoVoice with ducking on,
  PowerShell 7, a real chat triggering the skill from "enable tts".
- Hooks need `git config core.hooksPath .githooks` once per clone (set here); web-UI edits and
  `--no-verify` bypass them. No GitHub Action exists.
- The `install-skills` skill ran in this chat: remote check, approved install with
  `-SkipToolkits`, installed-file hash comparison and post-install check all succeeded.
- Not tested: `Speak-Text.ps1` on a machine with no voice (simulated only).
- Not run live: tool permission prompts, workspace banners, the V2 Idle-to-Pending upgrade path, a card
  above a scrolled-up chat list, the `Send-CopilotPrompt.ps1` new-session path. All `AgentCursor` and
  `Compare-RepoSnapshot` cases are marked not run; `Install-Skills` I-01 to I-19 and I-24 to I-35 ran in a
  sandbox only.
- AgentDebugToolkit repo (separate): `tools/Watch-CopilotChat.ps1` still has the old name and is not
  synced with V1; improve the list-windows
  flag error message; add a test trait for the interactive-desktop click test. It also has two
  uncommitted graph doc files, deliberately left out. Feedback review confirmed current MCP
  `ui_inspect` is already read-only and has no screenshot option.
- `docs/DESIGN_DECISIONS.md` has an unrelated pre-existing typo ("ersion" in the 2026-11-13 skills index
  entry), not fixed.
- No code graph or Key Flows file is generated here. Documentation changes need no application
  build; installer consistency and generated-index checks apply.
