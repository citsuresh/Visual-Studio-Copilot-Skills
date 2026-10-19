---
name: agent-orchestrator
description: 'Drive and supervise a Copilot chat agent running in a *different* Visual Studio (or VS Insiders) window, via the ui-interaction skill''s AgentDebugToolkit UIA primitives. Use for: attaching to a target VS window, assigning it a task, polling its state cheaply, detecting and answering ChoicePrompt cards vs. plain chat replies, and running the Pre-Build Decomposition -> implement -> Regression Audit -> review -> approve -> commit loop end-to-end as the human-in-the-loop responder. User-level global skill; originated in the OpenWayToolsAndTest-Main / FDM repo but not scoped to it.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 5`. This is this file's own version, used to detect when the globally
  installed copy at `C:\Users\sveluswa\.copilot\skills\agent-orchestrator\SKILL.md` is behind the
  source-of-truth copy in this repo at
  `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\agent-orchestrator\SKILL.md`. Unlike
  `project-memory-management-graph` (which bootstraps many independent target projects and needs
  a per-project marker), this skill has only one installed copy and one source of truth, so no
  per-project marker file is needed — just a direct comparison between the running copy's version
  and the repo copy's version. Bump this integer whenever an edit to this file changes what a step
  actually does.
- Changelog (append one entry per version bump; never delete prior entries):
  - v1 — versioning introduced.
  - v2 — extracted the generic UIA mechanics (AgentDebugToolkit path-fallback, `DOTNET_ROOT`
    gotcha, screenshot cleanup, CLI_CONTRACT reference) into the new **ui-interaction** skill,
    and the debugger-bridge setup notes into the new **vs-debug** skill, since both were
    duplicated near-verbatim with what the (now-retired) `ui-debug-map` skill also documented.
    This skill now composes those two rather than restating their setup; nothing about *how this
    skill orchestrates a Copilot chat session* changed — Steps 1-6 and the anti-patterns below
    are unchanged from v1.
  - v3 — added bundled scripts `Send-CopilotPrompt.ps1`, `Get-CopilotChatTranscript.ps1`,
    `Select-ChoicePromptOption.ps1`, and `Compare-RepoSnapshot.ps1`, and updated
    `Watch-CopilotChat.ps1` for the newer Copilot Chat experience (status text `Working`, no
    `Waiting...` node while a card is open, completion footer, `-RequireWorkingFirst`). Steps 2-5
    now use these scripts. Step 4 no longer selects options with `click --strategy Name` or
    `SelectionItemPattern.Select()`: both were observed submitting a different option than the
    one requested. Added `AgentCursor.ps1` (user request): a blue-dot cursor for the whole
    orchestration session and a red-dot cursor while a script is sending mouse/keyboard input,
    always restored afterwards. Added learned scripts (same idea as project-memory-management-graph
    v15/v16): reusable orchestration code is saved to `scripts\` in the repo copy and indexed in
    `scripts\SCRIPTS.md` without asking, and the user is told; Step 0 reads the index, Step 5 may
    run the target repo's read-only indexed scripts, and the new Step 7 closes the session with a
    retrospective save, an index check and `-Session Stop`. The blue dot is on only while you are
    actively driving or monitoring the target: stop it before every reply that waits for the user,
    start it again when you resume. The input scripts bring the target window to the front with
    `Set-AgentForegroundWindow` (Alt tap plus `SetForegroundWindow`, verified), because
    `agentdebug-ui activate` is blocked by focus-stealing prevention when the caller isn't in front.
    `AgentCursor.ps1` now lives in the **ui-interaction** skill (`ui-interaction\scripts\`) and is
    shared: blue = agent-orchestrator, green = a ui-interaction / ui-navigation-orchestrator run,
    red = input now from either; the first session started owns the colour. Tool permission
    prompts ("Do you allow Copilot to ...?") are a third prompt type: the watcher reports them
    as `PromptKind: "PermissionPrompt"` (they previously looked Idle) and
    `Select-ChoicePromptOption.ps1 -Button` answers them, refusing lasting permissions without
    `-AllowPersistent`. Idle without a completion footer now needs `-IdleWithoutFooterPolls`
    (default 3) stable polls and carries a `Note`; view-model placeholder message names are
    ignored.
  - v4 — Three card and footer fixes from live tests. Multi-question cards show one question per
    page with `Next question` instead of `Submit` until the last page: the watcher reported them as
    Working; it now reports Pending with `MorePages`, and `Select-ChoicePromptOption.ps1` answers one
    page per call (`NextQuestion` names the next page). The workspace trust card ("Do you trust this
    folder?", `Trust once` / `Do not trust`) is reported as `PromptKind: "PermissionPrompt"` with
    only its own buttons; the chat pane's header buttons were listed as options before, and its
    question was empty. The short footer "The response cost <n> credits." now counts as a
    completion footer. Validated live: a two-question card answered page by page, the trust card
    read and answered with `-Button "Trust once"`. A tool permission prompt is still untested live,
    because tools are auto-approved in the test setup. Chat banners: after switching folders in
    the target window, a `HarnessWorkspaceMismatchBanner` ("The open folder is outside this
    session's working directory", `Update working directory` / `Close message`) stayed above the
    input and the watcher reported plain Idle, so a new task would have run in the old folder. The
    watcher now returns `Banners` (Id, Text, Buttons) in every result, and `Send-CopilotPrompt.ps1`
    refuses to send while that banner or `WorkspaceTrustWarningBanner` is shown, unless
    `-IgnoreBanners`. Validated live: both detected the banner; clicking `Update working directory`
    cleared it.
  - v5 — Fixes Step 1's no-pid fallback: discover with `--processName devenv` and the plain
    `--titleContains "Microsoft Visual Studio"` substring, not an unscoped session-pid lookup
    or wildcard pattern. Confirm the returned hwnd and pid and never guess among multiple matches.

# Agent Orchestrator

Supervise a Copilot chat agent that is running inside a *separate* Visual Studio / VS Insiders
window, by driving its chat UI through UIA. This lets you act as the human-in-the-loop responder
for that agent's confirmation prompts, task assignments, and commit approvals — without the
actual user needing to manually click anything.

## Relationship to other skills

This skill composes two lower-level mechanism skills rather than reimplementing them:

- **ui-interaction** — for all UIA mechanics: finding/attaching to windows, clicking, typing/
  pasting text, reading back element state, and the shared `AgentDebugToolkit` setup (portability
  path-fallback, the `DOTNET_ROOT` gotcha, `CLI_CONTRACT.md`, screenshot cleanup). Read that
  skill's `SKILL.md` for anything related to those primitives or the general toolkit setup — it
  is not restated here.
- **vs-debug** — only if a task delegated to the other agent involves debugger automation (e.g.
  breakpoint/wait-for-break verbs). Most orchestration sessions never need this.

What stays here, because it's specific to orchestrating a Copilot chat session and nothing else
covers it: which selectors actually work against the real Copilot Chat control (Step 2),
recognizing and correctly answering a `ChoicePrompt` card versus a plain chat reply (Step 4),
classifying chat state (`Watch-CopilotChat.ps1`, Step 3) and its known unreliability, the
standard decompose -> implement -> audit -> review -> approve -> commit loop (Step 5), and the
independent-verification discipline before approving any commit.

## Bundled scripts

All live in `scripts\` next to this SKILL.md. Each clears `DOTNET_ROOT` itself and accepts
`-ExePath` (or uses .NET UIA directly) — run `Get-Help <script> -Full` for every parameter.
The `.\<script>.ps1` examples in this file assume that `scripts\` folder is the current
directory; otherwise use the full path.

| Script | Use it for | Changes anything? |
| --- | --- | --- |
| `Send-CopilotPrompt.ps1` | Step 2: new session (optional), clear, paste, verify, then Send | Sends a prompt |
| `Watch-CopilotChat.ps1` | Step 3: poll until Pending, Idle, or timeout | No |
| `Get-CopilotChatTranscript.ps1` | Step 3: full text of the latest reply/replies | No |
| `Select-ChoicePromptOption.ps1` | Step 4: answer a `ChoicePrompt` card (verifies the echo) or, with `-Button`, a permission prompt | Clicks (moves the mouse) |
| `Compare-RepoSnapshot.ps1` | Step 5: which files the agent really added/modified/deleted | Writes only the snapshot file |
| `AgentCursor.ps1` (shared, in `ui-interaction\scripts\`) | "Hands off" indicator: blue dot = orchestration session active, red dot = input now | Temporarily swaps system cursors |

**Hands-off cursor indicator (user requirement):**
- `AgentCursor.ps1` belongs to the **ui-interaction** skill, which also uses it (green dot for
  its own multi-step runs). From this skill's `scripts\` folder it is
  `..\..\ui-interaction\scripts\AgentCursor.ps1`; the two input scripts load it from there.
  Below, `AgentCursor.ps1` means that path. This skill always uses the default
  `-Kind Orchestrator` (blue). Never show blue for ordinary work (editing, git, builds) - only
  while orchestrating another chat.
- **Blue dot - session.** Run `AgentCursor.ps1 -Session Start` before Step 1 of an
  orchestration session, and `AgentCursor.ps1 -Session Stop` when it ends - including when it
  ends early or fails. It stays on between script calls within a turn (monitoring, thinking), so
  the user knows not to use the machine.
- **Stop it at every hand-back.** The blue dot means "you are using the machine right now", not
  "a multi-turn test is in progress". Before ending any turn that waits for the user (reporting
  results, asking a question, offering next steps), run `AgentCursor.ps1 -Session Stop`, even
  if the overall session will continue. Run `-Session Start` again as the first action when you
  resume driving or monitoring the target.
- **Red dot - input.** `Send-CopilotPrompt.ps1` and `Select-ChoicePromptOption.ps1` switch to
  red while they activate the window, type, or click, then return to blue (or to the user's
  cursors if no session is active). Any other code that moves the mouse or sends keys must do
  the same: `. <path>\AgentCursor.ps1; Enable-AgentCursor; try { ... } finally { Restore-AgentCursor }`.
  Read-only scripts (`Watch-CopilotChat.ps1`, `Get-CopilotChatTranscript.ps1`,
  `Compare-RepoSnapshot.ps1`) don't change the cursor.
- If a dot is ever left behind, `AgentCursor.ps1 -Restore` clears everything (or the user
  can sign out and back in). A session flag older than 12 hours is ignored.
- Only one session colour shows at a time; the first one started owns it. If `-Session Start`
  reports that a UiAutomation (green) session is already active, it was left behind or another
  run is in progress - say so to the user rather than clearing it.

Prefer these over ad-hoc `agentdebug-ui.exe` calls; the raw commands below are what to fall
back on if a script is missing or fails.

## Learned scripts (saved by the orchestrator, curated by the user)

The table above lists the **core** scripts. Code you write during a session for a repeatable
orchestration step (handling Keep/Undo or a tool-permission prompt, typing a custom card answer,
waiting for a build in the target, scrolling the transcript) is saved next to them, so later
sessions reuse it instead of re-deriving it.

- **Where:** the repo copy, `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\agent-orchestrator\scripts\`
  (the source of truth; `Install-Skills.ps1` copies it to the installed skill). Index:
  `scripts\SCRIPTS.md`, a markdown table: script | purpose | how to call | read-only or
  sends input/modifies | date. Create it with the header the first time a script is saved; never
  as an empty placeholder.
- **Consuming:** before writing code for an orchestration step, check the core table and
  `scripts\SCRIPTS.md`, and run a fitting script from the repo copy. Check its output before
  relying on it.
- **Saving, without asking first:** save only code that (a) is likely to be reused with different
  inputs, (b) is more than a one-liner, (c) takes its inputs as parameters (hwnd, paths, names,
  timeouts - nothing hardcoded), and (d) contains no credentials, tokens, customer data or personal
  details. Name it `<Verb-Noun>.ps1` with a comment-based help header (purpose, parameters,
  whether it sends input or modifies anything). Scripts that type or click must use the red-dot
  cursor (`Enable-AgentCursor` / `Restore-AgentCursor` in `finally`). Add an index line, then tell
  the user in the chat: "Saved/updated script `<name>` - <one-line reason>".
- **Generalize, don't copy:** if an existing learned script can take the new case as a
  backward-compatible parameter (its default keeps the current behaviour), extend it, update its
  index line and date, and say so. Never save a near-copy with one value changed.
- **Boundaries:** core scripts and this SKILL.md are changed only through the repo's skill update
  workflow (temp copy, diff, confirmation) - propose the change instead. Never delete scripts or
  index lines; the user curates. Never commit or push; saved scripts stay uncommitted until the
  user asks. Never save into the target repo's `scripts/agent/` - that belongs to the target
  agent and would pollute the diff you are reviewing.
- **Broken script:** fix it in place and update its date, or do the step manually; never loop on a
  broken script.

## Prerequisites / environment

- Set up `AgentDebugToolkit`, `agentdebug-ui.exe`, and the `DOTNET_ROOT` workaround per the
  **ui-interaction** skill — this skill assumes that's already in place and doesn't restate it.
- Only if the delegated task involves debugger automation: also set up `agentdebug-vs.exe` per
  the **vs-debug** skill.
- Known limitations doc: `C:\MyFiles\Git\AgentDebugToolkit\docs\KNOWN_OPEN_FINDINGS.md`.

## Step 0: Version Check

Run this **once**, at the very start of a new orchestration session — do not repeat it on every
individual verb call (click, inspect, poll, etc.) within that session; it must not get pulled into
Step 3's polling loop. This is a cheap check (one line read from one local file, no UIA calls
involved), so do it every time a new session starts rather than skipping it to save time.

1. Read `CURRENT_SKILL_VERSION` from the repo copy of this file at
   `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\agent-orchestrator\SKILL.md`. Use the same "ask,
   don't guess" fallback documented in `ui-interaction` for the `AgentDebugToolkit` path if this
   repo path doesn't exist on the current machine — stop and ask the user where to find it rather
   than silently skipping the check or assuming a different location.
2. Compare that repo version to this file's own `CURRENT_SKILL_VERSION` (the version of whatever
   copy is currently loaded/running).
3. If the repo's version is higher: tell the user plainly what changed (the changelog entries
   between the running version and the repo's version) and that the installed copy is stale.
   Recommend running `Install-Skills.ps1` before continuing, but let the user decide whether to
   pause and update now or proceed anyway with the current session.
4. If versions match: proceed silently — no need to announce anything.
5. If the repo copy's `scripts\SCRIPTS.md` exists, read it so the learned scripts are in context,
   and mention the count in a few words (e.g. "2 learned scripts indexed").
6. Start the hands-off indicator: `AgentCursor.ps1 -Session Start` (blue dot).

## Step 1 — Find and verify the target window

Using ui-interaction's `list-windows`/`attach` primitive:
```powershell
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue
& $exe list-windows --pid <pid>
```
Confirm `Hwnd`, `Title`, and that the process is still alive. Hwnds can change if the target VS
instance was restarted — never assume a previously-known hwnd is still valid; re-verify at the
start of a new session or after any long gap.

Prefer `--pid` when available. If you don't have a pid, use
`list-windows --processName devenv --titleContains "Microsoft Visual Studio"` and confirm the
returned hwnd and pid before use. `--titleContains` is a substring filter, not a wildcard;
without an explicit scope, `list-windows` uses the session context pid. Do not guess among
multiple matches — ask the user to identify the intended instance.

## Step 2 — Send a task to the agent

Use `Send-CopilotPrompt.ps1`:

```powershell
.\Send-CopilotPrompt.ps1 -Hwnd <h> -NewSession -Text "<task text>"
```

It activates the window, optionally starts a new session, clears the input, pastes, and reads it
back. It clicks Send **only** if the input matches the prompt exactly, and retries otherwise
(stray keystrokes typed into the window during a paste were observed being sent along with the
prompt). `Sent: false` means nothing was sent — read `Error` and `InputText`. Omit `-NewSession`
to reply in the current conversation. It also refuses, before typing anything, while the chat
shows a working-directory mismatch or untrusted-workspace banner (see Step 4); don't pass
`-IgnoreBanners` unless the user agreed. The raw equivalent, for fallback:

Prefer **clipboard paste over synthetic typing** for reliability with longer text (user
preference, confirmed this session):

```powershell
& $exe type --hwnd <h> --strategy Name --value "Ask Copilot" --text "<task text>" --paste --verify
```

- `--strategy Name --value "Ask Copilot"` targets the chat input via its placeholder Name (shown
  only when the chat box is empty). This is currently the only reliable selector for the real
  Copilot Chat input/Send button, because they expose no `AutomationId` — `AutomationId=WpfTextView`
  is ambiguous (resolves to either the chat input or the code editor pane depending on UIA
  traversal/focus state). This is a fact about this specific control, not a generic
  ui-interaction gotcha, so it's recorded here rather than there.
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
change to the other. It classifies state from the UIA tree (NOT by button-name heuristics like
"does a Cancel button exist" — a `ChoicePrompt` card also has its own Cancel button, so that check
alone false-positives as WORKING when the agent is actually PENDING on your input; this was
observed and corrected mid-session):

- **Pending** — a `"Waiting..."` node, or an open card (a `RadioFieldLabel`/`FormField` element
  plus a `Submit` button, or an enabled `Next question` button on a multi-question card). The newer
  Copilot Chat experience has no `"Waiting..."` node and keeps
  showing `Working` while a card is open, so the card check is what catches Pending there. A
  tool permission prompt (`"Do you allow Copilot to ...?"` with `Allow this time` / `Deny`
  buttons) is also Pending, with `PromptKind: "PermissionPrompt"`; while one is open the chat
  shows no `Working` text at all. A workspace trust card (`"Do you trust this folder?"` with
  `Trust once` / `Do not trust`, shown when the target window opens an untrusted folder) is
  reported the same way; chat is disabled until it is answered.
- **Working** — a `"Working on it..."` or `"Working"` node (the shorter label is the newer
  experience). Pass `-WorkingMarkers` if a Visual Studio update changes the text again.
- **Idle** — neither. Confirmed at once when a new completion footer
  (`"The response used the <model> model..."`, or the short `"The response cost <n> credits."`)
  appears after the reply, after 2 stable polls
  when the last message is a footer, or after `-IdleWithoutFooterPolls` (default 3) when it is
  not. An Idle result without a footer has a `Note`: read the transcript and inspect for an
  unrecognized prompt before trusting it.

Prefer this script over rolling your own ad-hoc polling loop. Right after sending a prompt or
answering a card, pass `-RequireWorkingFirst` so the previous reply isn't reported as Idle before
the agent starts; after `-StartGraceSeconds` (default 30) it accepts Idle anyway, for replies
that finish before the first poll (`WorkingSeen: false` in the result tells you that happened).

```powershell
.\Watch-CopilotChat.ps1 -Hwnd 0x691588 -RequireWorkingFirst -TimeoutSeconds 300 -PollIntervalSeconds 12
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
   `stop_powershell`, then independently re-inspect (`Get-CopilotChatTranscript.ps1`) or check
   `git status`/`git log` right away, rather than sleeping through another full poll cycle just to
   watch the script confirm what you can already see. The script's stability requirement exists to
   avoid false positives from momentary UI flicker, but a caller who's actively watching can (and
   should) verify directly instead of waiting idle.

