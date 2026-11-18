---
name: vs-debug
description: 'Attach the Visual Studio debugger to a running application via AgentDebugToolkit''s agentdebug-vs.exe (EnvDTE COM): set breakpoints, step, read call stacks, and resolve which source file/line/handler ran for a given action. Independently useful for any debugging task, not only ones reached via UI navigation. May call the ui-interaction skill to trigger an app UI action while attached, in order to hit a breakpoint. Does not build or maintain any persistent map of an application — see ui-navigation-orchestrator for that.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 11`. Compare against the source-of-truth copy at
  `<skills repo>\vs-debug\SKILL.md` (the clone path is in
  `%USERPROFILE%\.copilot\skills-source.json`, see Step 0), and against that clone's GitHub
  upstream, once at the start of a session.
- Changelog:
  - v1 — initial version. Extracted from `ui-debug-map`, which mixed this debugger-bridge
    mechanism together with map schema/policy; this skill now holds just the debugging mechanism,
    usable on its own regardless of whether any navigation map exists or is ever built.
  - v2 -- added an explicit "Step 0: Version Check" step (run once per session, never per
    attach/breakpoint/step/read-call-stack call), matching agent-orchestrator's pattern.
  - v3 — picked up AgentDebugToolkit's Phase 21/22 verbs (2026-10-02), which close most of the
    gaps that previously required falling back to `ui-interaction`/UI automation for debugger
    control: PID-targeted `attach-process`/`break-all`/`detach` (detach leaves the debuggee
    running — distinct from `stop-debugging`), reliable state reporting with a bounded-retry
    `com-busy-retry-exhausted` outcome on COM-busy rather than an indefinite hang, and
    thread/frame selection plus expression evaluation (`list-threads`/`select-thread`/
    `select-frame`/`evaluate`). Added documentation for each new verb, an end-to-end quick-
    reference workflow, and narrowed Prerequisites/Limitations to reflect that UI automation is
    now a fallback for what these verbs don't cover, not a default path. No existing verb's
    documented behavior changed.
  - v4 — documented two additional `select-frame` failure modes confirmed live against a real
    21-frame WPF stack trace (2026-10-02): `frame-selection-failed` can now also occur as a
    permanent, per-stack-shape EnvDTE limitation (not only the v3 mid-call resume race) for frame
    positions inside a native/managed transition region (e.g. a WinForms/WPF message loop,
    collapsed `"[External Code]"` frames, or the outermost managed frame beyond that region such as
    `Program.Main`) — reproduced with the debugger staying in break mode the entire time, ruling out
    the race. A new error code, `frame-selection-mismatch`, was added and documented: EnvDTE can
    report a `select-frame` success while silently rebinding `CurrentStackFrame` to a different
    frame than requested (live-observed: a shallow `"[External Code]"` index silently bound to
    `Program.Main` instead), which `select-frame` now detects by comparing `FunctionName` on
    read-back instead of only checking for null. No existing verb's previously-documented behavior
    changed; this only adds coverage for failure modes that previously surfaced as the same raw
    `0x80070490` HRESULT or a silently-wrong frame.
  - v5 — documented post-failure recovery for `select-frame`: after a `frame-selection-failed` or
    `frame-selection-mismatch`, `CurrentStackFrame` may be left bound to an unrelated frame
    (live-observed: the outermost managed frame). Added guidance to re-select a known-good frame
    and re-check with `get-callstack` before trusting any `get-locals`/`evaluate` call. No verb
    behavior changed — documentation only.
  - v6 — documented AgentDebugToolkit's 2026-10-14 strict option parsing for `agentdebug-vs.exe`:
    only `--allowSideEffects` and `--all` may be bare; any other flag with a missing value, or
    followed by another `--` flag, fails `invalid-argument`; empty or `--`-prefixed values need
    `--name=value` (e.g. `--expression=--i`). Documentation only; requires a CLI built from
    that change.
  - v7 — Step 0 now also checks the repo's GitHub upstream (`git fetch`, then reads the upstream
    copy of this file), not only the local clone, and offers to run
    `Install-Skills.ps1 -Remote -Force` when a newer version exists. Same trigger as before: once
    per session.
  - v8 — Step 0 reads this skill's version and what's new from the repo's small `skills-index.json`
    instead of the whole `SKILL.md`, so the update check costs about 2 KB, not up to 100 KB. If the
    index cannot be read it falls back to a filtered read of the version line.
  - v9 — The skills repo clone is found through `%USERPROFILE%\.copilot\skills-source.json` and
    AgentDebugToolkit through `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit`, instead of fixed
    `C:\MyFiles\Git` paths, and Step 0 gains a toolkit check (clone, update and build through
    `Install-Skills.ps1`). Needs the `Install-Skills.ps1` from the same change; no verb changed.
  - v10 - Corrects CLI verb names and documents exception inspection, wait limits, portable
    packages, and expression-evaluation caveats. Documentation only; no toolkit verb changed.
  - v11 - Documents executable capability checks, static help, explicit VS-instance targeting,
    optional break context and seconds-based long waits without changing evaluation permissions.

