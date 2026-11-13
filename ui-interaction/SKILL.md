---
name: ui-interaction
description: 'Generic Windows UI automation primitives via AgentDebugToolkit''s agentdebug-ui.exe: click, inspect/read, wait/poll, handle native dialogs and tricky controls, selector strategy with fallback. A pure mechanism skill — it drives and reads a UI but never decides whether an action succeeded or means what the caller intended; that judgment belongs to whichever skill or agent calls it (e.g. ui-navigation-orchestrator, agent-orchestrator). Use whenever a task needs to click, type into, or read the state of a Windows desktop UI, for any target application.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 18`. Compare this file's version against the source-of-truth copy at
  `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\ui-interaction\SKILL.md`, and against that clone's
  GitHub upstream, once at the start of a
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
  - v5 — Adds `--clear` guidance for emptying controls, documents strict option parsing and
    `--flag=value` for empty or `--`-prefixed values, and clarifies that drag success means input
    was dispatched rather than the drop accepted. Extends explicit read-back confirmation to
    clearing as well as typing and chat submission.
  - v6 — Adds the shared hands-off cursor indicator `scripts\AgentCursor.ps1` (moved here from
    agent-orchestrator, which now loads it from this skill): red dot while an action moves the
    mouse or sends keys, green dot for the whole of a multi-step UI run, nothing for ordinary
    work. agent-orchestrator's sessions are blue; whichever session starts first owns the colour.
    The script also provides `Set-AgentForegroundWindow` (Alt tap plus `SetForegroundWindow`,
    verified) for when `activate` is blocked by focus-stealing prevention.
  - v7 — Documents cross-process window discovery, substring filters, default exclusions, and
    new-window waits; replaces the discovery and scroll-to-element gaps with the supported
    primitives. Adds UIA-only `scroll-into-view`, its activation caveat, methods, errors, and
    explicit post-scroll verification.
  - v8 — Documents shipped CLI `--controlType` selector filtering and absolute
    `scroll-container --verticalPercent` for reading virtualized content. MCP support for these
    toolkit additions is pending a rebuild.
  - v9 — Documents that `read-visible-text` output is flat and unlabelled, collapsed content is
    not expanded, and long virtualized lists should be re-read after each `scroll-container`
    position.
  - v10 — Documents that `inspect` screenshots are opt-in (toolkit commit `aabc864`): pass
    `screenshot` only when an image is needed and delete only the returned `screenshotPath` files.
    Toolkit builds and MCP servers not yet rebuilt still save a screenshot on every `inspect`.
  - v11 — Documents the toolkit's own cursor session (toolkit commit `daee298`): CLI
    `cursor-session start|stop [--kind UiAutomation|Orchestrator]` and MCP
    `ui_cursor_session_start` / `ui_cursor_session_stop`. It shares `AgentCursor.ps1`'s flag file,
    so either can be used for the green (or blue) session. Use the MCP tools when no PowerShell
    is available, and always stop the session when monitoring or a multi-step run ends.
  - v12 — Adds a screenshot-first fallback for opaque windows, restart-safe window rediscovery,
    physical-pixel coordinate guidance, and the optional `Invoke-ScreenClick` helper.
  - v13 — Rewrites the opaque-window section for the toolkit's new verbs (commits `3e63f7d`,
    `57c821f`, `07fe1d2`, `66b4441`): coordinate `click`/`right-click`/`double-click` with bounds
    check, `window-gone`, screenshot `windowRect`/`dpiScale` with `--region`/`--scale`, selector-free
    `send-keys` and `paste-text`. Adds guidance to look at as little as possible and to compare
    pixels locally before viewing. `Invoke-ScreenClick` is kept for older builds. Wheel scroll
    remains unsupported.
  - v14 — Documents the mouse-wheel `scroll` verb / `ui_scroll` (toolkit commit `9f609c7`): moves
    the real cursor, scrolls the window under it, stops if the cursor or foreground window changes,
    needs verification of the result. Removes the "no wheel scroll" gap; the line in the
    `scroll-into-view` primitive about no mouse-wheel fallback still describes that verb only.
  - v15 — Records the verified accessibility fix: `--force-renderer-accessibility` on a throwaway
    VS Code Insiders instance raised the UIA tree from 14 to 181 nodes and made selectors work.
    Notes that it is a launch argument, exposes full content, and is untested on the Claude app.
  - v16 — Corrects a misdiagnosis in v12-v15: the Claude desktop window was not opaque. The default
    `--maxDepth 8` of `inspect` and `read-visible-text` stops above the page content (the chat input
    is at depth 16; `read-visible-text` gave 6 lines at depth 8 and 272 at depth 30). The section now
    says to probe deep and filtered (`--maxDepth 30`) before calling a window opaque, and keeps the
    screenshot-first fallback and the accessibility-flag result for windows that stay frame-only.
  - v17 — Documents the toolkit's depth-limit detection (commits `5b5923a`, `7ea546b`): `depthLimited`,
    `maxDepth`, `nodesBeyondDepth`, `nodesBeyondDepthCapped` and `hint` on `inspect` and
    `read-visible-text`, so a frame-only result at the default depth is recognisable as "look deeper".
  - v18 — Step 0 now also checks the repo's GitHub upstream (`git fetch`, then reads the upstream
    copy of this file), not only the local clone, and offers to run
    `Install-Skills.ps1 -Remote -Force` when a newer version exists. Same trigger as before: once
    per session.

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
- **Screenshots are opt-in, and cleanup is the caller's responsibility.** `inspect --screenshot
  true` (MCP: `screenshot: true`) saves a PNG of the whole window to
  `%LOCALAPPDATA%\AgentDebugToolkit\screenshots\` and returns its path in `screenshotPath`; the
  file is not deleted automatically. The capture can include source code, chat text and other
  window contents, so pass `screenshot` only when an image is actually needed.
  - At the end of the task, delete only the files whose paths your own calls returned in
    `screenshotPath`, never the whole folder or files you did not create (other runs or users may
    keep screenshots on purpose).
  - Toolkit builds from before commit `aabc864`, and any MCP server not rebuilt since, save a
    screenshot on **every** `inspect` even when none is requested. On those builds, check every
    `inspect` result for `screenshotPath` and clean up those paths too, and prefer `find-all`,
    `get-text` or `read-visible-text` over `inspect` when they are enough.

## Step 0: Version Check

Run this **once**, the first time this skill's primitives are about to be used in a session —
not on every individual click/inspect/wait/type call. If another skill composing this one
(`ui-navigation-orchestrator`, `agent-orchestrator`) already ran its own Step 0 this session,
still check this skill's own version once (they version independently), but never repeat the
check per call — this skill is invoked far more often than the others, so re-checking per call
would defeat the point of it being a cheap, once-per-session check.

1. The repo clone is `C:\MyFiles\Git\Visual-Studio-Copilot-Skills`. Use the same "ask, don't
   guess" fallback as the `AgentDebugToolkit` path above if it doesn't exist on the current
   machine.
2. Check GitHub: `git -C C:\MyFiles\Git\Visual-Studio-Copilot-Skills fetch --quiet origin`. This
   changes no working file. If it fails (offline, no upstream), say once that GitHub could not
   be checked and continue with the clone alone.
3. Read `CURRENT_SKILL_VERSION` from the clone's copy at
   `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\ui-interaction\SKILL.md` and, if the fetch worked,
   from the upstream copy:
   `git -C C:\MyFiles\Git\Visual-Studio-Copilot-Skills show "@{u}:ui-interaction/SKILL.md"`.
   The repo version is the higher of the two.
4. Compare the repo version to this file's own `CURRENT_SKILL_VERSION`.
5. If the repo's version is higher: tell the user plainly what changed (the changelog entries
   between the two versions) and whether the newer version is only on GitHub (clone not pulled
   yet) or already in the clone. Ask via `ask_user` whether to update now. On yes, run
   `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\Install-Skills.ps1 -Remote -Force`: it pulls the
   clone (fast-forward only, never when tracked files have uncommitted changes) and installs every
   changed skill; tell the user the new text applies from a new chat session. On no, proceed
   with the current session and do not ask again in it.
6. If versions match: proceed silently.

## Hands-off cursor indicator (user requirement)

`scripts\AgentCursor.ps1` (next to this SKILL.md; `Get-Help` it for details) marks the system
cursor so the user can tell who is using the machine and keep their hands off. It is shared:
agent-orchestrator loads it from here.

| Dot | Meaning | Who sets it |
| --- | --- | --- |
| Red | Mouse or keyboard input right now | Any skill, around each input action |
| Green | A multi-step UI run (this skill or ui-navigation-orchestrator) is in progress | `-Session Start -Kind UiAutomation` |
| Blue | agent-orchestrator is driving or monitoring another Copilot chat | agent-orchestrator only |

- **Red - input.** Wrap every action that moves the mouse or sends keys (`click`,
  `right-click`, `double-click`, `drag`, `move-mouse`, `type`, `send-keys`, `set-grid-cell`,
  `submit-chat-message`, `activate`) in the same PowerShell call:
  `. <skill>\scripts\AgentCursor.ps1; Enable-AgentCursor; try { <agentdebug-ui calls> } finally { Restore-AgentCursor }`.
  Batch consecutive input actions into one block rather than flashing red per call.
  Read-only verbs (`inspect`, `list-windows`, `find-all`, `get-text`, `read-visible-text`,
  waits) don't change the cursor. If `activate` fails with `stale-context` because another
  process is in front, use `Set-AgentForegroundWindow -Handle <hwnd>` from the same script
  inside the red block; it returns `$true` only if the window really came to the front.
- **Green - multi-step run.** Before a run of several UI actions (navigating through several
  screens, an explore/map sweep, a click-and-wait loop), run
  `scripts\AgentCursor.ps1 -Session Start -Kind UiAutomation`; run
  `scripts\AgentCursor.ps1 -Session Stop -Kind UiAutomation` when it ends or fails, and before
  any reply that waits for the user (a question, a confirmation, a report) - start it again when
  you resume. A single action or a read-only check gets red only (or nothing), never green.
- **Green session without PowerShell (MCP / CLI).** Toolkit builds from commit `daee298` on can
  start and stop the same session themselves: MCP `ui_cursor_session_start` and
  `ui_cursor_session_stop` (default kind `UiAutomation`, green), or CLI
  `agentdebug-ui.exe cursor-session start|stop [--kind UiAutomation|Orchestrator]`. They share the
  script's flag file and first-owner rule, so a start while another kind owns the cursor returns
  `changed: false` with the owner and leaves the cursor alone. Use this around any monitoring or
  polling loop driven through MCP tools (for example watching a Copilot chat with `ui_find_all`
  and `ui_read_visible_text`):
  1. Start the session before the first poll.
  2. Stop it, passing the same `kind`, when monitoring ends, on any error, and before any reply
     that waits for the user; start it again when you resume.
  3. A stop with no `kind` clears any session, including a blue agent-orchestrator one, so pass
     the kind unless clearing a leftover dot.
  A failure to draw the dot returns success with a `warning`; continue without it. A server not
  rebuilt since `daee298` does not list these tools; fall back to the script.
- **One colour at a time.** The first session started owns the colour. Inside an
  agent-orchestrator session (blue), `-Kind UiAutomation` Start and Stop change nothing - keep
  calling them as normal; the blue session is stopped by its owner. After a red block the cursor
  returns to the owning session's colour, or to the user's own cursors if none is active.
- **Never for ordinary work.** Editing files, git, builds, reading code: no dot of any colour.
- If a dot is ever left behind, `scripts\AgentCursor.ps1 -Restore` clears every session and
  restores the user's cursors (or the user can sign out and back in). A session flag older than
  12 hours is ignored.

## Core primitives

- **list-windows / attach** — find and scope to a target window, by hwnd, pid, or title.
  `list-windows` has three mutually exclusive scopes: `--pid <n>` (or the session context pid
  by default), `--all` (any process on the current desktop), or `--processName <name>` (all
  processes matching the name case-insensitively; a trailing `.exe` is stripped).
  `--titleContains` and `--className` are case-insensitive substring filters, not wildcards.
  `--all` and `--processName` exclude DWM-cloaked, untitled, and zero-area windows by default;
  `--includeUntitled` re-includes untitled windows only. Pid scope has no default exclusions.
  Titles may contain sensitive data: filter first and keep only the needed rows. Discovery is
  read-only and does not change session context; use the returned hwnd or set the context pid.
  Matching by title alone when multiple windows share it is ambiguous — prefer `--pid` or an
  explicit hwnd when available, and flag ambiguity rather than silently picking one.
- **click** — by selector. Prefer `Name`-based selectors with a documented fallback strategy over
  `AutomationId` where the caller's target app is known to expose unreliable `AutomationId`s (that
  finding belongs to the caller/target app's own notes, not generalized here, since it isn't true
  of every app). When a selector could plausibly match more than one element (e.g. shared labels,
  or a name that also matches a system element such as a browser bookmark), scope it with
  `--scopeHwnd` (`click` also accepts `--controlType` to filter by a recognized short UIA type).
  `click`, `right-click`, `double-click`,
  `drag`, selector-form `move-mouse`, `type`, `get-text`, and `send-keys` now fail with
  `ambiguous-match` instead of acting on the first match. The response includes `count` and up to
  10 candidates (`name`, `automationId`, `controlType`, `className`), and no action is performed.
  On `ambiguous-match`, narrow with `--scopeHwnd`, `--controlType` on supported verbs, or retry
  using a candidate's `AutomationId` if it is unique. This behavior requires an
  `agentdebug-ui.exe` built from the 2026-10-14 change; an older build silently uses the first
  match. `get-text` now also accepts `--scopeHwnd`.
  If selector uniqueness is uncertain, use `find-all` first (see
  `CLI_CONTRACT.md`) to confirm the match count before acting. Its own
  `--scopeStrategy`/`--scopeValue` flags can narrow that pre-check, but they are not accepted by
  `click`/`type` themselves. CLI `click`, `get-text`, `find-first`, `find-all`, and
  `wait-for-element` accept optional `--controlType <short name>`; this filters candidates before
  matching/ambiguity checks, but does not guarantee uniqueness. An unknown type returns
  `invalid-argument`. MCP support for this new selector option is pending a rebuild; use the CLI
  until the matching MCP tools are rebuilt. A selector matching a label does not prove that it
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
  To empty a control, use `type --clear` (MCP: `ui_type` with `clear=true`), not `--text ''`.
  `--clear` is mutually exclusive with `--text` and `--paste`. It uses `ValuePattern` where
  available (`method: "pattern-clear"`); otherwise it clicks the control and sends select-all
  then delete (`method: "synthetic-clear"`). `--verify` checks for an empty read-back only on
  `pattern-clear`. The `synthetic-clear` path has not been validated live, so read back to
  confirm the control is empty after it.
- **drag** — success means the input was dispatched, not that the application accepted the drop.
  The response now includes source and target coordinates, useful for diagnosing a drag that had
  no effect. Verify the expected result separately by re-reading the target state. Two attempts
  to reorder Notepad tabs returned success with no visible reorder; the cause was not established.
  Prefer a target with a measurable before and after state when you need to be sure. `--steps`
  and `--durationMs` can be raised for targets that need more intermediate mouse moves.
- **wait / poll** — for a UI state to settle, invoked asynchronously so a caller can relay
  progress without blocking.
- **set-grid-cell** — for virtualized WPF DataGrid controls (see gotcha below).
- **scroll-container** — CLI only until MCP is rebuilt:
  `scroll-container --hwnd <h> --strategy <Name|AutomationId> --value <v> --verticalPercent <0..100> [--scopeHwnd <h2>]`.
  Moves one uniquely selected container to an absolute vertical percent using UIA `ScrollPattern` only;
  there is no direction or relative-step option. Check `changed`, `boundaryReached`, and
  `verticalScrollPercentAfter`, then re-read the rendered content at each position. This is
  useful for surveying a virtualized list: `scroll-into-view` exposes a specific target, not
  every item. The call does not request activation or send input, but changes the scroll position
  and does not restore it. An ambiguous container must be narrowed; a container without vertical
  scrolling returns `not-scrollable`. Do not infer the full list from one rendered snapshot.
- **scroll-into-view** — CLI: `scroll-into-view`; MCP: `ui_scroll_into_view`. Uses UIA patterns
  only: it does not request activation and makes no cursor or input calls, but the target's UIA
  provider may activate its window during a scroll (observed with WPF). It does not restore the
  scroll position. Run `find-all` first to check selector matches; for virtualized lists pass
  the list as the scope with both `--scopeStrategy` and `--scopeValue`. The scope is both the
  search area and scroll container. Afterward verify with `find-first` or `get-text`.
  Methods: `already-visible`, `scroll-item`, `ancestor-scroll`, `item-container`, `scroll-search`.
  It tries `ScrollItemPattern`, a vertically scrollable ancestor, or
  `ItemContainerPattern.FindItemByProperty` and `Realize` before a scroll-search from the top;
  success requires `fullyVisible: true`. Horizontal virtualization is not searched, and no
  mouse-wheel fallback is implemented.
  Errors: `invalid-argument`, `window-gone`, `window-not-responding`, `element-not-found`, `stale-context`,
  `container-not-found`, `ambiguous-container`, `not-scrollable`, `ambiguous-match`, `timeout`,
  `element-not-found-after-scroll`, `scroll-provider-error`. `element-not-found` means the hwnd
  has no window; `element-not-found-after-scroll` means the element was not found or disappeared
  after scrolling. A dead or closed hwnd returns `window-gone` on current builds (older builds:
  `window-not-responding` from the shared responsiveness check). Narrow ambiguous matches/scopes
  rather than choosing one silently.

### Electron and opaque windows: probe deep, then screenshot-first

- **Probe deep before calling a window opaque.** `inspect` and `read-visible-text` default to
  `--maxDepth 8`, but an Electron/Chromium window nests its page content far below that. On the
  Claude desktop app the web page starts around depth 9, the chat input (`Edit`, name `Prompt`,
  with ValuePattern and TextPattern) is at depth 16, and `read-visible-text` returned 6 lines at
  depth 8, 91 at depth 16 and 272 at depth 30. A result with only the window frame (Minimize,
  Restore, Close, empty Pane/View nodes) at the default depth does **not** show the app is
  opaque; this exact mistake produced an earlier "UIA cannot read Claude" conclusion. First
  re-probe once, deep and filtered: `inspect --maxDepth 30 --controlType Edit` (or
  `--nameContains <label>`, or `--controlType Button`) and `read-visible-text --maxDepth 30`.
  Filtered output is a pruned tree, so it stays small. Toolkit builds from commit `5b5923a` on
  say so themselves: when nodes at the depth limit still have children, `inspect` and
  `read-visible-text` add `depthLimited: true`, `maxDepth`, `nodesBeyondDepth` (a lower bound when
  `nodesBeyondDepthCapped` is true) and a `hint` that suggests a deeper `--maxDepth`; treat that as
  "not opaque, look deeper". Chromium builds its accessibility tree lazily, so if a deep probe
  still shows only the frame, probe once more after a few seconds before deciding.
- **Only if a deep filtered probe still returns just the window frame** is the app opaque.
  Then stop UIA probing, tell the user immediately (“UIA cannot read this app; screenshot and
  coordinates only”), and continue screenshot-first without retrying selectors. Never relaunch
  the app or enable accessibility without the user's approval, because that can expose chat
  content.
- **Root fix for a truly opaque Electron app, verified on a throwaway app.** Launching it with
  `--force-renderer-accessibility` turns its accessibility tree on. On a throwaway VS Code
  Insiders instance (temporary profile, extensions off) the same depth-14 `inspect` went from 14
  UIA nodes (window frame only, 3 buttons, no edit controls) to 181 (37 named buttons, an edit
  control and documents), `find-all` and Name-selector `click` then worked, and toggling a panel
  by selector changed the tree. It is a launch argument: the app must be (re)started with it, it
  cannot be switched on for a running instance, and it exposes the app's full content (chat text
  included) to every UIA client, so it needs the user's approval. The Claude desktop app did not
  need it: its tree was readable once probed deeply.
- **Dead or replaced window.** A hwnd that no longer exists returns `window-gone` (older builds:
  `window-not-responding`), for example after an app restart. Re-run
  `list-windows --processName <name>` to find the current hwnd and pid, then take a fresh
  screenshot before any click. Do not reuse the old hwnd or an earlier screenshot.
  `window-not-responding` now means the window exists but is hung.
- **Seeing.** `screenshot --hwnd <h>` returns `screenshotPath` plus `windowRect` (left, top, right,
  bottom, physical screen pixels), `imageWidth`, `imageHeight` and `dpiScale`. Do not look at a
  full-window image when a small one answers the question: `--region x,y,w,h` (window image
  pixels, inside the window) saves only that part, and `--scale 0.1..1.0` shrinks it. Look at as
  little as the next decision needs, and for "did anything change?" compare before and after
  pixels in a script before viewing either image. `inspect --screenshot` is unchanged. The capture
  normally renders the target window itself, but if that fails the toolkit falls back to copying
  the screen area, which also captures any window covering the target (a cropped image included):
  keep the target unobscured when you depend on a capture.
- **Coordinate recipe.** Coordinates are physical pixels. For an unscaled image,
  `screenX = windowRect.left + imagePixelX` and `screenY = windowRect.top + imagePixelY`; with
  `--region`/`--scale`, `screenX = windowRect.left + region.x + imagePixelX / scale` (likewise
  y; ceiling rounding makes this approximate by up to one pixel). `windowRect` includes the
  invisible resize border, so a maximized window sits at about −11,−11 and its image is larger
  than the visible area. Do not multiply by `dpiScale` again. Geometry is only meaningful for a
  visible window (a minimized window reports a rectangle near −32000).
- **Acting by coordinates.** `click`, `right-click` and `double-click` accept `--x/--y` instead of
  a selector (never both). The point must lie inside the `--hwnd` window rectangle, checked before
  activation for a non-minimized window and again after activation or restore; pass
  `--allowOutsideWindow` only deliberately. A point inside the rectangle can still hit another
  window covering it. Also available: `activate`, `move-mouse --x/--y`, `get-cursor-pos` (a
  cheap, image-free check that the pointer is at the intended point; it does not say which window
  or control received a click, so still verify the effect) and `wait-for-window-change`.
  `drag` is not an opaque-window tool: its source still needs `--strategy/--value`; only the
  destination can be `--targetX/--targetY`. Take a screenshot immediately before each coordinate action and
  verify the result afterwards; menus and lists move between captures.
- **Keys and text without a selector.** `send-keys --hwnd <h> --keys <...>` with no
  `--strategy/--value` sends keys to whatever has focus in that window (explicit `--hwnd`
  required; `--scopeHwnd` not allowed; `--focusMode`, if given, must be `none`). Put focus first,
  for example with a coordinate click. `paste-text --hwnd <h> --text <...>` pastes text (newlines
  allowed) with Ctrl+V and restores the previous clipboard after `--restoreDelayMs` (default 300;
  a wait, not a guarantee). If the target reads the clipboard later than that, **it pastes the
  restored previous clipboard instead of your text, possibly unrelated or confidential content,
  while the call still reports success**: raise the delay for a slow target and always verify what
  landed. Use it for multi-line or special-character text, because `send-keys` breaks on
  `+ ^ % ~ { }`. Check both `clipboardRestored` (`false`: the user's clipboard was replaced and
  could not be put back) and `clipboardSnapshotComplete` (`false`: the previous clipboard was not
  preserved in full; an omitted `clipboardRestored` then does not mean it was empty). MCP:
  `ui_send_keys` (selector optional) and `ui_paste_text`. Success means keys were sent, not that
  the text landed: verify with a cropped screenshot.
- **Older builds.** Without toolkit commit `3e63f7d` there is no coordinate click: use
  `scripts\Invoke-ScreenClick.ps1` (dot-source; `Invoke-ScreenClick -X <x> -Y <y> [-Button
  Left|Right] [-Double]`, DPI-aware, wrapped in the red cursor). The new CLI verbs also reach the
  MCP tools (`ui_click` with `x`/`y`, `ui_paste_text`, `--region`/`--scale`) only after the MCP
  server is rebuilt and restarted, which needs the sessions that use it closed.
- **Scrolling.** `scroll --hwnd <h> --direction up|down|left|right [--clicks 1..50]` (MCP
  `ui_scroll`; toolkit commit `9f609c7`) sends mouse-wheel notches with no UI Automation, so it
  works where `scroll-container` and `scroll-into-view` cannot. It brings the window to the
  foreground, **moves the user's real cursor** to the window center (or to `--x/--y`, which must be
  inside the window like a coordinate click) and scrolls whatever window is under it, so a window
  covering that point would receive the wheel. It stops if the cursor is moved by the user or by a
  clip rectangle, or if the foreground window changes; do not touch the mouse while it runs. Success
  means the input was sent, so verify the view changed (for example by comparing cropped
  screenshots before and after). How far the content moves per notch is up to the application. On
  an older build there is no wheel scroll.
- **Data handling.** Screenshots can contain confidential content: capture only what the task
  needs, and delete only screenshot files whose paths your own calls returned.

### Verifying typed input

- After every `type` (including `--clear`) or `submit-chat-message` call, perform an explicit
  read-back before treating text entry or clearing as confirmed. `success: true` or a passed
  `--verify` is not sufficient on its own:
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
- **`read-visible-text` output is flat.** It returns one de-duplicated list of strings in visual order, with no label for which element each string came from, so it cannot tell chat messages from tool-call details or other UI text. Collapsed or expandable content (for example, folded tool-call details) is not expanded, so its inner text does not appear. Do not treat its output as a complete transcript. To check a specific element's text, use a scoped `inspect` or `get-text` on that element. When reading a long virtualized list, re-read after each `scroll-container` position, because one read covers only what is currently rendered.
- **Virtualized WPF DataGrid controls** — use the `set-grid-cell` verb; some grids need an
  explicit `--applyStrategy`/`--applyValue` to commit the edit.
- **Plain-string ListBox items** — a `ListBoxItem` and its `TextBlock` can share the same `Name`,
  causing a Name selector to return `ambiguous-match`. Give each item a unique `AutomationId`
  in the app under test, or use a selector that resolves to one element. `scroll-into-view` can
  move the scroll position even when it returns an error.
- **Hover-driven pickers** — some pickers only detect a target after the OS cursor has physically
  entered the window; a raw click at a coordinate isn't sufficient on its own.
- **Cross-process window discovery** — use `list-windows --all` or `--processName <name>` with
  filters. `wait-for-window-change` accepts the same scopes and filters: `--until settle` waits
  for a stable hwnd set; `--until match` waits for a nonempty stable match and requires at least
  one of `--titleContains`, `--className`, or `--processName`. To find a newly opened window,
  pass hwnds from an earlier `list-windows` as a comma-separated `--excludeHwnds` list; a window
  opened before the wait's first snapshot otherwise belongs to its baseline, not `newWindows`.
- **Strict option parsing** — the CLI now rejects a value-taking flag with no value, or followed
  by another `--` flag, with `invalid-argument` instead of silently using `"true"`. Windows
  PowerShell 5.1 drops empty-string arguments to native programs, which is how `--text ''` used
  to type "true" (confirmed live). Use `--flag=value` for an empty value (`--text=`) or a value
  that starts with `--` (`--text=--foo`). The only flags that may be bare are `--screenshot`,
  `--paste`, `--verify`, `--clear`, `--all`, `--includeUntitled`, and `--allowOutsideWindow`
  (the last takes only `true` or `false` when given a value). This requires an `agentdebug-ui.exe` built from the
  2026-10-14 parsing fix; an older build still turns a bare flag into `"true"`. MCP tools already
  send empty and `--`-prefixed values in `--flag=value` form.
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