If missing entirely, recreate it: loop `inspect --hwnd <h> --maxDepth 20-25`, classify state by
the rules above (Pending, then Working, otherwise Idle), sleep ~12-15s between polls (start short right
after you respond, back off gradually, cap around 60s — don't leave long gaps once a response has
just been sent, since the agent may finish or hit a prompt quickly).

**Reading the reply:** the watcher's `LastMessage` is now the last non-footer message in document
order (it was previously often stale), but it is cut at `-MaxMessageLength`. For the full text —
for example a long tool-call trace — use:
```powershell
.\Get-CopilotChatTranscript.ps1 -Hwnd <h> -AsText            # latest reply
.\Get-CopilotChatTranscript.ps1 -Hwnd <h> -Last 0 -IncludeFooter  # every rendered message
```
It reads `inspect`, not `read-visible-text`, because `read-visible-text` cuts each value at 2000
characters (a Test-3 trace was truncated that way). The chat list is virtualized: only rendered
messages are returned, so scroll the chat if an older one is missing.

**Transient noise:** occasional `{"success":false,"error":"unhandled-exception","message":"Element
does not exist or it is virtualized..."}` responses from `inspect` are a transient UIA
virtualization race — simply retry, don't treat as a real failure.

## Step 4 — Detect and answer prompts correctly

