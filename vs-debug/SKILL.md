---
name: vs-debug
description: 'Attach the Visual Studio debugger to a running application via AgentDebugToolkit''s agentdebug-vs.exe (EnvDTE COM): set breakpoints, step, read call stacks, and resolve which source file/line/handler ran for a given action. Independently useful for any debugging task, not only ones reached via UI navigation. May call the ui-interaction skill to trigger an app UI action while attached, in order to hit a breakpoint. Does not build or maintain any persistent map of an application — see ui-navigation-orchestrator for that.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 5`. Compare against the source-of-truth copy at
  `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\vs-debug\SKILL.md` once at the start of a session.
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

# VS Debug

Drive Visual Studio's debugger against a running application via `agentdebug-vs.exe`, and resolve
runtime behavior down to exact source. This skill is a pure mechanism, like `ui-interaction`: it
attaches, breaks, steps, and reads — it has no opinion about *why* you're debugging something and
does not persist anything about what it finds. A caller (e.g. `ui-navigation-orchestrator`, or a
person debugging directly) decides what the resolved source location means and whether to keep a
record of it.

## Prerequisites / environment

- **Portability note:** same as `ui-interaction` — this skill assumes
  `C:\MyFiles\Git\AgentDebugToolkit` is a specific, hardcoded local clone. If it doesn't exist,
  stop and ask the user where to find or clone it rather than guessing.
- Tool: `agentdebug-vs.exe`, built from
  `C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.Debugger.VisualStudio`. This is a
  separate CLI/process from `agentdebug-ui.exe` — it drives Visual Studio's debugger via EnvDTE
  COM, not the UI via UIA.
- **CRITICAL environment gotcha:** clear `DOTNET_ROOT`
  (`Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue`) before invoking `agentdebug-vs.exe`
  or `dotnet build`/`restore`, same as `ui-interaction`.
- Full verb contract: `C:\MyFiles\Git\AgentDebugToolkit\docs\CLI_CONTRACT.md`.
- **UI automation is a fallback, not a default.** As of Phase 21/22, `agentdebug-vs.exe` itself
  covers PID-targeted attach/break/detach, reliable state reporting, and thread/frame/locals/
  evaluate inspection entirely via EnvDTE/COM — no UI automation/SendKeys involved. Only reach for
  `ui-interaction` when the goal genuinely requires *driving the app's own UI* (e.g. clicking a
  button to trigger the code path you want to hit) or for something this skill's verbs don't
  cover at all. Do not use `ui-interaction` to drive Visual Studio's own debugger UI (breakpoint
  margin clicks, Locals window, etc.) — every one of those is now a direct, reliable verb here.

## Step 0: Version Check

Run this **once**, the first time this skill is used in a session — not on every individual
attach/breakpoint/step/read-call-stack call.

1. Read `CURRENT_SKILL_VERSION` from the repo copy at
   `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\vs-debug\SKILL.md`. Use the same "ask, don't
   guess" fallback as the `AgentDebugToolkit` path above if this repo path doesn't exist.
2. Compare that repo version to this file's own `CURRENT_SKILL_VERSION`.
3. If the repo's version is higher: tell the user plainly what changed and that the installed
   copy is stale. Recommend running `Install-Skills.ps1`, but let the user decide whether to
   update now or proceed with the current session.
4. If versions match: proceed silently.

## Core operations

- **attach** — to a running process, or the process VS is already debugging.
- **attach-process `--pid <n>`** — attach by explicit PID rather than by name/already-debugging
  process. Resolution is unambiguous by construction (every running `devenv.exe`, or just the one
  matching `--solution`, is scanned for that PID in its `LocalProcesses`). Returns
  `{ pid, mode }`. Fails with `process-not-found` if no instance sees that PID, or
  `ambiguous-process` (with a `candidates` list of `{instance, solution}`) if more than one
  running Visual Studio instance can see it — retry with `--solution` to disambiguate rather than
  guessing which one.
