# Code Summary

This repo is a collection of GitHub Copilot CLI **skills** for use with Visual Studio Copilot. It
has no application code of its own — each top-level skill folder contains a `SKILL.md` (the
skill's instructions/workflows) plus supporting docs and assets. `Install-Skills.ps1` copies each
skill folder into `%USERPROFILE%\.copilot\skills\` so they're available to the Copilot CLI.

No C# solution detected in this repo; tracked in docs-only mode (no code graph).

Feedback diagnostics: updated AgentDebugToolkit build markers provide exact managed tool paths;
skills still verify the selected binary's own identity/capabilities. V2 orchestration optionally
emits phase/heartbeat facts without extra UI probes; watcher observations never declare overall
task completion. Read-aloud retains legacy failure markers and adds bounded, text-free diagnostics
plus non-speaking availability checks, with no voice selection or notification coupling.

Generic hardware-session guidance distinguishes failed audio from intentional foreground silence
and server acceptance from user-confirmed phone receipt. Orchestration documents tracked async
commands, live step/parameter-iteration evidence and verified reusable cleanup, not new runtime
helpers. `docs/framework-improvements.md` lists reported, unverified framework candidates only.

Reusable session helpers are indexed in `docs/SCRIPTS.md`. `scripts/agent/Compare-TrxCoverage.ps1`
checks that complete passing TRX files jointly cover exactly a reference case set, rejecting
duplicates and missing/unexpected cases without running tests or changing files.
`scripts/agent/Test-InstallSkillsCredential.ps1` verifies credential exclusion, preservation,
nested copying and pruning in a disposable fake profile, without real credentials or network.
`scripts/agent/Test-ReadAloud.ps1` mocks speech and auto-TTS with a disposable wrapper fixture;
`scripts/agent/Test-WatcherProgress.ps1` tests AST-isolated progress cadence and terminal semantics
without UI calls or file writes. Neither establishes remote audible/foreground recovery.
`scripts/agent/Test-SendCopilotPrompt.ps1` tests quoted native arguments with a disposable
argument-echo process and input read-back/send gating with mocks, without accessing any chat.
`scripts/agent/Test-ReadCopilotReply.ps1` runs the transcript and reader scripts against a fake UI
executable serving synthetic trees to test structural reply classification, without any chat.
`vs-chat-history/scripts/Invoke-IdleChatRename.ps1` is the canonical bundled one-shot UI
worker: waits for an approved final-message hash and stable idle before renaming a pinned
host/session, verifies clipboard/foreground/title/save/reopen and writes private timed facts.
The root `scripts/agent/Invoke-IdleChatRename.ps1` forwards unchanged parameters/output to it;
`Test-IdleChatRename.ps1` stays repository-only and tests strict guards, forwarding and the
documented independent launcher with mocks. Tracked workers prevented idle; use the skill's
independent handoff, not a tracked worker. The optimized self-rename/restore passed all checks;
the other-chat recovery restored its title/context but lacked full caller-context verification.
Scoped title reads and optional `-DelaySeconds 2` reduce overhead; timings are host-specific.

## Update index and hooks

| File | Responsibility |
|---|---|
| `skills-index.json` | Generated: per skill `version` and one-line `whatsNew`. Read by each skill's Step 0 (clone copy and `git show "@{u}:skills-index.json"`) instead of the whole `SKILL.md`. |
| `scripts/Update-SkillsIndex.ps1` | Generator, derived from each `SKILL.md`'s `CURRENT_SKILL_VERSION` and changelog entry. `-Check` (read-only), `-Stage`, `-WarnUnbumped` (staged vs HEAD), `-WarnUnbumpedFrom/-To` (range, warn only). |
| `.githooks/pre-commit`, `.githooks/pre-push` | Regenerate and stage the index on commit; warn (never block) about a missing version bump over the whole push. Need `git config core.hooksPath .githooks` per clone; LF line endings (see `.gitattributes`). |
| `Install-Skills.ps1 -Check` | Also prints `INDEX: UpToDate / OutOfDate / Missing`; does not change `RESULT:`. |

## Toolkits and installer state

| Item | Responsibility |
|---|---|
| `Install-Skills.ps1` (toolkit part) | Per toolkit used by a skill (GraphTools, AgentDebugToolkit, VsChatHistoryToolkit): clone from `<ToolkitBaseUrl>/<Name>` into `%USERPROFILE%\.copilot\toolkits\<Name>`, fast-forward with `-Remote` (never over uncommitted changes), build with the toolkit's `scripts\agent\Build-Toolkit.ps1`. One `TOOLKIT: <Name> <Status>` line each (`UpToDate`, `NotInstalled`, `NeedsBuild`, `Behind`, `Diverged`, `NotAClone`, `NoDotnetSdk`, `NoGit`, and after a real run `CloneFailed`, `PullFailed`, `NoBuildScript`, `BuildFailed`); exit 1 if a clone, pull or build failed. `-SkipToolkits`, `-ToolkitBaseUrl`. |
| `%USERPROFILE%\.copilot\skills-source.json` | Written by every real installer run: `{"schema":1,"skillsRepo":"<clone path>"}`. Every skill's Step 0 reads `skillsRepo` instead of a path typed into its `SKILL.md`; `-Check` prints `SOURCE: Recorded / Differs / NotRecorded`. |
| Toolkit repos (separate, public) | Each has an integer `VERSION` and `scripts\agent\Build-Toolkit.ps1`, which builds in place and writes `.built-version` (git-ignored) with the built commit. A toolkit is `NeedsBuild` when that commit differs from `HEAD`. |
| Skills' toolkit check | Step 7 in `vs-debug`, `ui-interaction`, `vs-chat-history`; Step 6a in `agent-orchestrator`; Step 6 in `project-memory-management-graph`. Runs `Install-Skills.ps1 -Check -Remote -MaxAgeHours 6`, filtered to the skill's own `TOOLKIT:` line, and asks before running the installer. `ui-navigation-orchestrator` and `project-memory-management` have none. |

## Skills in this repo

`vs-copilot-chat-voice` adds assistant-side policy for the separate VsCopilotChatVoice
application: explicit one-shot prototype handoffs, dual-version content and live VS ownership.
Automatic delivery and authoritative Speaker state require the unavailable production bridge.
No runtime helper or application binary is bundled; the existing installer/index discover v1.

| Skill | Purpose |
|---|---|
| `project-memory-management` | Deprecated predecessor; use `project-memory-management-graph` in docs-only mode instead. |
| `project-memory-management-graph` | Begin Session, Bootstrap, End Session and Initialize; supports docs-only repos or registered per-solution Roslyn graphs through GraphTools. Includes user-curated feature-checklist guidance and regression-audit protocols. Ships `scripts/Speak-Text.ps1`, now only a forwarder to the `read-aloud` skill's copy so the path written by Bootstrap v25 and v26 keeps working; Step 7c (v28) writes a short pointer delegating ready-handoff timing to `read-aloud`, with enabled push preceding enabled TTS. |
| `agent-orchestrator` | Supervise a Copilot agent in another Visual Studio window; composes UI interaction and debugger skills. Reuses exact-binary capability checks and bounded raw probes; generic UIA selection never replaces card submit/echo verification. The bundled script set is the same (v32 adds an opt-in `-Trace` for per-stage timings to `Send-CopilotPrompt` and cheaper own-host, banner and draft checks that keep every guard; v33 makes it refuse at once with `InputOffScreen` when the chat input is outside the visible screen; v34 makes it and `Select-ChoicePromptOption` wait for a quiet keyboard and mouse, stop if the person starts typing, and hand their window and focus back): `Send-CopilotPrompt`, `Watch-CopilotChatV2` (default: light poll), `Watch-CopilotChatV1` (full tree/details), `Get-CopilotChatTranscript`, `Select-ChoicePromptOption` and `Compare-RepoSnapshot`; learned scripts are indexed in `scripts/SCRIPTS.md`. |
| `ui-interaction` | Shared AgentDebugToolkit UI primitives: scoped selectors, exact-binary capability checks, opt-in bounded inspection, UIA row/tree pages, authoritative state reads, verified toggle/replacement-selection changes and explicit restore. Partial observations remain unknown; budgets are cooperative, not hard deadlines. Documents Windows PowerShell 5.1 and partly off-screen-window gotchas (v24), and the shared quiet-wait, do-not-disturb, input-lock and focus hand-back helpers in `AgentCursor.ps1` (v25). Preserves typed-input read-back and the shared cursor indicator `scripts/AgentCursor.ps1` (blue = orchestrator, green = UI run, red = input), also used by `ui-navigation-orchestrator`. |
| `ui-navigation-orchestrator` | Navigate WinForms/WPF apps with a per-target-repo navigation-tree cache; composes `ui-interaction` and `vs-debug`. |
| `vs-debug` | AgentDebugToolkit/EnvDTE bridge: capability-gated static help, explicit VS-instance targeting, optional non-atomic break context and seconds-based long waits, plus attach/breakpoints/stepping/stacks/thread-frame selection/evaluation. VS and debuggee PIDs are distinct; expression side effects still require explicit consent, and exception locals do not prove stop cause. |
| `vs-chat-history` | Search/read local history through `chathistory`; v13 bundles the independent idle-handoff worker for this responding chat and gives optimized direct UI steps for another verified idle chat. Never rename during generation. The installer recursively copies the runtime; repository compatibility/test entry points and private test artifacts are not installed. UI identity/title/reopen verification is separate from CLI coverage, activity/force checks, restart behavior and undo logging. |
| `read-aloud` | Optional current-chat speech, triggered by "enable tts" / "start tts" (off: "disable tts" / "stop tts"), plus independent auto tts (`enable auto tts` / `start auto tts`; off: `disable auto tts` / `stop auto tts`). At a ready handoff, send any qualifying enabled push, run speech last, then immediately show the question/reply. Auto tts calls `scripts/Speak-IfAway.ps1 -Text`; its read-only `Test-HostVsActive.ps1` locates the host `devenv.exe` through parent processes or `-HostPid` and compares its foreground state. Only `Inactive` speaks; `Unknown`/errors stay silent. Plain tts wins if both modes are on. `Speak-Text.ps1` uses the Windows default System.Speech voice (`-Text` only; `NoVoice`, exit 2 when unavailable). Optional ducking uses in-memory `AudioDucker.cs`, `%USERPROFILE%\.copilot\tts-settings.json` and temporary `tts-duck-state.txt`. Unversioned, not in `skills-index.json`. |
| `push-notifications` | Opt-in current-chat Pushbullet alerts with stable Completed/Question/Blocker titles for MacroDroid, approved repository-prefixed fixed bodies and no task details. Start/enable checks for local encrypted XML; missing setup leaves pushes off until a fresh start/enable command. Bundles the canonical sender/setup under its own `scripts/`; XML defaults beside those installed scripts, outside Git. Old `scripts/agent/` forwarders explicitly default to that installed location. Installer excludes `pushbullet-token.xml` from copying/pruning; legacy XML migration requires approval and has no silent fallback. Ready handoff order is push, active TTS, then the question/final reply. |
| `install-skills` | Lets Copilot install/update the repo's skills on request ("install skills from <url>", "check the repo and update all the skills"): `Install-Skills.ps1 -Check -Remote` (read-only, `REMOTE:`, `TOOLKIT:` and `RESULT:` lines), then `-Remote -Force` (pull + install + clone/update/build the toolkits), `-Prune` only after asking. Skills with a Step 0 update check compare clone/upstream versions once per session; `read-aloud` and `push-notifications` have no such check. |
