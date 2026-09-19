---
name: agent-orchestrator
description: 'Drive and supervise a Copilot chat agent running in a *different* Visual Studio (or VS Insiders) window via AgentDebugToolkit''s UIA CLI (agentdebug-ui.exe). Use for: attaching to a target VS window, assigning it a task, polling its state cheaply, detecting and answering ChoicePrompt cards vs. plain chat replies, and running the Pre-Build Decomposition -> implement -> Regression Audit -> review -> approve -> commit loop end-to-end as the human-in-the-loop responder. User-level global skill; originated in the OpenWayToolsAndTest-Main / FDM repo but not scoped to it.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 1`. This is this file's own version, used to detect when the globally
  installed copy at `C:\Users\sveluswa\.copilot\skills\agent-orchestrator\SKILL.md` is behind the
  source-of-truth copy in this repo at
  `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\agent-orchestrator\SKILL.md`. Unlike
  `project-memory-management-graph` (which bootstraps many independent target projects and needs
  a per-project marker), this skill has only one installed copy and one source of truth, so no
  per-project marker file is needed — just a direct comparison between the running copy's version
  and the repo copy's version. Bump this integer whenever an edit to this file changes what a step
  actually does. Started fresh at v1; no changelog was reconstructed for changes made before this
  versioning system existed.
- Changelog (append one entry per version bump; never delete prior entries):
  - v1 — versioning introduced (this entry itself).

# Agent Orchestrator

Supervise a Copilot chat agent that is running inside a *separate* Visual Studio / VS Insiders
window, by driving its chat UI through UIA (via `agentdebug-ui.exe` from
`C:\MyFiles\Git\AgentDebugToolkit`). This lets you act as the human-in-the-loop responder for
that agent's confirmation prompts, task assignments, and commit approvals — without the actual
user needing to manually click anything.

## Prerequisites / environment

- **Portability note:** this skill assumes `C:\MyFiles\Git\AgentDebugToolkit` is a specific,
  hardcoded local clone of the AgentDebugToolkit repo on this machine — it is not a portable
  path. If that folder doesn't exist at all (e.g. a different machine, a fresh environment, or
  the clone was moved/removed), stop and ask the user where they'd like to check it out (do not
  guess a path or silently fall back to a different one). The repo's remote is
  `https://github.com/citsuresh/AgentDebugToolkit.git` — if the user confirms they don't have a
  local clone yet, offer to `git clone` it to a location of their choosing, then proceed using
  that path for the remainder of the session (the skill's hardcoded paths above are just the
  default/most-recently-known location, not a requirement).
- Tool: `agentdebug-ui.exe`, built from `C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli`.
  Default build output path:
  `C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe`
  If it doesn't exist, build it first: `dotnet build` in that project folder (after clearing
  `DOTNET_ROOT`, see below).
- **CRITICAL environment gotcha:** always run
  `Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue`
  before invoking `agentdebug-ui.exe` or `dotnet build`/`dotnet restore` in a fresh PowerShell
  process. VS's inherited `DOTNET_ROOT` env var breaks both.
- Tool (only if the delegated task involves debugger automation, e.g. Phase 20's breakpoint/
  wait-for-break verbs): `agentdebug-vs.exe`, built from
  `C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.Debugger.VisualStudio`. Default build
  output path:
  `C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.Debugger.VisualStudio\bin\Debug\net8.0-windows\agentdebug-vs.exe`
  If it doesn't exist, build it first the same way as `agentdebug-ui.exe` (clear `DOTNET_ROOT`
  first, then `dotnet build` in that project folder, or `dotnet build AgentDebugToolkit.slnx` for
  the whole solution). This is a separate CLI/process from `agentdebug-ui.exe` — it drives Visual
  Studio's debugger via EnvDTE COM, not the chat UI via UIA; you won't need it unless you're
  independently verifying or exercising debugger-automation verbs yourself.
