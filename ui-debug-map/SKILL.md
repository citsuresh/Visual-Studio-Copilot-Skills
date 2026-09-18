---
name: ui-debug-map
description: 'Interactively debug a WinForms/WPF application via UIA (AgentDebugToolkit''s agentdebug-ui.exe) and the Visual Studio debugger bridge (agentdebug-vs.exe), building a persistent UI-element-to-source-code map in the TARGET application''s own repo as you navigate. Use for: "navigate to feature X", "debug this screen", or building/updating a navigation map so future navigation to a known feature can jump straight there instead of re-exploring. The map is stored per-target-repo (e.g. docs/ui-debug-map.json in that app''s repo), never in this skill''s own folder or a global location, since each project has its own distinct UI.'
---

# UI Debug Map

Build and use a persistent map from **UI elements/features of a target application** to the
**source code that implements them**, by combining live UI automation (clicking through the
running app) with live debugger correlation (breakpoints + call stacks), so that once a feature
has been visited once, future requests to "navigate to X" or "debug X" can jump directly to the
known code location instead of re-exploring from scratch.

## Where the map lives (important)

**The map is data about a specific target application, not about this skill.** It must be stored
in that target application's own repository, never inside this skill's folder or any global
location — different projects have entirely different UIs and the map is meaningless outside its
own app's context.

- Default location: `<target-repo-root>/docs/ui-debug-map.json` (create `docs/` if it doesn't
  exist). If the target repo already has a `docs/` convention for project memory (e.g.
  `CODE_SUMMARY.md`, `PROJECT_STATE.md`), place it alongside those.
- Before writing, confirm the resolved absolute path with the user if it's not obvious (e.g.
  multi-solution repos, nested project layouts) — same discipline as the project-memory skills.
- Do not create a second copy of the map elsewhere "for convenience." One authoritative file per
  target repo.
- **Growth note:** the map currently stays a single flat JSON file by design. If it grows very
  large (many workflows/features explored, file becomes unwieldy to read/diff), revisit this and
  consider breaking it down (e.g. an index file plus one shard file per workflow/area) — but treat
  that as a deliberate future decision to make with the user when the need actually arises, not
  something to do preemptively.
