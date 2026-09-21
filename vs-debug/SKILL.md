---
name: vs-debug
description: 'Attach the Visual Studio debugger to a running application via AgentDebugToolkit''s agentdebug-vs.exe (EnvDTE COM): set breakpoints, step, read call stacks, and resolve which source file/line/handler ran for a given action. Independently useful for any debugging task, not only ones reached via UI navigation. May call the ui-interaction skill to trigger an app UI action while attached, in order to hit a breakpoint. Does not build or maintain any persistent map of an application — see ui-navigation-orchestrator for that.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 2`. Compare against the source-of-truth copy at
  `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\vs-debug\SKILL.md` once at the start of a session.
- Changelog:
  - v1 — initial version. Extracted from `ui-debug-map`, which mixed this debugger-bridge
    mechanism together with map schema/policy; this skill now holds just the debugging mechanism,
    usable on its own regardless of whether any navigation map exists or is ever built.
  - v2 -- added an explicit "Step 0: Version Check" step (run once per session, never per
    attach/breakpoint/step/read-call-stack call), matching agent-orchestrator's pattern.

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
- **set-breakpoint / clear-breakpoint** — by file/line, or by method signature where supported.
- **wait-for-break** — poll asynchronously for a breakpoint to be hit; relay progress rather than
  blocking silently, same pattern as `ui-interaction`'s `wait`.
- **step** — into / over / out.
- **read-call-stack** — returns the current call stack once broken.
- **detach** — release the debugger without stopping the target process, when the caller just
  wanted a resolved location, not a live debugging session.

## Typical composition with ui-interaction

A common flow when the goal is "tell me what code runs when I do X in the app":

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
