---
name: ui-interaction
description: 'Generic Windows UI automation primitives via AgentDebugToolkit''s agentdebug-ui.exe: click, inspect/read, wait/poll, handle native dialogs and tricky controls, selector strategy with fallback. A pure mechanism skill — it drives and reads a UI but never decides whether an action succeeded or means what the caller intended; that judgment belongs to whichever skill or agent calls it (e.g. ui-navigation-orchestrator, agent-orchestrator). Use whenever a task needs to click, type into, or read the state of a Windows desktop UI, for any target application.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 4`. Compare this file's version against the source-of-truth copy at
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
  - v3 — Clarifies that potentially ambiguous click selectors should be scoped, that selector
    uniqueness and the resolved control type/class must be checked rather than inferred from
    `success: true`, and that all typed input requires an explicit read-back before it is called
    verified (including line-ending normalization when comparing text). Adds a known gap for
    actions that open windows owned by a different process: callers must identify a plausible
    process to inspect rather than guessing, since cross-process window enumeration is not yet
    available.
  - v4 — Documents the 2026-10-14 toolkit change that rejects ambiguous selector matches without
    acting, returns candidate details for narrowing, and adds `--scopeHwnd` to `get-text`;
    older builds still silently use the first match. Adds compact-first `inspect` guidance
    using name/control-type filters and their pruned-tree output, and records scroll-to-element
    as another known gap.

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
  of every app). When a selector could plausibly match more than one element (e.g. shared labels,
  or a name that also matches a system element such as a browser bookmark), scope it with
  `--scopeHwnd` (the only scoping flag `click`/`type` accept). `click`, `right-click`, `double-click`,
  `drag`, selector-form `move-mouse`, `type`, `get-text`, and `send-keys` now fail with
  `ambiguous-match` instead of acting on the first match. The response includes `count` and up to
  10 candidates (`name`, `automationId`, `controlType`, `className`), and no action is performed.
  On `ambiguous-match`, narrow with `--scopeHwnd`, or retry using a candidate's `AutomationId` if
  it is unique. This behavior requires an `agentdebug-ui.exe` built from the 2026-10-14 change;
  an older build silently uses the first match. `get-text` now also accepts `--scopeHwnd`.
  If selector uniqueness is uncertain, use `find-all` first (see
  `CLI_CONTRACT.md`) to confirm the match count before acting. Its own
  `--scopeStrategy`/`--scopeValue` flags can narrow that pre-check, but they are not accepted by
  `click`/`type` themselves. A selector matching a label does not prove that it
  targets the intended control — confirm the matched element's `controlType`/`className` in the
  response, not just that `success: true` was returned.
- **inspect / read** — returns the current element tree, text, and state. This is the primitive
  that answers "what's on screen right now" — always fresh, never cached by this skill.
  Use compact-first inspection: try `inspect --nameContains <text>` (case-insensitive) and/or
  `--controlType <short name>` (e.g. `Button`, `Edit`) first. Filtered output is a pruned tree:
  matches plus their ancestor chain, with a `matchCount` field. An unknown control type returns
  `invalid-argument`. Reserve unfiltered `inspect` and screenshots for cases the filters cannot
  resolve. If the window's own name matches `--nameContains`, the whole tree is retained, so use
  a more specific substring or add `--controlType`.
- **type / paste** — prefer clipboard-paste over synthetic typing for reliability; avoid literal
  newlines in directly-typed text (rejected by design in some verbs).
- **wait / poll** — for a UI state to settle, invoked asynchronously so a caller can relay
  progress without blocking.
- **set-grid-cell** — for virtualized WPF DataGrid controls (see gotcha below).

### Verifying typed input

- After every `type` or `submit-chat-message` call, perform an explicit read-back before treating
  text entry as confirmed. `success: true` or a passed `--verify` is not sufficient on its own:
  per `CLI_CONTRACT.md`'s `type` verb, `--verify` is silently skipped on the synthetic-keyboard
  path and, on the clipboard-paste path, only checks the immediate/bounded stability window
  described by the `verify-unstable` mitigation.
- "Action succeeded" (the verb returned `success: true`) and "content verified" (a read-back
  confirms the actual on-screen text matches intent) are different claims. Only make the second
  claim after an explicit read-back, even when `--verify` passed.
- Before concluding expected and actual text genuinely differ, normalize line endings on both
  sides (`\r\n` and lone `\r` to `\n`). Windows edit controls have been observed reading embedded
  newlines back as `\r`, not `\n`.
- For the read-back, use `get-text` on controls with a usable `ValuePattern`. On controls without
  one (e.g. the Copilot chat input), `get-text` falls back to the element's accessibility `Name`,
  which is a label rather than the typed content, so use `read-visible-text` or a narrowly scoped
  `inspect` instead.

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
- **New windows owned by another process** — after an action expected to open a new window, if
  the result is not visible via `wait-for-window-change`/`list-windows` scoped to the original
  process, the new window may belong to a different process entirely (e.g. a "Report a Problem"
  action opening a browser instead of a dialog in the host app). `list-windows` currently requires
  a `--pid` or context pid; there is no cross-process window-enumeration primitive yet. The caller
  must attach to a plausibly involved process by name to check, or ask the calling skill/agent
  which process to check. This is a known gap, not something to work around silently by guessing.
- **Scroll-to-element** is also a known gap.
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