- **Trial dual-format mode (current, temporary — OpenWayCOSEM.PC repo):** the user has asked to
  maintain BOTH representations in parallel for now, to compare and decide later which to keep:
  1. The single flat file — named `docs/ui-debug-map-full.json` in the OpenWayCOSEM.PC repo (the
     `-full` suffix distinguishes it from the broken-down mirror below; other repos may just use
     the default `docs/ui-debug-map.json` name), same schema as above — the canonical/complete
     record.
  2. A broken-down mirror, structured as:
     ```
     docs/ui-debug-map/
       index.json                                <- app, generatedBy, startupNotes, list of endpoint types
       <EndpointType>/
         index.json                               <- endpoint-specific notes, list of workflow subfolders
         <WorkflowPath>/
           map.json                                <- features[] scoped to just this workflow path (same
                                                        per-feature schema as the flat file)
           <NestedWorkflowPath>/
             map.json                              <- further nesting mirrors the app's own menu nesting
     ```
     `<EndpointType>` is a directory-safe version of the endpoint type name (e.g.
     `Gen5RivaElectricity`). `<WorkflowPath>` segments are directory-safe versions of each menu
     level's UI name, with any numeric prefix stripped (e.g. the menu item "01. Device Control
     Panel" becomes folder `DeviceControlPanel`; a sub-item inside it like "1. Operational Status"
     becomes `OperationalStatus` nested underneath). Nest one folder level per level of menu
     nesting actually observed in the app — do not pre-guess a fixed depth; only create folders
     for levels that exist.
  - Both representations must be updated together, from the same in-memory finding, every time a
    feature is recorded — write once to the flat file's `features[]`, and once to the matching
    workflow's `map.json`. They are not independent sources of truth; treat any divergence between
    them as a bug to fix immediately, not as something to reconcile later.
  - This is temporary scaffolding for an explicit side-by-side comparison the user requested, not
    a permanent dual-maintenance requirement. Once the user decides which format to keep, update
    this section (and remove references to the discarded format) — do not leave both indefinitely
    without an explicit decision recorded here.
  - Restructuring between the two representations (e.g. splitting a large flat file into shards,
    or splitting an existing workflow's `map.json` further into per-sub-feature files) is a pure
    file-reorganization task once features are already recorded — the recorded data (uiPath,
    selectors, source, call stacks) is simply repartitioned across files/folders. It never requires
    re-running the live UI/debugger exploration in Workflow A; only stale/incorrect *data* (not its
    file layout) requires re-exploration.

## Map schema (JSON)

```json
{
  "app": "Itron.Fdm.Mobile.SystemWorkflows.OpenWayCOSEM.PC",
  "generatedBy": "ui-debug-map skill",
  "lastUpdated": "2026-09-15T19:25:00+05:30",
  "features": [
    {
      "name": "COSEM Connection Page - Save Workflow",
      "uiPath": ["MainForm", "TabControl:Workflows", "COSEMConnectionPage"],
      "selector": { "strategy": "Name", "value": "Save" },
      "selectorFallback": { "strategy": "ControlTypeIndex", "value": "Button:3" },
      "sourceFile": "src/.../COSEMConnectionPage.cs",
      "sourceLine": 176,
      "handlerMethod": "SaveWorkflowData",
      "callStackSample": ["SaveWorkflowData", "..." , "Main"],
      "deviceVariant": "both",
      "notes": "AutomationId unreliable for this control family; Name selector confirmed unique.",
      "lastVerified": "2026-09-15"
    }
  ]
}
```
Keep entries minimal but sufficient to re-navigate without re-deriving from scratch. Prefer
`Name`-based selectors as primary since `AutomationId` is documented as unreliable for the FDM
WinForms app family (`AgentDebugToolkit/docs/CLI_CONTRACT.md`); record a fallback selector when
the primary one is fragile.

- **`deviceVariant` field:** many meter definitions (MDF XML files, e.g.
  `Meter Definitions/Gen5 Riva.xml`) declare multiple `SupportedDevice`/`ConfigGroup` combinations
  under one endpoint type — distinguished by `DeviceType` (e.g. `Gen5Riva` = single-phase,
  `Gen5RivaPoly` = polyphase) and a capabilities file (e.g.
  `MeterCapabilities-NAM-SinglePhase.xml` vs `...Polyphase.xml`). A single workflow can show
  different features/pages depending on which device variant is actually connected. Record this
  per feature as `"deviceVariant"`, using whatever value is concretely knowable at the time (e.g.
  `"SP"`, `"PP"`, `"both"`, or a more specific `DeviceType`/`ModelType` string) — do not guess it
  from the UI alone. This is usually NOT determinable just by walking the UI; either read it off a
  device info/status screen in the app if one displays model/serial/type, or ask the user (they
  typically know which physical/simulated device variant they're connected to). If truly unknown
  at recording time, omit the field rather than guessing, and leave a note.

## Map is a living document — not a read-only reference

Treat "exploring the app" and "maintaining the map" as the same activity, not two separate modes
that need separate permission each time:

- Whenever driving the app's UI for any purpose (explicit mapping request, navigating to a known
  feature per Workflow B, or just checking behavior along the way), if a workflow/screen/menu path
  is encountered that has no corresponding folder/entry yet, create the missing
  folder(s)/`map.json` and record it — don't leave it unmapped just because the current task wasn't
  explicitly "map this."
- Likewise, if new UI elements appear on an already-mapped screen (e.g. a button that wasn't there
  before, or a variant-specific control appears because a different device is connected), add
  them to the existing entry/file rather than treating the page as already fully mapped and done.
- This still respects the same-session discipline elsewhere in this skill (e.g. clean up
  breakpoints before moving on) — "living document" means the map keeps growing/self-correcting
  through normal use, not that verification/cleanup steps get skipped.

## Prerequisites

- **Portability note:** this skill assumes `C:\MyFiles\Git\AgentDebugToolkit` is a specific,
  hardcoded local clone of the AgentDebugToolkit repo on this machine — it is not a portable
  path. If that folder doesn't exist at all (e.g. a different machine, a fresh environment, or
  the clone was moved/removed), stop and ask the user where they'd like to check it out (do not
  guess a path or silently fall back to a different one). The repo's remote is
  `https://github.com/citsuresh/AgentDebugToolkit.git` — if the user confirms they don't have a
  local clone yet, offer to `git clone` it to a location of their choosing, then proceed using
  that path for the remainder of the session.