- Full verb contract: `C:\MyFiles\Git\AgentDebugToolkit\docs\CLI_CONTRACT.md`. Read this if a verb
  behaves unexpectedly — do not guess at flags.
- Known limitations doc: `C:\MyFiles\Git\AgentDebugToolkit\docs\KNOWN_OPEN_FINDINGS.md`.
- **Screenshot cleanup is the caller's responsibility.** `inspect --screenshot true` saves to
  `%LOCALAPPDATA%\AgentDebugToolkit\screenshots\` and returns the path in `screenshotPath` — the
  CLI does not delete these automatically. Delete the screenshot files you generate during a
  polling/verification session once you're done with them, rather than leaving them to accumulate.

## Step 0: Version Check

Run this **once**, at the very start of a new orchestration session — do not repeat it on every
individual verb call (click, inspect, poll, etc.) within that session; it must not get pulled into
Step 3's polling loop. This is a cheap check (one line read from one local file, no UIA calls
involved), so do it every time a new session starts rather than skipping it to save time.

1. Read `CURRENT_SKILL_VERSION` from the repo copy of this file at
   `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\agent-orchestrator\SKILL.md`. Use the same "ask,
   don't guess" fallback already used for the `AgentDebugToolkit` path above if this path doesn't
   exist on the current machine (e.g. a different machine, a fresh environment, or the repo was
   moved/removed) — stop and ask the user where to find it rather than silently skipping the check
   or assuming a different location.
2. Compare that repo version to this file's own `CURRENT_SKILL_VERSION` (the version of whatever
   copy is currently loaded/running).
3. If the repo's version is higher: tell the user plainly what changed (the changelog entries
   between the running version and the repo's version) and that the installed copy is stale.
   Recommend running `Install-Skills.ps1` before continuing, but let the user decide whether to
   pause and update now or proceed anyway with the current session.
4. If versions match: proceed silently — no need to announce anything.

## Step 1 — Find and verify the target window

```powershell
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue
& $exe list-windows --pid <pid>
```
Confirm `Hwnd`, `Title`, and that the process is still alive. Hwnds can change if the target VS
instance was restarted — never assume a previously-known hwnd is still valid; re-verify at the
start of a new session or after any long gap.

If you don't have a pid, ask the user, or use `list-windows` without `--pid` and match by title
(e.g. `"* - Microsoft Visual Studio*"`).

## Step 2 — Send a task to the agent

Prefer **clipboard paste over synthetic typing** for reliability with longer text (user
preference, confirmed this session):

```powershell
& $exe type --hwnd <h> --strategy Name --value "Ask Copilot" --text "<task text>" --paste --verify
```

- `--strategy Name --value "Ask Copilot"` targets the chat input via its placeholder Name (shown
  only when the chat box is empty). This is currently the only reliable selector for the real
  Copilot Chat input/Send button, because they expose no `AutomationId` — `AutomationId=WpfTextView`
  is ambiguous (resolves to either the chat input or the code editor pane depending on UIA
  traversal/focus state).
- `--paste` avoids issues with special characters/newlines that synthetic typing can mangle.
- `--verify` confirms the text landed (skipped automatically for synthetic-keyboard-only controls
  — this is expected, not a bug).
- **Never embed literal newlines in `--text`** — `type`/`submit-chat-message` reject embedded
  `\n`/`\r` with `invalid-argument` by design (Phase 9). Compose the task as a single logical
  paragraph.

Then click Send:
```powershell
& $exe click --hwnd <h> --strategy AutomationId --value SendButton
```
(`SendButton`'s `AutomationId` IS reliable, unlike the input.)

## Step 3 — Poll for state (Working / Pending / Idle)

Use the reusable script, bundled with this skill at
`scripts\Watch-CopilotChat.ps1` (next to this SKILL.md — always available even if
`C:\MyFiles\Git\AgentDebugToolkit` isn't cloned/up to date). It's also committed in that repo at
`tools\Watch-CopilotChat.ps1`; the two should be kept in sync — if you improve one, copy the
change to the other. It classifies state correctly by looking for literal `"Waiting..."` /
`"Working on it..."` text nodes in the UIA tree (NOT by button-name heuristics like "does a Cancel
button exist" — a `ChoicePrompt` card also has its own Cancel button, so that check alone
false-positives as WORKING when the agent is actually PENDING on your input; this was observed and
corrected mid-session). Prefer this script over rolling your own ad-hoc polling loop.

```powershell
.\Watch-CopilotChat.ps1 -Hwnd 0x691588 -TimeoutSeconds 300 -PollIntervalSeconds 12
```

**Run it asynchronously (`mode="async"`), not synchronously, so progress can be relayed to the
user while it's still running** — a sync call only surfaces output after the whole script
returns (or times out), leaving the user with no visibility for minutes at a time. Instead:
1. Start the script with the `powershell` tool using `mode="async"` (short `initial_wait`, e.g.
   15-20s).
2. Call `read_powershell` repeatedly (delay ~20-30s each) to pull the accumulated `[poll #N ...]`
   lines emitted so far.
3. After each `read_powershell`, report the latest poll line(s) to the user in your response,
   **including the sleep duration until the next poll** (e.g. "poll #2: still WORKING, sleeping
   17s until poll #3") so the user knows how long the next wait is, not just that you're waiting
   again.
4. **As soon as a poll line shows `state=IDLE` (even at `idle-stability=1`, before the script's own
   2-consecutive-poll confirmation), stop waiting on the script and act immediately** — call
   `stop_powershell`, then independently re-inspect (`inspect --hwnd <h> --maxDepth 25`) or check
   `git status`/`git log` right away, rather than sleeping through another full poll cycle just to
   watch the script confirm what you can already see. The script's stability requirement exists to
   avoid false positives from momentary UI flicker, but a caller who's actively watching can (and
   should) verify directly instead of waiting idle.

If missing entirely, recreate it: loop `inspect --hwnd <h> --maxDepth 20-25`, classify state by
presence of a `"Waiting..."` text node (Pending), a `"Working on it..."` text node with no
`"Waiting..."` node (Working), or neither (Idle), sleep ~12-15s between polls (start short right
after you respond, back off gradually, cap around 60s — don't leave long gaps once a response has
just been sent, since the agent may finish or hit a prompt quickly).

**Known unreliability:** `Watch-CopilotChat.ps1`'s `LastMessage` field is frequently **stale**
even when `State: Idle` is correctly detected. Do not trust it at face value. Reliable fallback:
after Idle is detected, run a fresh `inspect --hwnd <h> --maxDepth 25`, regex-extract
`"Name":"..."` values longer than ~50-80 chars, and take the last few unique matches as the true
latest message(s):
```powershell
... | Select-String -Pattern '"Name":"([^"]{50,})"' -AllMatches |
  ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } |
  Select-Object -Unique | Select-Object -Last 3
```

**Transient noise:** occasional `{"success":false,"error":"unhandled-exception","message":"Element
does not exist or it is virtualized..."}` responses from `inspect` are a transient UIA
virtualization race — simply retry, don't treat as a real failure.

## Step 4 — Detect and answer prompts correctly

Two distinct interaction shapes exist. Getting this wrong causes confusion (plain-text replies
landing while a card is still pending, `element-not-found`/`stale-context` errors):

1. **Plain chat question** (no card) — reply via Step 2's `type --paste` + Send-button click.
2. **`ChoicePrompt` card** (radio-button options, e.g. Pre-Build Decomposition approval,
   multiple-choice questions) — **THIS REQUIRES TWO CLICKS, NOT ONE:**
   ```powershell
   & $exe click --hwnd <h> --strategy Name --value "<exact option text>"
   & $exe click --hwnd <h> --strategy Name --value Submit
   ```
   Selecting the radio button by `Name` only *selects* it — the card is not dismissed/submitted
   until the separate `Submit` button (found via `--strategy Name --value Submit`) is clicked.
   Missing this second click is the single most common mistake when operating this skill.

   To detect a pending `ChoicePrompt`, look for radio-button-like Name matches plus a `Submit`
   button in a fresh `inspect` — or rely on the polling script's `PromptKind: "ChoicePrompt"`
   classification if using `Watch-CopilotChat.ps1`.

   **Known gotcha — the option click can silently mis-resolve or mis-select:** `click --strategy
   Name --value "<exact option text>"` sometimes reports `"method":"synthetic-click"` against a
   `ToolTip` element (not the actual `RadioButton`) instead of failing outright, and in that case
   it can end up selecting a *different* radio option than the one requested (observed twice in a
   single session: once selecting a neighboring option, once toggling the wrong choice entirely).
   A successful-looking JSON response (`"success":true`) is **not sufficient proof the intended
   option was selected**. Always re-verify after the two-click submit:
   ```powershell
   & $exe inspect --hwnd <h> --maxDepth 20
   ```
   Check that `Submit`/the radio group is gone (card dismissed) and, via the last chat message(s)
   or a `"User entered: ..."`-style echo, confirm the option that actually got submitted matches
   what was intended. If it picked the wrong option, don't panic — assess whether the agent's
   resulting path is still reasonable (it may self-correct, as observed once) before deciding
   whether to redirect it with a plain-text follow-up.

## Step 5 — Run the standard collaboration loop

For any implementation task assigned to the other agent, expect and drive this pattern
(consistent with how Phases 15-19 of AgentDebugToolkit itself were completed):

1. Send the task, including a request for a **Pre-Build Decomposition** (a proposed breakdown
   into parts, presented as a `ChoicePrompt`) before it starts implementing.
2. Review the proposed decomposition; approve via Step 4's two-click pattern, or push back with a
   plain-text reply if changes are needed first.
3. Poll (Step 3) while the agent implements and self-runs a **Regression Audit**.
4. When the agent reports audit results (usually another `ChoicePrompt`, e.g. "audit clean,
   proceed?" or "found N issues, fix them?"), review the findings on their merits before
   approving.
5. **Before approving any commit**, independently verify — do not just trust the chat transcript:
   - `git status --short` / `git diff --stat` in the target repo to see actual changed files.
   - View the real diff content for anything non-trivial.
   - Rebuild (`dotnet build`, clearing `DOTNET_ROOT` first) and confirm 0 warnings/0 errors.
   - For nuget/restore-related changes, force a fresh restore (delete `obj/`, `dotnet restore`)
     rather than trusting an incremental "up-to-date" restore.
6. Approve the final commit/push via the two-click pattern.
7. Confirm the commit landed: `git log --oneline -n <few>` and `git log origin/main..HEAD
   --oneline` (empty output = fully pushed/synced).

## Step 6 — Track and close out backlog items

If working through a list of open items/findings (e.g. `docs/PROJECT_STATE.md`,
`docs/KNOWN_OPEN_FINDINGS.md` in the target repo), update those docs as items are resolved so
future sessions don't need to re-derive status. Prefer committing doc updates in the same or an
immediately-following commit as the fix itself, with clear commit messages referencing the
phase/finding.

## Anti-patterns to avoid

- Don't respond to a pending `ChoicePrompt` by typing into the chat box — it will not register
  as the card's answer and can leave the conversation in a confusing half-state.
- Don't skip the `Submit` click after selecting a radio option.
- Don't trust a `"success":true` response from the option-selection click as proof the *correct*
  option was selected — re-inspect after submitting to confirm (see Step 4's gotcha note).
- Don't trust `LastMessage`/chat-transcript claims about code changes without independently
  checking the actual files/git diff.
- Don't assume a previously-known hwnd/pid is still valid across a long gap — re-verify.
- Don't use `AutomationId=WpfTextView` for the chat input — it's ambiguous; use
  `--strategy Name --value "Ask Copilot"` for input, `--strategy AutomationId --value SendButton`
  for Send.
