---
name: ui-interaction
description: 'Generic Windows UI automation primitives via AgentDebugToolkit''s agentdebug-ui.exe: click, inspect/read, wait/poll, handle native dialogs and tricky controls, selector strategy with fallback. A pure mechanism skill — it drives and reads a UI but never decides whether an action succeeded or means what the caller intended; that judgment belongs to whichever skill or agent calls it (e.g. ui-navigation-orchestrator, agent-orchestrator). Use whenever a task needs to click, type into, or read the state of a Windows desktop UI, for any target application.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 25`. Compare this file's version against the source-of-truth copy at
  `<skills repo>\ui-interaction\SKILL.md` (the clone path is in
  `%USERPROFILE%\.copilot\skills-source.json`, see Step 0), and against that clone's
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
  - v19 — Step 0 reads this skill's version and what's new from the repo's small `skills-index.json`
    instead of the whole `SKILL.md`, so the update check costs about 2 KB, not up to 100 KB. If the
    index cannot be read it falls back to a filtered read of the version line.
  - v20 — The skills repo clone is found through `%USERPROFILE%\.copilot\skills-source.json` and
    AgentDebugToolkit through `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit`, instead of fixed
    `C:\MyFiles\Git` paths, and Step 0 gains a toolkit check (clone, update and build through
    `Install-Skills.ps1`). Needs the `Install-Skills.ps1` from the same change; no verb changed.
  - v21 - Adds state-first toggle handling, bounded inspection guidance, WinForms tree/tab and
    minimized-window recovery, explicit portable-package selection, and a script-free focus
    handback path. Documentation only; new toolkit capabilities are not assumed.
  - v22 - Gates new workflows on executable identity/capabilities and documents bounded inspection,
    paged UIA readers, verified state/selection changes and explicit minimized-window restoration.
  - v23 - Resolves managed executable paths from the successful-build marker when available and
    distinguishes observational remote-session diagnostics from an RDP activation fix.
  - v25 - Adds user-activity helpers to `AgentCursor.ps1`: a quiet wait before taking the foreground, an
    amber waiting dot with a sound, an input lock, and a hand-back of the person's window and focus. The quiet
    wait considers idle time, held mouse buttons and modifiers, do-not-disturb states and a manual pause. The
    rest are a cross-process input lock, a shared record of the agent's own last input, input-stamp checks
    between steps, and the hand-back of the focused control and pointer. Moving the pointer alone is ignored;
    typing, clicks, scrolling and held buttons count. A new section documents them. Offline tests with every
    native call mocked (81 assertions). Live (2026-11-25, one machine): a manual pause, simulated typing into
    a scratch window (43 of 43 characters landed there while the send waited), a held mouse button, a lock held
    by another process and a normal send with hand-back all behaved as designed. Not tested live: a real
    presentation, several orchestrators sending at once, and the amber dot and sound as seen by a person.
  - v24 - Documents Windows PowerShell 5.1 pitfalls, partly off-screen windows that still report
    `IsOffscreen: false`, and floating tool windows, from a 2026-11-25 cross-chat sender test. The
    5.1 pitfalls are single-result `.Count`, `$PSScriptRoot` empty in `param()` defaults for advanced
    scripts run with `-File`, backslash-before-quote native argument corruption and DPI-unaware window
    coordinates. Documentation only; no script or toolkit verb changed.

# UI Interaction

Drive and read a Windows desktop UI via `agentdebug-ui.exe`. This skill only performs and
observes actions — it has no opinion about *why* you're clicking something or whether the result
is *correct* for your task. If deciding what a click or a piece of read-back text means requires
knowing the caller's intent (e.g. "is this the ChoicePrompt card I expected," "did the map
navigate where I meant it to"), that judgment stays with the caller. This skill only ever answers
"perform this action" or "tell me what's there right now."

## Prerequisites / environment

- **Toolkit location:** AgentDebugToolkit is cloned and built on this machine by
  `Install-Skills.ps1`, at `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit` (expand
  `%USERPROFILE%` to an absolute path before using it). If that folder or the exe is missing,
  Step 0's toolkit check says what to do — never guess a path or silently fall back to a different
  clone.