Three distinct interaction shapes exist. Getting this wrong causes confusion (plain-text replies
landing while a card is still pending, `element-not-found`/`stale-context` errors):

1. **Plain chat question** (no card) — reply with `Send-CopilotPrompt.ps1` (no `-NewSession`).
2. **`ChoicePrompt` card** (radio-button options, e.g. Pre-Build Decomposition approval,
   multiple-choice questions) — use `Select-ChoicePromptOption.ps1`:
   ```powershell
   .\Select-ChoicePromptOption.ps1 -Hwnd <h>                                # list options only
   .\Select-ChoicePromptOption.ps1 -Hwnd <h> -Option "<exact option text>"  # select + Submit
   ```
   It clicks the exact `RadioButton` with a real mouse click, invokes `Submit`, and reads the
   `"User entered: ..."` echo (appended to the question text). `Success: true` means the echo
   names exactly the requested option; anything else is reported in `Error`, including
   `Wrong option submitted`. It moves the mouse, so keep hands off while it runs.

   **Multi-question cards** show one question per page, with `Next question` instead of `Submit`
   until the last page; the watcher reports `MorePages: true`. Call the script once per page: on a
   page with more to come it selects the option, clicks `Next question`, checks that the question
   changed, and returns `CardClosed: false` with `NextQuestion` set. The last call submits, and its
   echo lists every answer. Do not reply in the chat box while a later page is still open.

   **Why not the CLI or UIA select:** `SelectionItemPattern.Select()` marks the radio selected
   but the newer card still submitted its previous choice (asked for Option 2, card echoed
   Option 1). And `click --strategy Name` hits `ambiguous-match` (the RadioButton and its
   TextBlock share a Name) or the ToolTip gotcha below. If the script is unavailable, the raw
   fallback still **requires two clicks, not one**:
   ```powershell
   & $exe click --hwnd <h> --strategy Name --value "<exact option text>"
   & $exe click --hwnd <h> --strategy Name --value Submit
   ```
   Selecting the radio button by `Name` only *selects* it — the card is not dismissed/submitted
   until the separate `Submit` button (found via `--strategy Name --value Submit`) is clicked.
   Missing this second click is the single most common mistake when operating this skill.

   To detect a pending `ChoicePrompt`, rely on the polling script's `State: "Pending"` /
   `PromptKind: "ChoicePrompt"` result, or look for a `RadioFieldLabel` plus a `Submit` button in
   a fresh `inspect`. Ignore `Like`/`Dislike` radio buttons — they belong to completion footers.

   **Known gotcha — the option click can silently mis-resolve or mis-select:** `click --strategy
   Name --value "<exact option text>"` sometimes reports `"method":"synthetic-click"` against a
   `ToolTip` element (not the actual `RadioButton`) instead of failing outright, and in that case
   it can end up selecting a *different* radio option than the one requested (observed twice in a
   single session: once selecting a neighboring option, once toggling the wrong choice entirely).
   A successful-looking JSON response (`"success":true`) is **not sufficient proof the intended
   option was selected** — this is the same "don't trust success:true" discipline ui-interaction
   states generically, applied here to the specific case of confirming the *right* option landed,
   not just that *some* click succeeded. When using the raw fallback, always re-verify after the
   two-click submit:
   ```powershell
   & $exe inspect --hwnd <h> --maxDepth 20
   ```
   Check that `Submit`/the radio group is gone (card dismissed) and, via the last chat message(s)
   or a `"User entered: ..."`-style echo, confirm the option that actually got submitted matches
   what was intended. If it picked the wrong option, don't panic — assess whether the agent's
   resulting path is still reasonable (it may self-correct, as observed once) before deciding
   whether to redirect it with a plain-text follow-up.