- `agentdebug-ui.exe` (UIA driver) and `agentdebug-vs.exe` (VS debugger bridge), both from
  `C:\MyFiles\Git\AgentDebugToolkit`. Clear `DOTNET_ROOT` before invoking either
  (`Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue`). If either `.exe` doesn't exist at
  its default build output path, build it first (`dotnet build` in that project folder, or
  `dotnet build AgentDebugToolkit.slnx` for the whole solution).
- `agentdebug-vs` supports: `debugger-status`, `get-callstack`, `get-locals`,
  `get-exception-info`, `continue`, `step-over`/`step-into`/`step-out`, `start-debugging`,
  `stop-debugging`, plus (Phase 20, implemented) `set-breakpoint --file <path> --line <n>`,
  `remove-breakpoint --file <path> --line <n>` / `--all`, `list-breakpoints`, and
  `wait-for-break --timeoutMs <n> [--pollMs <n>]`. Breakpoint placement/waiting is now fully
  automatable — no manual VS UI step is required for the core click-to-breakpoint-hit loop.
- Full verb contracts: `AgentDebugToolkit/docs/CLI_CONTRACT.md` (UIA CLI, Phase 1-9 + 13 + 22;
  debugger bridge Phase 6 + 20, including the "Attaching to Visual Studio" / "Verbs" sections).