# VS Debug

Drive Visual Studio's debugger against a running application via `agentdebug-vs.exe`, and resolve
runtime behavior down to exact source. This skill is a pure mechanism, like `ui-interaction`: it
attaches, breaks, steps, and reads — it has no opinion about *why* you're debugging something and
does not persist anything about what it finds. A caller (e.g. `ui-navigation-orchestrator`, or a
person debugging directly) decides what the resolved source location means and whether to keep a
record of it.

## Prerequisites / environment

- **Toolkit location:** same as `ui-interaction` — AgentDebugToolkit is cloned and built by
  `Install-Skills.ps1` at `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit` (expand
  `%USERPROFILE%` to an absolute path before using it). If that folder or the exe is missing,
  Step 0's toolkit check says what to do; never guess another path or use a different clone.
- Tool: `agentdebug-vs.exe`, built from
  `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit\src\AgentDebugToolkit.Debugger.VisualStudio`
  (exe under `bin\Debug\net8.0-windows\`; built by the toolkit's `scripts\agent\Build-Toolkit.ps1`,
  which `Install-Skills.ps1` runs, so do not build it by hand). This is a
  separate CLI/process from `agentdebug-ui.exe` — it drives Visual Studio's debugger via EnvDTE
  COM, not the UI via UIA.
- **Explicit portable package:** if the user supplies a package location instead of the managed
  installation, use `<package>\vs\agentdebug-vs.exe` and that package's docs. Record the exact
  executable path; Step 0 checks the managed clone/build, not this separate package's capabilities.
  Do not silently switch between them. On capable binaries, `help`, `--help`, `<verb> --help`
  and `help --verb <verb>` return static JSON without contacting VS. Use canonical `get-callstack`;
  `get-call-stack` is a supported alias, but `read-call-stack` is not. Verify help capability
  before using these additions on an older package.
- **CRITICAL environment gotcha:** clear `DOTNET_ROOT`
  (`Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue`) before invoking `agentdebug-vs.exe`
  or `dotnet build`/`restore`, same as `ui-interaction`.
- Full verb contract: `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit\docs\CLI_CONTRACT.md`.
- **UI automation is a fallback, not a default.** As of Phase 21/22, `agentdebug-vs.exe` itself
  covers PID-targeted attach/break/detach, reliable state reporting, and thread/frame/locals/
  evaluate inspection entirely via EnvDTE/COM — no UI automation/SendKeys involved. Only reach for
  `ui-interaction` when the goal genuinely requires *driving the app's own UI* (e.g. clicking a
  button to trigger the code path you want to hit) or for something this skill's verbs don't
  cover at all. Do not use `ui-interaction` to drive Visual Studio's own debugger UI (breakpoint
  margin clicks, Locals window, etc.) — every one of those is now a direct, reliable verb here.

## Step 0: Version Check

Run this **once**, the first time this skill is used in a session — not on every individual
attach/breakpoint/step/get-callstack call.

1. Find the repo clone: read `skillsRepo` from `%USERPROFILE%\.copilot\skills-source.json`, which
   `Install-Skills.ps1` writes:
   `(Get-Content "$env:USERPROFILE\.copilot\skills-source.json" -Raw | ConvertFrom-Json).skillsRepo`.
   Call it `<skills repo>` below. If the file or the folder does not exist, use the same "ask, don't
   guess" fallback as the toolkit above: ask the user where the clone is.
2. Check GitHub: `git -C "<skills repo>" fetch --quiet origin`. This
   changes no working file. If it fails (offline, no upstream), say once that GitHub could not
   be checked and continue with the clone alone.
3. Read this skill's entry from the repo's small `skills-index.json` (about 2 KB), not from the
   whole `SKILL.md` (which can be over 100 KB). The repo version is the higher `version` of the
   two copies below, and its `whatsNew` is the change to report. Keep only the printed `version`
   and `whatsNew`:
   - GitHub's copy (skip if the fetch failed): `(git -C "<skills repo>" show "@{u}:skills-index.json" | Out-String | ConvertFrom-Json).skills.'vs-debug'`
   - The clone's copy: `(Get-Content "<skills repo>\skills-index.json" -Raw | ConvertFrom-Json).skills.'vs-debug'`
   - If neither can be read (a repo from before the index existed), read only the version line,
     never the whole file: `Select-String -Path "<skills repo>\vs-debug\SKILL.md" -Pattern 'CURRENT_SKILL_VERSION\s*=\s*\d+' | Select-Object -First 1`.
4. Compare the repo version to this file's own `CURRENT_SKILL_VERSION`.
5. If the repo's version is higher: tell the user what's new (the index's `whatsNew` line; if more than one version behind, say how
   many and offer to list the older changelog entries) and whether the newer version is only on GitHub (clone not pulled
   yet) or already in the clone. Ask via `ask_user` whether to update now. On yes, run
   `& "<skills repo>\Install-Skills.ps1" -Remote -Force`: it pulls the
   clone (fast-forward only, never when tracked files have uncommitted changes), installs every
   changed skill, and clones, updates and builds the toolkits; tell the user the new text applies
   from a new chat session. On no, proceed with the current session and do not ask again in it.
6. If versions match: proceed silently.
7. Toolkit check (also when the versions match). Skip it if step 5 just ran the installer
   successfully. Run this read-only command, which changes nothing:
   `& "<skills repo>\Install-Skills.ps1" -Check -Remote -MaxAgeHours 6 | Select-String '^TOOLKIT: AgentDebugToolkit '`
   and act on the status word in the line:
   - `UpToDate`: proceed silently.
   - `NotInstalled`, `NeedsBuild` or `Behind`: tell the user what the line says and ask via
     `ask_user` whether to run `& "<skills repo>\Install-Skills.ps1" -Remote -Force` (it clones or
     fast-forwards the toolkit and builds it, about a minute, and also installs changed skills). On
     yes, run it and check the exit code. On no, continue only if `agentdebug-vs.exe` exists
     (`Behind` works with the installed build); otherwise stop, because this skill cannot work
     without it.
   - `Diverged`, `NotAClone`, `NoDotnetSdk` or `NoGit`: report the line once and change nothing;
     continue only if `agentdebug-vs.exe` exists.
   - No `TOOLKIT:` line (an older installer): continue only if `agentdebug-vs.exe` exists,
     otherwise ask the user.
   Do not ask again in this session.
8. **Exact-executable preflight, once per chosen binary.** Run `<chosen exe> info` and record
   its actual path, architecture, embedded build facts and capabilities; UI executable identity
   or the managed checkout's HEAD does not identify this VS binary. Null build facts are unknown.
   For a portable package, use `info --verifyPackage`: only `matched` establishes manifest
   consistency, not a signature/trust guarantee. Report `not-present` as unverified and ask before
   relying on it; stop using a mismatched package. Required new capability IDs are
   `vs.help.json.v1`, `vs.instance-targeting.v1`, `vs.break-context.v1` and
   `vs.wait-for-break.long.v1` for the corresponding workflows below. If `info` or a needed ID is
   unavailable, do not assume the new verb/flag exists: use verified legacy behavior or ask to
   update the chosen installation. MCP additionally requires the running server to advertise the
   matching tool/schema; a CLI build does not restart that server or grant mutation permissions.

## Core operations

- **Instance targeting applies to every targeted command below.** On capable builds, first use
  read-only `list-instances` (no options) to identify the intended instance, then pass its verified
  `--instancePid <VS pid>` on every call; it is not persisted. This is the Visual Studio PID,
  not `--pid <debuggee pid>`. Optional `--solution <name>` is an additional AND constraint, not
  a fallback. Duplicate solution names need the exact VS PID. Unqualified ordinary commands
  retain legacy first-ROT-instance behavior, so do not use them to guess among several windows.
  Discovery may omit busy/unregistered instances and return null fields/errors; absence does
  not establish that VS is not running. Explicit targeting failures must not fall through to
  another instance. Signatures below omit these common flags for brevity.
- **debugger-status** — inspect the explicitly selected VS instance's mode; use `attach-process`
  only when attachment is needed. With `--context true`, also observe instance, selected thread/
  frame function, exposed `exceptionLocal`, last breakpoint, `modeAtEnd` and per-field errors.
  `breakReason` remains `unknown`; observations are non-atomic and null fields remain unknown.
  The root `activeDocument`/`activeLine` are last-hit-breakpoint observations, possibly historical,
  not proof of the current stop cause or selected frame's source. Inspect context errors and
  the call stack; neither a present nor absent `$exception` proves why execution stopped.
- **attach-process `--pid <n>`** — attach by explicit PID rather than by name/already-debugging
  process. Without explicit instance constraints, registered VS instances are scanned for that
  PID in `LocalProcesses`; `--instancePid`/`--solution` restrict this search. Returns
  `{ pid, mode }`. Fails with `process-not-found` if no instance sees that PID, or
  `ambiguous-process` (with a `candidates` list of `{instance, solution}`) if more than one
  instance can see it. Resolve the intended VS PID rather than guessing; explicit instance
  discovery can also return `ambiguous-instance`, `instance-unavailable` or `devenv-not-found`.
- **set-breakpoint / remove-breakpoint** — both take `--file <absolute path> --line <n>`.
  `list-breakpoints` enumerates existing breakpoints. Method-signature breakpoints and the alias
  `clear-breakpoint` are not implemented by the current CLI.
- **break-all `--pid <n>`** — breaks *every* thread in the target debuggee process (not just the
  current thread), resolved via the instance's `DebuggedProcesses` (processes under an active
  debug session — distinct from `LocalProcesses`, which is every attachable process whether or
  not it's being debugged). Same `process-not-debugged`/`ambiguous-process` failure shape as
  `attach-process`. Use this instead of waiting on a breakpoint when you need to stop the process
  *right now*, regardless of where it currently is.
- **wait-for-break `(--timeoutMs <n> | --timeoutSeconds <n>) [--pollMs <n>]`** — wait for any
  break mode, not just a breakpoint. Supply exactly one timeout unit; whole seconds are 0..590.
  Prefer `--timeoutSeconds 60` for one minute. Legacy direct-CLI milliseconds remain
  0..2147483647; there is no 170-second poll-loop cap. Polling defaults to 250 ms.
  Current MCP accepts 0..590000 ms or 0..590 whole seconds, rejecting out-of-range values rather
  than clamping to the old two-minute limit. Its outer process budget is requested wait plus
  10000 ms, at most 600000 ms. Target resolution/COM overhead and an in-flight call can exceed
  the polling budget; neither this nor a shell runner promises a hard deadline.
  A polling timeout reports `timeoutMs`, `pollMs` and `elapsedMs`; an outer runner timeout is
  distinct. For longer tests, repeat bounded waits only after an explicit polling `timeout`,
  preserving the same verified VS target; report other failures. Never resume the debuggee
  merely because a wait timed out. Use an asynchronous shell when supported; after a break,
  call `debugger-status --context true` and `get-callstack` on that same instance.
- **list-threads** — enumerate the current program's threads (real OS/runtime thread ids, not
  CLI-invented handles). Requires break mode; fails `no-current-program` if nothing is being
  debugged.
- **select-thread `--threadId <n>`** — sets `Debugger.CurrentThread`, genuinely changing which
  thread subsequent `get-locals`/`get-callstack`/`select-frame`/`evaluate` operate on (not merely
  tracked externally). Fails `thread-not-found` for an unknown id.
- **select-frame `--index <n>`** — 0-based, innermost-first (frame 0 matches `get-callstack`'s
  `frames[0]`). Frames have no stable id in EnvDTE, so they're re-resolved by position on every
  call rather than cached — re-select after any step/continue. Fails `no-thread-selected` if no
  thread has been selected yet, or `frame-index-out-of-range` if `--index` exceeds the selected
  thread's frame count. Can also fail `frame-selection-stale` if the debuggee resumes and re-pauses
  *during* the call itself (e.g. an enabled breakpoint elsewhere actively firing) — live-confirmed
  this is not tied to any specific thread (not a WPF-dispatcher-thread limitation); it reproduces
  on any thread whenever background code is actively hitting a breakpoint, and goes away once that
  breakpoint is removed/disabled. Retry with `break-all` then `select-frame` again when you see it
  — but if an enabled breakpoint is actively firing in background code, disable or remove it first
  (or select the frame immediately after `break-all`), otherwise the retry will fail the same way.
  Separately, `frame-selection-failed` (same underlying HRESULT, `0x80070490`) and
  `frame-selection-mismatch` can occur even while the debugger stays in break mode the whole time —
  live-confirmed as a known EnvDTE limitation (not a race) for stack positions inside a
  native/managed transition region (e.g. a WinForms/WPF message loop, collapsed `"[External Code]"`
  frames, or the outermost managed frame beyond that region such as `Program.Main`): EnvDTE either
  can't make that position current at all (`frame-selection-failed`) or silently rebinds
  `CurrentStackFrame` to a different frame than requested (`frame-selection-mismatch`, which names
  the frame actually bound). There is no workaround — select a different frame index instead of
  retrying; `evaluate`/`get-locals` remain reliable on frames outside this region.
  After either failure, `CurrentStackFrame` may be left bound to an unrelated frame (live-observed:
  the outermost managed frame, e.g. `Program.Main`). Never trust a `get-locals`/`evaluate` call made
  right after a failed `select-frame` — re-select a known-good frame first (index 0 if managed, or
  the last index that succeeded) and re-check with `get-callstack` before inspecting anything.
- **step-into / step-over / step-out** — the exact CLI verbs; there is no generic `step` verb.
- **get-callstack** — returns the current call stack once broken; capable builds also accept
  `get-call-stack` as an alias, not a separate implementation.
- **get-exception-info** — checks the current frame's locals for `$exception`, returning
  `exceptionType` and `message` (EnvDTE's value representation). `no-active-exception` means no
  `$exception` was found in that frame; it does not establish why the debugger originally stopped.
  `debugger-status` and `wait-for-break` report a last-hit-breakpoint location, which can be null
  for an exception or manual break. Inspect the stack and exception explicitly in that case.
- **get-locals** — local variables for the current (innermost, or selected-frame)
  stack frame as EnvDTE string representations, not typed/structured values.
- **evaluate `--expression <text> [--allowSideEffects]`** — evaluate an expression against the
  currently selected frame (or EnvDTE's own current frame if none was explicitly selected).
  - **Strict option parsing** (2026-10-14 build onward): `--allowSideEffects` and `--all`
    (`remove-breakpoint`) may be bare; capable builds also accept bare `--context` for
    `debugger-status`. Other value-taking flags with no value, or followed by another
    `--` flag, fail `invalid-argument` before the verb runs. Pass an empty value or one starting
    with `--` as `--name=value`: e.g. `--expression=--i`, not `--expression --i`. MCP tools
    already send such values in this form.
  - **Expression read by default**: uses `GetExpression`, not `ExecuteStatement`. Implicit
    property/function evaluation depends on Visual Studio's debugger settings; this is not a
    guarantee of side-effect-free inspection, and the CLI does not change those settings. Returns
    `{ name, value, type }`. If the expression parses but can't actually be evaluated, this is a
    real failure outcome (`evaluation-failed`, with available `name`/`type` details). Record the
    exact expression, quoting, selected frame and error. An out-of-scope variable, native frame,
    debugger function-evaluation restriction, or shell quoting can need different remedies; a
    failing method call does not by itself establish a missing toolkit feature. Do not retry
    blindly or automatically enable side effects.
  - **Unsafe opt-in**: `--allowSideEffects true` switches to `ExecuteStatement`, which *can* run
    property getters, method calls, and assignments against the live debuggee. Only pass this
    when the caller explicitly wants to mutate/invoke something — never as a default retry path
    after a safe-mode evaluation fails. The response shape differs on this path
    (`{ expression, allowSideEffects: true, executed: true }`, no `value`/`type`, since
    `ExecuteStatement` doesn't return an `Expression` object to report back).
  - **No-managed-frame / no-selection outcome**: fails `no-frame-selected` if
    `Debugger.CurrentStackFrame` is null. This is a distinct, meaningful outcome from the generic
    `not-in-break-mode` error — it means either no frame was ever selected, or the attached
    process/thread has no managed frame to evaluate against at all (e.g. you're stopped in native
    code). Treat it as "nothing to evaluate here," not as a reason to retry the same call.
- **detach `--pid <n>`** — release the debugger from the target debuggee **without stopping it**
  (`Process.Detach(WaitForBreakOrEnd: false)`), returning immediately. Deliberately distinct from
  `stop-debugging`, which ends the debuggee. Use this when the caller just wanted a resolved
  location/inspection, not to kill the process being investigated. Resolved the same way as
  `break-all` (only an actively debugged process can be detached from), with the same
  `process-not-debugged`/`ambiguous-process` failure shape.

### Reliability notes that apply across all verbs above

- **`com-busy-retry-exhausted` is a real, bounded outcome — not an invitation to retry
  yourself.** Every state-reporting/action call (`debugger-status`, `wait-for-break`,
  `attach-process`/`break-all`/`detach`'s post-action mode read, and all Phase 22 verbs) is
  already wrapped in a shared retry helper that retries up to 3 times with backoff
  (100ms/200ms/300ms) across every COM-busy HRESULT Visual Studio's message filter can return. If
  you still get `com-busy-retry-exhausted` after that, the tool has already exhausted its own
  retry budget — report it as a real failure (e.g. VS genuinely wedged/mid-build) rather than
  looping more calls at it.
- **`ambiguous-process` includes a `candidates` list** — identify the intended VS instance and
  use explicit `--instancePid` (and `--solution` if useful), never the first candidate blindly.

## Quick-reference workflow (PID-targeted, CLI-only)

A concise end-to-end flow using only the verbs above — no UI automation needed:

1. `list-instances`, verify the intended `<VS pid>`, then
   `attach-process --pid <debuggee pid> --instancePid <VS pid>` only if attachment is needed.
2. `break-all --pid <debuggee pid> --instancePid <VS pid>` to stop immediately, or set
   breakpoints and use `wait-for-break --timeoutSeconds 60 --instancePid <VS pid>`.
3. `list-threads`, `select-thread --threadId <n>`, then `select-frame --index <n>`;
   append the same `--instancePid <VS pid>` to each command.
4. Inspect with `debugger-status --context true`, `get-callstack`, `get-locals`, or
   `evaluate --expression <text>`, again targeting that VS PID on every call. Add
   `--allowSideEffects true` only when explicitly authorized to invoke/mutate.
5. `continue` / `step-over`/`step-into`/`step-out`, or `detach --pid <debuggee pid>` to release
   the debugger without stopping the process; keep the same explicit VS target.

## Typical composition with ui-interaction

A common flow when the goal is "tell me what code runs when I do X in the app" (i.e. the trigger
itself is a UI action, not something you can stop/attach to directly):

1. Verify the VS PID using `list-instances`, then `debugger-status --instancePid <VS pid>`;
   attach only if needed. Carry this target on every debugger command below.
2. `set-breakpoint --file <absolute path> --line <n>` at a plausible handler (from a code search,
   or from a coarse class-name anchor another skill already has).
3. Call into **ui-interaction** to actually perform the UI action (click/type) that should
   trigger that code path.
4. `wait-for-break --timeoutSeconds 60 --instancePid <VS pid>`, then targeted
   `debugger-status --context true` and `get-callstack` to inspect the observed break.
5. `detach --pid <n>` (or keep stepping, if the caller wants deeper investigation).

This skill never performs the UI-triggering step itself — that's `ui-interaction`'s job, kept
separate so this skill stays usable for debugging scenarios that don't involve UI interaction at
all (e.g. attaching to something already running and investigating a crash).

## What this skill never does

- Never persists a map, cache, or notes file of what it finds — that's up to the caller.
- Never decides where to look first; a caller supplies the breakpoint location (whether from a
  navigation tree's `[ClassName]` breadcrumb, a fresh code search, or direct instruction).
- Never opts into `ExecuteStatement` without explicit permission to invoke or mutate something
  on the debuggee. Do not enable `--allowSideEffects true` as a fallback after evaluation fails.
  The default `GetExpression` route still depends on the debugger's implicit-evaluation settings;
  do not describe it as a sandbox that prevents all getter or function execution.