- Tool: `agentdebug-ui.exe`, built from
  `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli`, exe under
  `bin\Debug\net8.0-windows\`. It is built by the toolkit's `scripts\agent\Build-Toolkit.ps1`, which
  `Install-Skills.ps1` runs; if the exe is missing, use Step 0's toolkit check rather than a manual
  `dotnet build`.
- **Managed executable discovery:** read the selected managed clone's `.built-version` JSON.
  Updated build markers expose `tools.ui.executablePath` (and `tools.vs`, `tools.console`,
  `tools.server` for the other tools). Use the exact absolute path, confirm the file exists,
  then run that binary's `info` and check its reported tool/path/capabilities. A marker is a
  discovery aid, not proof of binary identity or provider support. Older markers lack `tools`;
  use the documented project/output path above only after confirming the file exists. Report
  malformed/missing paths rather than searching arbitrary Debug/Release/portable copies.
  Explicitly selected portable packages still take precedence over managed discovery.
- **Explicit portable package:** if the user supplies a package location, use
  `<package>\ui\agentdebug-ui.exe` and that package's docs instead. Record the exact executable
  path; Step 0 checks the managed clone/build, not a separately copied package or its verb
  capabilities. Run the exact executable's identity/capability preflight below; do not silently
  switch installs, or infer verbs from a folder layout.
- **CRITICAL environment gotcha:** always run
  `Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue` before invoking `agentdebug-ui.exe`
  or `dotnet build`/`restore` in a fresh PowerShell process — VS's inherited `DOTNET_ROOT` breaks
  both.
- Full verb contract: `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit\docs\CLI_CONTRACT.md`. Read this if a verb
  behaves unexpectedly — do not guess at flags.
- **Screenshots are opt-in, and cleanup is the caller's responsibility.** CLI `inspect --screenshot
  true` saves a PNG of the whole window to
  `%LOCALAPPDATA%\AgentDebugToolkit\screenshots\` and returns its path in `screenshotPath`; the
  file is not deleted automatically. The capture can include source code, chat text and other
  window contents, so pass `screenshot` only when an image is actually needed.
  Current MCP `ui_inspect` is read-only and has no screenshot option; use the screenshot tool
  separately when an image is needed. If image viewing fails, do not claim to have seen the
  capture or guess coordinates from it; use readable UIA evidence or ask the user for help.
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
   - GitHub's copy (skip if the fetch failed): `(git -C "<skills repo>" show "@{u}:skills-index.json" | Out-String | ConvertFrom-Json).skills.'ui-interaction'`
   - The clone's copy: `(Get-Content "<skills repo>\skills-index.json" -Raw | ConvertFrom-Json).skills.'ui-interaction'`
   - If neither can be read (a repo from before the index existed), read only the version line,
     never the whole file: `Select-String -Path "<skills repo>\ui-interaction\SKILL.md" -Pattern 'CURRENT_SKILL_VERSION\s*=\s*\d+' | Select-Object -First 1`.
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
     yes, run it and check the exit code. On no, continue only if `agentdebug-ui.exe` exists
     (`Behind` works with the installed build); otherwise stop, because this skill cannot work
     without it.
   - `Diverged`, `NotAClone`, `NoDotnetSdk` or `NoGit`: report the line once and change nothing;
     continue only if `agentdebug-ui.exe` exists.
   - No `TOOLKIT:` line (an older installer): continue only if `agentdebug-ui.exe` exists,
     otherwise ask the user.
   Do not ask again in this session.
8. **Exact-executable preflight, once per chosen binary.** Run `<chosen exe> info` before using
   the capabilities below. Keep its actual `executablePath`, `architecture`, embedded
   `build.sourceCommit`/`sourceDirty` and `capabilities`; null build facts remain unknown. A
   matching skill version, checkout HEAD or installer marker does not identify a copied binary.
   For a portable package, also run `info --verifyPackage`: only `packageVerification.status`
   `matched` establishes manifest consistency. `not-present` means unverified, not matched;
   report it and ask before relying on an unverified package. Stop using a mismatched package.
   This is integrity evidence, not a signature or permission to mutate a target.

   | Workflow | Required capability IDs |
   | --- | --- |
   | State read / desired-state toggle | `ui.get-state.v1` / `ui.set-toggle-state.v1` |
   | Explicit restore / lookup hints | `ui.activate.restore.v1` / `ui.lookup-diagnostics.v1` |
   | Bounded inspect / text | `ui.inspect.bounded.v1` / `ui.read-visible-text.bounded.v1` |
   | Paged rows / tree items | `ui.read-rows.uia-paged.v1` / `ui.read-tree-items.uia-paged.v1` |
   | Verified item / row selection | `ui.select-item.verified.v1` / `ui.select-row.verified.v1` |
   | Coordinate click / window-level keys | `ui.click.coordinates.v1` / `ui.send-keys.window.v1` |

   Check only the features needed for the task. If `info` is unavailable or a required ID is
   missing, do not issue that new verb/flag; use already-verified legacy behavior or ask to update
   the chosen installation. An advertised feature does not guarantee provider support. For MCP,
   check the running server's advertised tool/schema too: CLI identity or rebuilding files does
   not update an already-running server. Restart/update only with approval; never enable mutation
   permissions merely to obtain a tool.

## Hands-off cursor indicator (user requirement)

`scripts\AgentCursor.ps1` (next to this SKILL.md; `Get-Help` it for details) marks the system
cursor so the user can tell who is using the machine and keep their hands off. It is shared:
agent-orchestrator loads it from here.

| Dot | Meaning | Who sets it |
| --- | --- | --- |
| Amber | The agent wants the keyboard or mouse and is waiting for the person to pause; nothing is typed or clicked yet | `Wait-AgentUserQuiet`, after about half a second of waiting |
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

### Be considerate of a person using the machine

Taking the foreground while someone types sends their keystrokes into the target window, and an Alt tap
(`Set-AgentForegroundWindow` uses one) can open a menu in their application. `scripts\AgentCursor.ps1`
(dot-source it) provides the building blocks; `Send-CopilotPrompt.ps1` and `Select-ChoicePromptOption.ps1`
already use them. Real input is read with `GetLastInputInfo`; no keyboard hook is installed and no key is recorded.

- **`Wait-AgentUserQuiet`** returns when it is safe to take the foreground: no typing, click or scrolling for
  3 s (6 s while the focused editor of the foreground application holds text), no mouse button or modifier
  key held (a held button produces no new event, so idle time cannot see a drag), and no do-not-disturb state.
  Moving the pointer alone, whatever the distance, is ignored: people move the mouse for many reasons, and a
  jittery pointer would otherwise keep every wait going. It restarts the wait whenever the person types or
  clicks again and gives up after 120 s with `UserActive`,
  `DoNotDisturb` or `SessionNotPresent`; the caller must then type and click nothing. After about 0.5 s of
  waiting the cursor shows the amber dot and one short system sound plays; after about 30 s the person is asked
  once to pause (spoken with `-SpeakRequest`, which the caller passes only when speech is on in the chat,
  otherwise the sound repeats). When the person is already idle it returns at once.
- **Do not disturb** (`Get-AgentDoNotDisturbReason`): a manual pause (`Set-AgentUiPause -Minutes 60`, undo
  with `Clear-AgentUiPause`; the marker is `%USERPROFILE%\.copilot\ui-pause.flag`), Windows' own state from
  `SHQueryUserNotificationState` (full-screen app, presentation settings, Focus assist quiet time, locked or
  screen-saver session) and a menu or drag in progress in the foreground. An ordinary window shared in a
  meeting is not reported by Windows, so use the manual pause for that.
- **One UI block at a time** (`Enter-AgentUiLock` / `Exit-AgentUiLock`, a session-wide mutex) so several
  orchestrators never take the foreground from each other, and a shared record of the last agent input
  (`Set-AgentOwnInputStamp`) so the next block does not wait for input that was never the person's.
- **During a block:** read `Get-AgentInputStamp` after each of your own input steps and compare it before the
  next one; if it moved, the person is using the keyboard or mouse and the block must stop. Take the foreground
  only for the input steps (do read-only checks first, since UIA reads need no foreground) and release it
  straight after the last step.
- **Hand back** (`Save-AgentUserFocus` before the first foreground change, `Restore-AgentUserFocus` after the
  last input step): the person's window, focused control and pointer return only if they have not used the
  keyboard or mouse since the last agent step; a person who typed into the held window gets their window back
  at once without a pointer move; one who already moved to another window is left alone; nothing moves while
  a mouse button or modifier is held. The result says whether the hand-back was verified.
- Never use `BlockInput` (it needs elevation and can lock the person out if the script dies) or a low-level
  keyboard hook (security tools treat it as a keylogger).

### Script-blocked environments and focus handback

- If execution policy blocks the helper scripts, do not change or bypass that policy. Use the
  approved executable directly: `cursor-session start --kind UiAutomation` before a multi-step
  run and `cursor-session stop --kind UiAutomation` on completion, failure and handback. An
  orchestrator uses `Orchestrator` instead. This session indicator is not the script's red
  per-input wrapper; do not claim that unavailable wrapper ran.
- When the caller requests focus handback, identify the hosting VS window before leaving it:
  `list-windows --processName devenv` returns candidate HWNDs and PIDs. Confirm the right
  instance with the user if ambiguous; do not choose the first VS process or assume the target
  app is the chat host. Retain the verified host HWND for this run and rediscover after a restart.
- After each requested action batch, return with `activate --hwnd <host hwnd> --restore true`
  when the restore capability is advertised (otherwise use verified legacy activation), and
  verify the host's `isForeground` through `list-windows`. Stop the session indicator before waiting for
  the user. If activation is denied and scripts are blocked, report the failure and ask for
  manual activation; do not promise that `Set-AgentForegroundWindow` is available. Raising VS
  does not prove that the Chat pane itself is selected. No automatic return-to-host verb exists
  in the current toolkit.

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
  `invalid-argument`. Use this selector option through MCP only when the running tool advertises
  it; otherwise use the verified CLI. A selector matching a label does not prove that it
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
  Filters shrink output, not necessarily execution time: the current implementation builds the
  observed tree before pruning. Prefer a known control HWND and the smallest useful depth.
  On a capable binary, add `--maxNodes 500 --maxDurationMs 2000` to opt into incremental bounded
  traversal; omitting both retains legacy eager traversal. Nodes count attempted snapshots,
  including the root and failed reads. Time is cooperative: an in-flight UIA call can overrun
  arbitrarily, and lookup/filtering/serialization are outside that timer. This is not a hard
  deadline. Check `traversal.complete`, `traversal.stopReasons`, `traversal.errors` and `truncated`; successful partial
  output or zero filtered matches does not prove absence. Narrow the root or deliberately adjust
  budgets/depth and reread from the root; there is no resume token. Use `get-text` for a known
  value and the paged readers below for collections, rather than repeatedly dumping a grid.
- **read-rows / read-tree-items** — read-only, UIA-only structured pages on capable binaries:
  `read-rows --hwnd <container hwnd> --offset 0 --limit 20 --maxColumns 16` or
  `read-tree-items --hwnd <tree hwnd> --offset 0 --limit 50 --maxDepth 30`.
  With a window HWND, optional `--strategy/--value` resolves one container; no grid is guessed.
  Offset is zero-based; limit is required (1..100). Both default to finite budgets of 5000 node
  attempts and 10000 ms, overridable with `--maxNodes`/`--maxDurationMs` (still cooperative).
  Rows use provider-logical GridPattern coordinates when available, otherwise exposed row
  ordinals; check `backend`/`scope`. Tree pages enumerate exposed TreeItem descendants, excluding
  the root. Exposed offsets scan from the root; neither cheap seeking nor stable cross-page
  identity is promised. Check `pageComplete`, `complete` and `traversal.errors`, not just `success`: exposed
  modes always have `complete:false`, and omitted `hasMore` is unknown, not false. Follow
  `nextOffset` only for a clean page with identical target/options; incomplete pages supply
  `retryOffset` for rereading, not skipping missing content. Strings are capped at 512 characters.
  Unsupported providers fail explicitly. No scrolling, expansion, realization, selection, native
  remote-memory reads or hardware-state proof is added; WinForms/x86 support depends on UIA exposure.
- **select-item / select-row** — explicit replacement selection, not a read or grid edit:
  `select-item --hwnd <h> --strategy AutomationId --value <id> --mode replace`, or
  `select-row --hwnd <container hwnd> --row <zero-based index> --rowKind logical|exposed --mode replace`.
  An optional row selector identifies the container. Choose the row kind from observed backend
  semantics, never interchange exposed ordinals and logical coordinates. Replacement may deselect
  other items. Requires supported authoritative selection patterns and an enabled target; a
  logical coordinate must establish an actual row, not merely a cell. Success requires
  `verified:true` and a freshly checked singleton selection in the actual container. The toolkit
  calls Select at most once, with no click/key/scroll/realize fallback. Check `actionAttempted`,
  `partialMutationPossible` and observations on failure, then reread before deciding on another
  action; there is no rollback or automatic retry. Budgets are cooperative and observations are
  non-atomic. Provider internals may change focus. This verifies UI selection, not an app's
  submitted choice or hardware state; preserve any caller-specific echo/submission verification.
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
- **scroll-container** — use the CLI, or MCP only when the running tool exposes these options:
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
  re-probe once, deep and filtered: `inspect --maxDepth 30 --controlType Edit --maxNodes 2000
  --maxDurationMs 3000` (or `--nameContains <label>`, or `--controlType Button`) and
  `read-visible-text --maxDepth 30 --maxNodes 2000 --maxDurationMs 3000` on capable binaries.
  Filtering prunes output after traversal; check completeness before inferring absence. On older
  builds use a narrow root and verified legacy flags only. Toolkit builds from commit `5b5923a` on
  say so themselves: when nodes at the depth limit still have children, `inspect` and
  `read-visible-text` add `depthLimited: true`, `maxDepth`, `nodesBeyondDepth` (a lower bound when
  `nodesBeyondDepthCapped` is true) and a `hint` that suggests a deeper `--maxDepth`; treat that as
  "not opaque, look deeper". Chromium builds its accessibility tree lazily, so if a deep probe
  still shows only the frame, probe once more after a few seconds before deciding.
- **Only if a sufficiently observed deep filtered probe still returns just the window frame**
  is the app opaque; a budget/depth cutoff or provider failure is not evidence of opacity.
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
- **Read state before toggling.** A checkbox, connection button or other toggle is not an
  idempotent connect/disconnect command. Establish the current and desired states before a
  change, skip it if already correct, and verify afterward. On a capable binary use
  `get-state --hwnd <h> --strategy AutomationId --value <id>`: `state.toggleState` is `on`, `off`
  or `indeterminate`; `state.isSelected` is separate. Inspect nodes expose the same fields inside
  `State`, paged elements inside `state`. Unsupported patterns have support false and no value;
  failed probes leave facts unknown and report errors, never off/false defaults. `isEnabled` or
  a disabled neighbouring control is not proof of checked/connected state.
  For a requested change use `set-toggle-state` with the same selector and explicit
  `--expectedState <freshly observed state> --desiredState <intended state>`. It rejects stale
  preconditions/unsupported/disabled targets, toggles at most once, and verifies immediately;
  three-state cycles may return `verify-mismatch` rather than reaching the requested state.
  Read/action/read is not atomic; provider internals may change focus. On attempted failure,
  inspect `mutationAttempted` and before/after observations, then reread; never blindly repeat.
  If no authoritative state is available, ask rather than guessing. UI state alone does not
  establish a physical connection or hardware outcome.
- **WinForms tabs and minimized windows.** An element-not-found result does not establish that
  a control was removed: inactive tab pages can be absent from the exposed tree. Check the
  selected tab, switch only to the intended page and reacquire selectors. Missing/empty lookups
  can include `lookupDiagnostics` with observed root HWND/minimized state and conditional tab
  hints; they do not prove which page contains the control. Read-only lookups never restore or
  switch tabs. When interaction is intended and the capability exists, use
  `activate --hwnd <root hwnd> --restore true`; default activation still does not request restore.
  Check `activated` and `isMinimizedAfter` and requery the control. Windows may deny foreground
  activation even after restoration; report failure instead of assuming success. Restoration
  does not expose inactive pages or guarantee a selector match. On older builds ask for manual
  restoration when needed. Never send dummy input just to restore or reuse pre-restore geometry.
- **Native trees and lists.** `get-text` reads ValuePattern or the selected element's Name,
  not its descendants; a SysTreeView32 name such as `-` is not its item text. Try scoped
  `read-tree-items`/`read-rows` first on capable binaries; otherwise use scoped
  `read-visible-text --maxDepth <n>` or `inspect --controlType TreeItem --maxDepth <n>`;
  descendants still depend on provider exposure and expansion. `Name` selectors are exact UIA
  Name matches, not a search across every visible cell. The new verified selection verbs require
  provider support and do not make a cell an actual row. `set-grid-cell` remains editing, not
  general row selection. Report unsupported providers rather than silently installing a
  native-message/remote-memory workaround.
- **Remote Desktop and foreground denial.** Restoring the target window is not a verified fix
  for minimized/disconnected RDP. When available, read failure `foregroundDiagnostics` for
  this process's session/protocol/connection observations and per-field errors. Unknown remains
  unknown; a local `mstsc` client is not proof this agent runs remotely, and a remote process
  cannot establish whether its external client is minimized. Record those conditions separately.
  If interactive access is unavailable, stop input and explain the limitation; read-only UIA or
  debugger checks may still work. Request user restoration/reconnection only when needed. Never
  loop activation, change RDP registry settings/security policies, transfer sessions or silently
  reconnect/disconnect a client. Test restored/minimized/disconnected conditions only in an
  approved disposable remote setup. Without that reproduction, report the limitation as
  unverified rather than claiming lower failure rates or a fix.
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
  For the new identity verb only, `--verifyPackage` may also be bare; `activate --restore`
  requires an explicit `true` or `false`.
- **Windows PowerShell 5.1 script pitfalls** (observed 2026-11-25 on 5.1.26100):
  - `.Count` on a single result can be `$null` (seen for one `Get-CimInstance` object): wrap the
    result in `@(...)` before counting.
  - `$PSScriptRoot` is empty inside a `param()` default when the script runs with
    `powershell -File` and has `[CmdletBinding()]` or any `[Parameter()]` attribute (reproduced; a
    plain `param()` block and the script body work). Set such defaults in the body.
  - Native arguments: escaping only `"` as `\"` corrupts text with a backslash before a quote
    (`Path C:\temp\"x" end` arrived as `Path C:\temp\x"` and the caller still reported success).
    Double the backslashes that precede a quote and any trailing backslashes, as
    `agent-orchestrator\scripts\Send-CopilotPrompt.ps1` does in `ConvertTo-NativeArgument`, and read
    back what arrived.
  - A DPI-unaware PowerShell sees window rectangles scaled (1/1.5 at 150%). Call
    `SetProcessDPIAware` before `GetWindowRect`/`SetWindowPos`, or use the toolkit's physical values.
- **A partly off-screen window can look on-screen.** Observed: a chat input at y=1520 on a
  1080-pixel-high screen still reported `IsOffscreen: false`, and the input verb failed only with
  `foreground-activation-failed`, which does not say the target is outside the screen. The
  coordinate verbs check a point against the window rectangle, not the screen, and the toolkit's
  selector click does not check the element against the screen: from reading the source, Windows
  clamps `SetCursorPos` to the screen, so an element centred outside it would be clicked at the
  screen edge (the pointer was seen ending near the bottom row; whether a click was dispatched is
  unverified). Compare the element's `boundingRect` with the monitor's working area before acting,
  and move the window back or ask the user rather than clicking at the edge.
- **Floating tool windows.** `list-windows --pid` also returns undocked tool windows of the same
  process; their titles may lack the product name and they can be listed with `IsModal: true` and an
  owner. When a control is not found in the main window, try every top-level window of that process
  before concluding it is missing.
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