- **Screenshot cleanup is the caller's responsibility.** `inspect --screenshot true` (and any other
  verb that writes a screenshot file, e.g. `screenshot`) saves to
  `%LOCALAPPDATA%\AgentDebugToolkit\screenshots\` and returns the path in `screenshotPath` — the
  CLI does NOT delete these automatically, and they accumulate indefinitely across sessions. After
  viewing a screenshot (or a batch of them) and finishing the verification step it was needed for,
  delete the file(s) you created this session (e.g. `Remove-Item <screenshotPath>` or a glob over
  the session's timestamp range) — don't leave them for a future session to clean up.

## Workflow A — Explore/build the map (given a known code area)

Use when you already know the target code (e.g. user asks "show me the workflow save feature") and
want to locate/confirm its UI counterpart, recording the mapping:

1. Identify the source method/class of interest (use the code knowledge graph if this repo has
   one — see `project-memory-management-graph` skill — otherwise grep/search normally).
2. `set-breakpoint --file <path> --line <n>` at the relevant line via `agentdebug-vs`. Verify the
   response's `file`/`line` reflect what VS actually created (it may adjust/reject the request),
   not just what was requested.
3. Start/attach the debug session (`start-debugging`, or confirm already running via
   `debugger-status`).
4. Drive the UI (`agentdebug-ui`) to the screen/control believed to trigger that code path:
   `attach`/`list-windows` to find the app's window, `inspect --maxDepth <n>` to find candidate
   controls, `click` to interact.
5. `wait-for-break --timeoutMs <n>` instead of manually polling — it blocks until break mode is
   entered (or times out), then confirm/inspect via `get-callstack`/`get-locals`.
6. Record the feature: UI path, selector (+ fallback if `AutomationId` is unreliable for that
   control), source file/line, handler method, and a `lastVerified` date. If the repo is in
   "trial dual-format mode" (see above), write this to BOTH the flat file's (e.g.
   `docs/ui-debug-map-full.json`, or `docs/ui-debug-map.json` if the repo hasn't renamed it)
   `features[]` and the matching `docs/ui-debug-map/<EndpointType>/<WorkflowPath>/map.json` in the
   same step — otherwise write to whichever single format the repo has settled on.
7. `remove-breakpoint --file <path> --line <n>` (or `--all` if appropriate) to clean up, then
   `continue` or `stop-debugging` to release the session when done — don't leave stray
   breakpoints behind across sessions.

## Workflow B — Navigate to a known feature (map already built)

Use when the user asks to "navigate to X" / "debug X" and an entry already exists in the map
(the flat file — `docs/ui-debug-map-full.json` in this repo — and/or the broken-down mirror):

1. Load the map, find the matching feature entry.
2. Re-verify the app is running (`list-windows`); if not, offer to `start-debugging`/launch it.
3. Drive the UI directly via the stored `selector` (try `selectorFallback` if the primary fails —
   this is expected occasionally since UI layouts drift over time; update the map if a selector no
   longer resolves).
4. If debugging (not just navigating), `set-breakpoint` at the stored `sourceFile`/`sourceLine`,
   then `wait-for-break --timeoutMs <n>` to confirm the hit instead of manually polling
   `debugger-status`.
5. If the actual behavior/call stack diverges from what's recorded, update the map entry
   (`lastVerified`, corrected selector/line) rather than leaving stale data. If in trial
   dual-format mode, apply the same correction to both representations.
6. `remove-breakpoint` (or `--all`) to clean up before ending the session.

## Known constraints (be upfront with the user about these)

- **WinForms selector reliability** — `AutomationId` is documented as unreliable for the FDM app
  family; prefer `Name`, and record a fallback strategy per entry. Expect some controls to have no
  usable Name either; note these as "requires manual identification" in the map rather than
  guessing with `Coordinates` (not implemented — rejected with `invalid-argument` by design).
- **One map per target repo** — do not conflate maps across different applications/repos.
- Treat this skill as a companion to `agent-orchestrator` (same underlying `agentdebug-ui.exe`
  primitives), not a replacement — reuse its polling/verification discipline where applicable
  (e.g. independently confirming state via `debugger-status`/`inspect` rather than trusting stale
  chat-transcript-style assumptions). In particular, reuse `agent-orchestrator`'s known gotcha:
  a `click`'s `"success":true` response is not sufficient proof the intended element/option was
  actually resolved/selected (it can silently resolve to the wrong element) — re-inspect to
  confirm, especially before treating a UI action as having triggered the expected code path.
- **Native confirmation/message-box dialogs** — as of AgentDebugToolkit commit `c5db97a` ("Fix
  owned native dialog enumeration"), `list-windows`/`attach` enumerate owned native dialogs (e.g.
  a WPF `MessageBox.Show(...)` window, `ClassName: "#32770"`) alongside the app's normal windows,
  returned with their own `Hwnd`, `OwnerHwnd`, and `IsModal`/`IsForeground` flags. Interact with
  them exactly like any other window using that returned `Hwnd` (e.g.
  `click --hwnd <dialog-hwnd> --strategy Name --value Yes`). If a `click` on a button that should
  trigger a confirmation appears to have no effect (target window looks unchanged, action seems to
  not have happened), re-run `list-windows`/`attach` first and check for a new `#32770`-classed
  entry before concluding the underlying feature/code is broken — this exact confusion caused a
  false "write doesn't work" diagnosis in the WindowWorks Property Inspector before the toolkit fix
  landed. If working against an AgentDebugToolkit build older than `c5db97a`, this enumeration gap
  still applies — verify existence of the dialog via a raw Win32 `EnumWindows` check before assuming
  the underlying app is broken.
- **Virtualized WPF DataGrid controls** — use `set-grid-cell` instead of saved row coordinates when
  a grid exposes UIA `GridPattern`/`ScrollPattern`. Locate the grid with `--gridStrategy`/
  `--gridValue`, locate a stable descendant in the desired row with `--rowStrategy`/`--rowValue`,
  and pass the value-cell's `GridItemPattern` column as `--columnIndex`. The verb scrolls and
  re-queries realized rows, then resolves the in-cell editor (default `Edit`) before writing.
  Include `--applyStrategy`/`--applyValue` only for grids that require an explicit action inside
  the edited cell to commit (for example, an Apply/OK button); omit them when the grid commits on
  focus loss, Enter, or its own editor behavior. For the WindowWorks Property Inspector:
  `set-grid-cell --hwnd <inspector-hwnd> --gridStrategy AutomationId --gridValue PropertyDataGrid
  --rowStrategy Name --rowValue style.display --columnIndex 1 --text block --applyStrategy Name
  --applyValue Apply`. Do not use an `inspect` bounding rectangle captured from an earlier call to
  target a virtualized grid row.
- **Hover-driven pickers** — some application pickers discover the target only after the OS cursor
  physically enters their window. Before inspecting or clicking one, activate the target window and
  move the cursor into it with the toolkit; this is application behavior, not a selector failure.
