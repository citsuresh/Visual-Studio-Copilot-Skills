---
name: ui-interaction
description: 'Generic Windows UI automation primitives via AgentDebugToolkit''s agentdebug-ui.exe: click, inspect/read, wait/poll, handle native dialogs and tricky controls, selector strategy with fallback. A pure mechanism skill — it drives and reads a UI but never decides whether an action succeeded or means what the caller intended; that judgment belongs to whichever skill or agent calls it (e.g. ui-navigation-orchestrator, agent-orchestrator). Use whenever a task needs to click, type into, or read the state of a Windows desktop UI, for any target application.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 2`. Compare this file's version against the source-of-truth copy at
  `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\ui-interaction\SKILL.md` once at the start of a
  session, the same way `agent-orchestrator` does — only one installed copy, one source of truth,
  no per-project marker needed.
- Changelog:
  - v1 — initial version. Extracted from `ui-debug-map` and `agent-orchestrator`, which both
    reimplemented slices of this same mechanism; this skill now holds the shared, reusable layer
    so future toolkit-level fixes/quirks only need updating in one place.
  - v2 -- added an explicit "Step 0: Version Check" step (run once per session, never per
    click/inspect/wait call) -- previously only the passive version metadata existed here,
    without agent-orchestrator's matching procedural caution against re-checking per call,
    which matters most for this skill since it's invoked far more often than the others.

# UI Interaction

Drive and read a Windows desktop UI via `agentdebug-ui.exe`. This skill only performs and
observes actions — it has no opinion about *why* you're clicking something or whether the result
is *correct* for your task. If deciding what a click or a piece of read-back text means requires
knowing the caller's intent (e.g. "is this the ChoicePrompt card I expected," "did the map
navigate where I meant it to"), that judgment stays with the caller. This skill only ever answers
"perform this action" or "tell me what's there right now."

## Prerequisites / environment

- **Portability note:** this skill assumes `C:\MyFiles\Git\AgentDebugToolkit` is a specific,
  hardcoded local clone of the AgentDebugToolkit repo on this machine. If that folder doesn't
  exist (different machine, fresh environment, moved/removed clone), stop and ask the user where
  to find or clone it — never guess a path or silently fall back to a different one.
- Tool: `agentdebug-ui.exe`, built from
  `C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli`. Build with
  `dotnet build` if the compiled exe isn't present (clear `DOTNET_ROOT` first, see below).
- **CRITICAL environment gotcha:** always run
  `Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue` before invoking `agentdebug-ui.exe`
  or `dotnet build`/`restore` in a fresh PowerShell process — VS's inherited `DOTNET_ROOT` breaks
  both.
- Full verb contract: `C:\MyFiles\Git\AgentDebugToolkit\docs\CLI_CONTRACT.md`. Read this if a verb
  behaves unexpectedly — do not guess at flags.
- **Screenshot cleanup is the caller's responsibility.** `inspect --screenshot true` saves to
  `%LOCALAPPDATA%\AgentDebugToolkit\screenshots\` and does not delete the file automatically.

## Step 0: Version Check

Run this **once**, the first time this skill's primitives are about to be used in a session —
not on every individual click/inspect/wait/type call. If another skill composing this one
(`ui-navigation-orchestrator`, `agent-orchestrator`) already ran its own Step 0 this session,
still check this skill's own version once (they version independently), but never repeat the
check per call — this skill is invoked far more often than the others, so re-checking per call
would defeat the point of it being a cheap, once-per-session check.

1. Read `CURRENT_SKILL_VERSION` from the repo copy at
   `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\ui-interaction\SKILL.md`. Use the same "ask,
   don't guess" fallback as the `AgentDebugToolkit` path above if this repo path doesn't exist on
   the current machine.
2. Compare that repo version to this file's own `CURRENT_SKILL_VERSION`.
3. If the repo's version is higher: tell the user plainly what changed (the changelog entries
   between the running version and the repo's version) and that the installed copy is stale.
   Recommend running `Install-Skills.ps1`, but let the user decide whether to update now or
   proceed with the current session.
4. If versions match: proceed silently.

## Core primitives

- **list-windows / attach** — find and scope to a target window, by hwnd, pid, or title. Matching
  by title alone when multiple windows share it is ambiguous — prefer `--pid` or an explicit hwnd
  when the caller can supply one, and flag the ambiguity rather than silently picking one if it
  can't.
- **click** — by selector. Prefer `Name`-based selectors with a documented fallback strategy over
  `AutomationId` where the caller's target app is known to expose unreliable `AutomationId`s (that
  finding belongs to the caller/target app's own notes, not generalized here, since it isn't true
  of every app).
- **inspect / read** — returns the current element tree, text, and state. This is the primitive
  that answers "what's on screen right now" — always fresh, never cached by this skill.
- **type / paste** — prefer clipboard-paste over synthetic typing for reliability; avoid literal
  newlines in directly-typed text (rejected by design in some verbs).
- **wait / poll** — for a UI state to settle, invoked asynchronously so a caller can relay
  progress without blocking.
- **set-grid-cell** — for virtualized WPF DataGrid controls (see gotcha below).

## Known generic UI-automation gotchas

Add to this list whenever a *toolkit- or control-family-level* quirk is discovered by any
consumer of this skill — not an app-specific fact (those belong in that app's own notes, e.g. in
`ui-navigation-orchestrator`'s target-repo tree file).

- **Native dialogs** enumerate as their own top-level window (`ClassName: "#32770"`), with
  `OwnerHwnd`/`IsModal`/`IsForeground`. If a click that should trigger a dialog appears to have no
  effect, re-run `list-windows`/`attach` and check for a new `#32770` entry before concluding the
  underlying feature is broken.
- **Virtualized WPF DataGrid controls** — use the `set-grid-cell` verb; some grids need an
  explicit `--applyStrategy`/`--applyValue` to commit the edit.
- **Hover-driven pickers** — some pickers only detect a target after the OS cursor has physically
  entered the window; a raw click at a coordinate isn't sufficient on its own.
- *(Resolved, kept for reference of the format above)* the toolkit's `send-keys` verb used to
  auto-focus an element with a click before sending keys, which broke reliable arrow-key
  navigation on custom listbox controls exposing zero UIA children. Fixed upstream in
  `AgentDebugToolkit`; no workaround needed anymore.

## What this skill never does

- Never decides whether an action's outcome matches what the caller intended. A `success: true`
  response is not proof the right thing happened — always re-`inspect` and hand the fresh state
  back to the caller; the caller compares it against its own expectation.
- Never persists anything about a target application (no map, no cache, no notes file) — that's
  the caller's job, if it wants one.