3. **Tool permission prompt** (`"Do you allow Copilot to read files from ...?"` with
   `Allow this time`, `More confirmation options` and `Deny` buttons; the watcher reports
   `PromptKind: "PermissionPrompt"` with the question and button names) — use:
   ```powershell
   .\Select-ChoicePromptOption.ps1 -Hwnd <h> -Button "Allow this time"
   ```
   It invokes that exact button (red dot) and checks the prompt closed. Choose
   `Allow this time` only when the request is clearly needed for the task you sent (e.g. the
   agent reading its own installed skill files); for anything else — writes outside the target
   repo, network access, unexpected paths — stop and ask the user. Never pick a lasting
   permission (`always`, session- or solution-wide; refused unless `-AllowPersistent`) unless
   the user asked for it. Don't type into the chat box to answer it.

   A **workspace trust card** (`"Do you trust this folder?"`, `Trust once` / `Do not trust`) is
   answered the same way, with `-Button`. `Trust once` lets the agent read files and run tools in
   that folder for the session, so always ask the user before choosing it. `Do not trust` leaves
   chat disabled in that window.

   **Chat banners** are not prompts: the agent isn't waiting, and the watcher can report Idle
   while one is shown. Check `Banners` in the watcher result before sending a task. A
   `HarnessWorkspaceMismatchBanner` ("The open folder is outside this session's working
   directory", with both paths) means a new session would run in the old folder, typically after
   the target window switched folders. If the open folder is the intended target, click
   `Update working directory` (`click --strategy AutomationId --value HarnessWorkspaceMatch`,
   with the red dot) and re-run the watcher to confirm `Banners` is empty; otherwise ask the user.
   Don't just close the banner.

## Step 5 — Run the standard collaboration loop

For any implementation task assigned to the other agent, expect and drive this pattern
(consistent with how Phases 15-19 of AgentDebugToolkit itself were completed):

1. Send the task, including a request for a **Pre-Build Decomposition** (a proposed breakdown
   into parts, presented as a `ChoicePrompt`) before it starts implementing. Take a file
   snapshot of the target repo first:
   `.\Compare-RepoSnapshot.ps1 -Mode Snap -Path <repo> -SnapshotFile <file outside the repo>`.
2. Review the proposed decomposition; approve via Step 4, or push back with a
   plain-text reply if changes are needed first.
3. Poll (Step 3) while the agent implements and self-runs a **Regression Audit**.
4. When the agent reports audit results (usually another `ChoicePrompt`, e.g. "audit clean,
   proceed?" or "found N issues, fix them?"), review the findings on their merits before
   approving.
5. **Before approving any commit**, independently verify — do not just trust the chat transcript:
   - `git status --short` / `git diff --stat` in the target repo to see actual changed files.
   - `.\Compare-RepoSnapshot.ps1 -Mode Diff -Path <repo> -SnapshotFile <same file>` to catch
     changes `git status` hides (ignored files) or that were already dirty before the task.
   - View the real diff content for anything non-trivial.
   - If the target repo has `docs/SCRIPTS.md`, you may run its scripts that are marked read-only
     to check the agent's claims (never ones that modify files without asking the user).
   - Rebuild (`dotnet build`, clearing `DOTNET_ROOT` first) and confirm 0 warnings/0 errors.
   - For nuget/restore-related changes, force a fresh restore (delete `obj/`, `dotnet restore`)
     rather than trusting an incremental "up-to-date" restore.
6. Approve the final commit/push via Step 4.
7. Confirm the commit landed: `git log --oneline -n <few>` and `git log origin/main..HEAD
   --oneline` (empty output = fully pushed/synced).

## Step 6 — Track and close out backlog items

If working through a list of open items/findings (e.g. `docs/PROJECT_STATE.md`,
`docs/KNOWN_OPEN_FINDINGS.md` in the target repo), update those docs as items are resolved so
future sessions don't need to re-derive status. Prefer committing doc updates in the same or an
immediately-following commit as the fix itself, with clear commit messages referencing the
phase/finding.

## Step 7 — Close the session

Run this when the orchestration session ends, including when it ends early or fails:

1. **Retrospective save.** Using only what is still visible in this session's context, check
   whether you wrote working code for a repeatable orchestration step that wasn't saved; if it
   passes the save test in "Learned scripts", save or extend a script and tell the user. Also
   note (don't apply) any core-script or SKILL.md improvement the session showed, as a proposal.
2. **Index check**, only if `scripts\SCRIPTS.md` exists: every index line points to an existing
   file (`Test-Path`), and every non-core `.ps1` in `scripts\` has an index line. Add a missing
   line for an unlisted learned script; report anything else and change nothing.
3. **Clear the indicator:** `AgentCursor.ps1 -Session Stop`.
4. Report in a few lines: scripts saved/updated, mismatches, proposals. Skip any part with
   nothing to say.

## Anti-patterns to avoid

- Don't respond to a pending `ChoicePrompt` by typing into the chat box — it will not register
  as the card's answer and can leave the conversation in a confusing half-state.
- Don't skip the `Submit` click after selecting a radio option.
- Don't select card options with `SelectionItemPattern.Select()` — the card can still submit a
  different option. Use `Select-ChoicePromptOption.ps1`, which clicks and checks the echo.
- Don't run an orchestration session without the blue-dot indicator, don't send mouse/keyboard
  input without the red one, and never leave either on - `-Session Stop` at the end and before
  every reply that waits for the user, and `Restore-AgentCursor` in a `finally` block.
- Don't re-derive orchestration code that a core or learned script already covers, and don't
  save a near-copy of a learned script - extend it with a parameter.
- Don't trust a `"success":true` response from the option-selection click as proof the *correct*
  option was selected — re-inspect after submitting to confirm (see Step 4's gotcha note).
- Don't trust `LastMessage`/chat-transcript claims about code changes without independently
  checking the actual files/git diff.
- Don't assume a previously-known hwnd/pid is still valid across a long gap — re-verify.
- Don't use `AutomationId=WpfTextView` for the chat input — it's ambiguous; use
  `--strategy Name --value "Ask Copilot"` for input, `--strategy AutomationId --value SendButton`
  for Send.