- **set-breakpoint / clear-breakpoint** — by file/line, or by method signature where supported.
- **break-all `--pid <n>`** — breaks *every* thread in the target debuggee process (not just the
  current thread), resolved via the instance's `DebuggedProcesses` (processes under an active
  debug session — distinct from `LocalProcesses`, which is every attachable process whether or
  not it's being debugged). Same `process-not-debugged`/`ambiguous-process` failure shape as
  `attach-process`. Use this instead of waiting on a breakpoint when you need to stop the process
  *right now*, regardless of where it currently is.
- **wait-for-break** — poll asynchronously for a breakpoint to be hit; relay progress rather than
  blocking silently, same pattern as `ui-interaction`'s `wait`.
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
- **step** — into / over / out.
- **read-call-stack** — returns the current call stack once broken.
- **read-locals** (`get-locals`) — local variables for the current (innermost, or selected-frame)
  stack frame as EnvDTE string representations, not typed/structured values.
- **evaluate `--expression <text> [--allowSideEffects]`** — evaluate an expression against the
  currently selected frame (or EnvDTE's own current frame if none was explicitly selected).
  - **Safe by default**: reads the expression (`GetExpression`, no statement execution, no
    assignments) — same non-mutating path `get-locals` already uses. Returns
    `{ name, value, type }`. If the expression parses but can't actually be evaluated, this is a
    real failure outcome (`evaluation-failed`, with `name`/`type` still populated) — not something
    to blindly retry; it means the expression itself is invalid in this context (e.g. an
    out-of-scope variable), not a transient error.
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
- **`ambiguous-process` always includes a `candidates` list** — use it to retry with `--solution`
  rather than guessing or picking the first candidate blindly.

## Quick-reference workflow (PID-targeted, CLI-only)

A concise end-to-end flow using only the verbs above — no UI automation needed:

1. `attach-process --pid <n>` (resolve `--solution` first if `ambiguous-process` comes back).
2. `break-all --pid <n>` (to stop immediately) — or set breakpoints and `wait-for-break` if you
   want to stop at a specific location instead.
3. `list-threads` → `select-thread --threadId <n>` → `select-frame --index <n>`.
4. Inspect: `read-locals` for a quick dump, or `evaluate --expression <text>` for something
   specific (add `--allowSideEffects true` only if you deliberately need to invoke/mutate).
5. `continue` / `step-over`/`step-into`/`step-out` to keep going, or `detach --pid <n>` to release
   the debugger while leaving the process running.

## Typical composition with ui-interaction

A common flow when the goal is "tell me what code runs when I do X in the app" (i.e. the trigger
itself is a UI action, not something you can stop/attach to directly):

1. `attach` to the running target application.
2. `set-breakpoint` at a plausible handler (from a code search, or from a coarse class-name
   anchor another skill already has).
3. Call into **ui-interaction** to actually perform the UI action (click/type) that should
   trigger that code path.
4. `wait-for-break`, then `read-call-stack` to confirm exactly what ran.
5. `detach` (or keep stepping, if the caller wants deeper investigation).

This skill never performs the UI-triggering step itself — that's `ui-interaction`'s job, kept
separate so this skill stays usable for debugging scenarios that don't involve UI interaction at
all (e.g. attaching to something already running and investigating a crash).

## What this skill never does

- Never persists a map, cache, or notes file of what it finds — that's up to the caller.
- Never decides where to look first; a caller supplies the breakpoint location (whether from a
  navigation tree's `[ClassName]` breadcrumb, a fresh code search, or direct instruction).
- Never executes statements, property getters, method calls, or assignments against the live
  debuggee by default. `evaluate` only reads an expression's current value unless the caller
  explicitly passes `--allowSideEffects true` — this is a deliberate safety default, not an
  oversight, and it is this skill's responsibility to never flip that flag on its own (e.g. as a
  fallback after a safe-mode evaluation fails). Only pass it when the caller has explicitly asked
  to mutate or invoke something on the debuggee.
