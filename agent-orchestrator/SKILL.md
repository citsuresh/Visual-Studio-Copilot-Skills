---
name: agent-orchestrator
description: 'Drive and supervise a Copilot chat agent running in a *different* Visual Studio (or VS Insiders) window, via the ui-interaction skill''s AgentDebugToolkit UIA primitives. Use for: attaching to a target VS window, assigning it a task, polling its state cheaply, detecting and answering ChoicePrompt cards vs. plain chat replies, and running the Pre-Build Decomposition -> implement -> Regression Audit -> review -> approve -> commit loop end-to-end as the human-in-the-loop responder. User-level global skill; not scoped to any one repo.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 35`. This is this file's own version, used to detect when the globally
  installed copy at `%USERPROFILE%\.copilot\skills\agent-orchestrator\SKILL.md` is behind the
  source-of-truth copy in this repo at
  `<skills repo>\agent-orchestrator\SKILL.md` (the clone path is in
  `%USERPROFILE%\.copilot\skills-source.json`, see Step 0) or behind that clone's
  GitHub upstream. Unlike
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
  - v6 — Lessons from a long supervised run. `Watch-CopilotChat.ps1` returns `AwaitingReply` (and
    a `Note`) when an Idle chat ends with a plain-text question or approval request, because the
    agent asked and stopped and Idle alone looks like "finished"; adds `-ProgressFile`,
    `-NotifyOnDone` and `-QuestionPattern`; the default `-MaxPollIntervalSeconds` is 30 (was 60),
    so a finished reply is noticed sooner. `Send-CopilotPrompt.ps1` adds `-TitleContains` (look
    the window up by title, since an hwnd goes stale when Visual Studio restarts), says so when
    the window no longer exists, and adds `-Quiet` (do not echo the prompt back on success).
    `-TitleContains` fails with the candidate list when several windows match, and with a plain
    "no window" message when none does; a failed window listing is reported as such.
    New Step 2 briefing template and two gotchas (commit-message encoding in Windows PowerShell
    5.1, stale git lock files). Checked: failure paths of the Send script (no args, no match,
    several matches, stale hwnd, nothing typed in each), the progress file and beep in the Watch
    script, and `QuestionPattern` against real replies. Not run live: a successful `-Quiet` send
    and an `AwaitingReply` result from a real chat.
  - v7 — `Send-CopilotPrompt.ps1` finds the chat itself. When the chat input is not showing it
    selects the `Chat` tab (in a window where Chat and Git Changes share a pane, the chat is not
    rendered while Git Changes is the active tab), and if the pane then shows only the session
    list it creates a new session; `-NoNavigate` turns this off. The banner check now runs after
    that, because banners only render while the chat is visible. A new session now gets up to 30s
    to show its input (it took longer than the old 10s). Since v6 these were run live: a
    successful `-Quiet` send, `-TitleContains`, `LastMessageTail`, and an `AwaitingReply` result
    (a false alarm, see Step 3). Not run live: the new navigation. Two attempts to hide the chat
    and watch the script recover were defeated by the window losing the foreground, so v7's
    navigation is covered by a parse check and code review only; test it before relying on it.
  - v8 — The two watcher scripts are now `Watch-CopilotChatV1.ps1` (the old `Watch-CopilotChat.ps1`,
    full UI tree per poll) and `Watch-CopilotChatV2.ps1` (the old `Wait-CopilotChat.ps1`, one small
    probe per poll). Use V2 by default; each script's header lists its pros and cons. V1 stays for
    what V2 does not return: the question and options of a Pending prompt, plain-text question
    detection (`AwaitingReply`), banners. `Invoke-CopilotReview.ps1`'s `-Poller` values are now `V2`
    (default) and `V1`. There is no unversioned `Watch-CopilotChat.ps1` any more; anything that
    called it must use a versioned name. Not run live after the rename: only parse checks and a
    reference search. The copy at `tools\Watch-CopilotChat.ps1` in the AgentDebugToolkit repo is
    the old V1 and is not renamed yet.
  - v9 — The end-of-wait signal is now the Windows `tada` sound (`Media\tada.wav`, with a beep as the
    fallback) instead of beeps, in `Watch-CopilotChatV1.ps1` (`-NotifyOnDone`), `Watch-CopilotChatV2.ps1` and
    `Invoke-CopilotReview.ps1` (`-NoBeep` silences it). It plays when a background chat is done or needs
    the person (a prompt or question is waiting), so someone working in another window hears it. The
    sound plays on the machine running the script; a Claude mobile client does not receive it.
  - v10 — Reverts v9's sound change. When the supervised agent finishes or needs the person, the
    scripts (`Watch-CopilotChatV1.ps1` `-NotifyOnDone`, `Watch-CopilotChatV2.ps1`,
    `Invoke-CopilotReview.ps1`) beep again, as before v9. The `tada` sound is reserved for the
    orchestrating Claude finishing its own task for the user and is not played by these scripts.
  - v11 - `Watch-CopilotChatV2.ps1` fixed and extended. A live card test found that V2 never saw a
    question card: the card is a message in the chat list, which V2 did not search, the list ends with an
    empty placeholder item, and the list's scroll percentage stops short of 100. V2 now searches the last
    three real messages while the list is within 10 percent of its end, and skips trailing placeholders for
    the completion footer. It also returns V1's details (question, options, banners, `AwaitingReply`,
    last message) by running V1 once when the wait ends (`-NoDetail` skips it, `-ExePath` points at
    agentdebug-ui.exe), and upgrades Idle to Pending if the full tree shows a prompt the light probe missed.
    Test cases for the watchers and the other scripts are now in `scripts\tests\`. Verified live on
    2026-10-31: single, two-question and free-text cards, plain-text question, normal reply, NotVisible,
    WindowGone, Timeout, missing exe, NoDetail, `Select-ChoicePromptOption.ps1` on all card types. Not run:
    permission prompt, banners, the Upgraded path, a card above a scrolled-up view.
  - v12 - `Watch-CopilotChatV2.ps1` returns `ChatSwitched` when the visible chat is no longer the one
    being watched. It watches whichever chat is visible, so clicking New chat mid-task used to end with a false
    Idle while the first chat kept working. It now keeps the session title from the chat pane header and
    fires when the title changes, the stop button is gone and there is no completion footer (a rename while
    busy or after a footer is followed silently). `Invoke-CopilotReview.ps1` returns NoReply for it. Verified
    live on 2026-10-31 (switch at t=12 s detected at 17 s; a normal send into a new session stayed Idle). A
    missing or shared title cannot be detected: always confirm the reply with `Read-CopilotReply.ps1`.
  - v13 - Three fixes to `Invoke-CopilotReview.ps1` found by live test cases (2026-11-01). The draft guard never
    worked: it looked for an element named `Ask Copilot` (the input box itself, present with or without text), so
    a draft in the input was overwritten; it now reads the Send button (enabled only when the input holds text). The
    reference tag appended to each prompt was 8 hex digits and Copilot treated it as a git commit; it is now
    letters only (`msg-xxxxxxxx`). A complete reply could end as `NoReply` / `ReadNotConfirmed` when the list
    scroll position stopped short of the end; `Read-CopilotReply.ps1` now reports `NearEnd` and the wrapper returns
    Done with a caveat in Reason once the footer was read. Live results for Send-CopilotPrompt S-07 to S-10 and
    Invoke-CopilotReview IR-02 to IR-07 are in scripts\tests (all pass; a first run of S-09, S-10 and IR-02 failed
    because of a mistake in the test script, not in the scripts).
  - v14 - Step 3 says how to wait cheaply: one long background watcher call and its completion notice (two calls in
    all, whatever the duration), not repeated short polls and not a monitoring sub-agent. Based on measurements in
    `scripts\tests\Monitoring-cost.md` (a call costs about the same at a 400,000- and a 740,000-token context; a
    sub-agent adds about 50,000 tokens of start-up). Documentation only; no script changed. Not measured: a wait of
    10 minutes or more.
  - v15 - Fixes from live testing. `Select-ChoicePromptOption.ps1 -MenuItem` answers the permission prompt's "More
    confirmation options" dropdown ("Always allow", "Allow in this session"): those are MenuItems under the
    `ExtraActionsButton`, which `-Button` cannot click even with `-AllowPersistent`; `-MenuItem` is refused without
    `-AllowPersistent`. New `Set-ChatScroll.ps1` pages the chat list with `ScrollPattern.Scroll` (`SetScrollPercent`
    did not move it) and reports `Moved`; Step 3's "Verify cheaply" now uses it and says to check that the scroll
    moved. `Send-CopilotPrompt.ps1` retries the foreground step once and then tells the person to click the target
    window and rerun. `-TitleContains` (via the new `Resolve-CopilotWindow.ps1`) is added to `Watch-CopilotChatV2.ps1`,
    `Watch-CopilotChatV1.ps1`, `Select-ChoicePromptOption.ps1`, `Read-CopilotReply.ps1` and
    `Get-CopilotChatTranscript.ps1`; `-Hwnd` works as before. Documentation: Step 3 long-wait pattern (one Copilot turn
    runs `Start-Sleep` while one background watcher waits; measured 672 s, 135 polls, no tokens while waiting), the V2
    `Upgraded` flag, how to produce a permission prompt for tests (touch a path outside the workspace), and the Stop
    hook chime note. Tested 2026-11-02 without a live chat: parse checks, the no-match, no-argument and
    lasting-permission refusal paths, and the shared title lookup with several matches. NOT tested live: `-MenuItem`
    on a real prompt, `Set-ChatScroll.ps1` on a real chat, the foreground retry message, `-TitleContains` against a
    live chat.
  - v16 - Documentation only, from a long live session: Step 2 now says not to send while the chat is working
    (the Send button becomes Stop, so the send script fails after pasting and leaves the text unsent) and to keep
    each Copilot round small (one item per prompt, a separate cheap read-only review prompt, one full test run per
    round). No script changed.
  - v17 - Step 0 now also checks the repo's GitHub upstream (`git fetch`, then reads the upstream
    copy of this file), not only the local clone, and offers to run
    `Install-Skills.ps1 -Remote -Force` when a newer version exists. Same trigger as before: once
    per orchestration session. Steps 5 and 6 of Step 0 are now steps 7 and 8.
  - v18 — Step 0 reads this skill's version and what's new from the repo's small `skills-index.json`
    instead of the whole `SKILL.md`, so the update check costs about 2 KB, not up to 100 KB. If the
    index cannot be read it falls back to a filtered read of the version line.
  - v19 — The skills repo clone is found through `%USERPROFILE%\.copilot\skills-source.json` and
    AgentDebugToolkit through `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit`, instead of fixed
    `C:\MyFiles\Git` paths, and Step 0 gains a toolkit check as step 6a (clone, update and build through
    `Install-Skills.ps1`). The core scripts' default `-ExePath` now points into the toolkits folder.
    Needs the `Install-Skills.ps1` from the same change; no other step changed.
  - v20 - Documents script-blocked orchestration and caller-requested focus handback through
    ui-interaction, without bypassing policy or assuming automatic host discovery exists.
  - v21 - Coordinates ready user handoffs: finish verification and focus/cursor cleanup, then
    optional push, optional TTS and the immediately available question or final reply.
  - v22 - Reuses exact-binary capability checks and explicit restore guidance, bounds raw UIA
    fallbacks, and distinguishes verified UI selection from a verified submitted card answer.
  - v23 - Adds opt-in phase/heartbeat visibility without extra UI probes and classifies blocked,
    waiting and completed overall handoffs independently of watcher/subtask completion.
  - v24 - Documents tracked async command results, live test-step and parameter-iteration
    evidence, and reusable verified hardware cleanup without assuming runner output streams.
  - v25 - Preserves quoted prompt text across Windows native argument transport and requires
    an independent input read-back before Send. Offline tests cover argument round trips and
    input verification; no live chat send is implied.
  - v26 - Refuses to clear an existing chat draft by default and exposes an explicit overwrite
    switch, forwarded by review callers. Whitespace-only drafts are preserved too; offline
    tests cover refusal, overwrite forwarding and draft rechecks without chat interaction.
  - v27 - Refuses, before reading or typing anything, a target window owned by the calling
    script's own process chain (the Visual Studio hosting the calling chat); `-AllowOwnHost`
    overrides it and the review wrapper forwards it. Other devenv processes (main, Insiders,
    Experimental) stay targetable. An unreadable window list or process chain fails closed.
    Offline tests use mocks and a read-only real-window check; no chat send is implied.
  - v28 - `Get-CopilotChatTranscript.ps1` adds structural `Kind`, `ChildCount` and `HasMarker` per
    message (PART_FlowScrollViewer body, toolCallExpander/HeaderSite tool, PART_LikeButton footer),
    and `Read-CopilotReply.ps1` classifies by them first so items such as "Worked on 7 tasks" and
    file chips are no longer returned in `Reply`; bodies win over child-count heuristics and the
    old regexes remain the fallback. Offline fake-UI tests plus a read-only real-tree check.
  - v29 - `Watch-CopilotChatV2.ps1` also recognizes a plain `Allow` button as a pending permission
    (Pending, PermissionPrompt) when it and a `Deny` sibling are enabled and on screen, not only
    `Allow this time`. Historical or scrolled-out buttons, a lone `Allow`, and Cancel buttons do not
    match. Offline mock tests; no live approval prompt was available.
  - v30 - V2 accepts an already-idle footer after two consecutive prompt-free polls without
    `RequireBusyFirst`, and timeout notes report observed wait facts instead of claiming busy.
    `RequireBusyFirst` keeps its existing busy/grace and quiet rules. The header documents timeout
    budgeting; virtual-clock mock tests cover polling decisions without UI interaction.
  - v31 - Requires tracked async watchers and explicit wait/recovery checks, adds text-free draft
    refusal diagnostics and opt-in busy-chat steering without weakening draft protection, and
    forbids unverified cause claims.
    A reported untracked watcher lost 5.4 hours waiting for a completion notice that never came.
    The empty-input refusal cause remains unknown; offline tests cover diagnostic character codes,
    ValuePattern precedence and unchanged whitespace/zero-width draft refusal. No live UI was used.
    Steer checks busy state, retains exact read-back and clicks only SteerButton, never Stop or
    Send as a fallback. Step 2 documents steering and a bounded stuck-agent progress check.
    User-reported live POC verified SteerButton submission, input clearing and agent continuation;
    this script integration is tested offline only, not against a live window.
    A follow-up live refusal exposed sibling layout: CancelButton (Name Cancel), SteerButton and
    SendButton are direct Chat pane children, not input-host descendants. Discovery now scans
    only those children; a matching offline regression fails against the old scope and excludes
    historical message-list buttons. The corrected script has not been rerun live here.
  - v32 - Corrects the claim that the `Ask Copilot` input Name appears only while the input is
    empty, and adds an opt-in `-Trace` switch to `Send-CopilotPrompt.ps1` that returns per-stage
    timings. The Name stays with a draft, so finding it proves the input exists, not that it is
    empty (fixed in the Step 2 selector note, Step 3 "Verify cheaply" and the V2 header). A live test
    on another machine (2026-11-25) confirmed it: an Ask Copilot-keyed cache check passed with a
    draft present. That test also saw the input expose TextPattern but not ValuePattern. `-Trace`
    returns per-stage milliseconds (no chat or draft text) and leaves the default output unchanged.
    The draft check now reuses the input element it has
    just found instead of searching the whole window a second time (refusals and diagnostics are
    unchanged; the saving is expected, not measured). The own-host check reads one process snapshot
    instead of one lookup per ancestor (same chain, tested against the old walk; on a 6-process chain
    the guard fell from about 3.5 s to about 0.7 s). The banner check searches for the two banner IDs
    instead of dumping the tree with `inspect` (about 2.0 to 2.9 s before, about 0.4 to 0.7 s after),
    and a failed banner read now refuses with `BannerCheckFailed` instead of reading as no banner
    (`-IgnoreBanners` still skips it). Detection was confirmed live with a real working-directory
    mismatch banner: the new lookup and the old `inspect` method found the same banner, and the
    script refused with nothing typed. The trust banner could not be raised and is untested live.
    An interleaved before/after timing (4 runs each, noisy machine) gave a median of about 21 s
    before and about 13 s after. Not yet run on another machine or from inside a Visual Studio chat.
  - v35 - `Send-CopilotPrompt.ps1` is about 2.7 s faster per send and no longer calls a window on another
    virtual desktop "gone". It asks in this process whether the chat input is showing (one UIA search) instead of
    launching `agentdebug-ui.exe`, and falls back to the old wait only when that says no; it skips the early
    draft check for a plain send (the one after the quiet wait is the one that counts; a new session or a steer
    still refuse a draft early); and it does not clear an input that was just verified empty on the first
    attempt (the exact read-back still guards the pasted text, a retry clears first, and `-OverwriteInput` still
    clears first). A target window on another virtual desktop is missing from the default window list, so it
    used to be reported as "no longer exists"; the message now says it is on another virtual desktop and that
    sending would switch the person's desktop, and nothing is typed. Measured live (one machine, 4 interleaved
    pairs against the committed v34): median total 13.9 s to 11.2 s, and 9.9 s to 7.2 s without the quiet wait,
    which varies with the person's typing. Stage changes: first draft check 0.59 s to 0, repeated input wait
    0.62 s to 0, first clear 1.18 s to about 0. Still slow: loading the shared helper script (inside the
    `foreground` stage, about 1.5 s), the paste (1.8 s), the own-host window list (0.9 s) and the foreground
    changes (each waits 300 ms).
  - v34 - `Send-CopilotPrompt.ps1` and `Select-ChoicePromptOption.ps1` now wait for a quiet keyboard and
    mouse before taking the foreground, and hand the person's window back afterwards. Keystrokes typed while
    the script held the target window used to land in the target chat, possibly before a paste. Now the read-only
    checks (banner, input, on-screen, draft) run with the person's window still in front; the foreground is
    taken only to navigate or for the input steps; the script first queues behind other agents (one session-wide
    input lock) and waits for 3 s without typing, a click or scrolling (moving the pointer alone is ignored;
    6 s while the foreground editor holds text,
    and while a mouse button or modifier key is held, a presentation or full-screen app, Windows quiet time, a
    menu or drag in progress or a manual pause is in effect). After 0.5 s of waiting the cursor shows an amber dot
    and one short sound plays; after 30 s the person is asked once to pause (`-SpeakRequest`, only when speech is
    on in the chat); after 120 s it returns `UserActive`, `DoNotDisturb` or `SessionNotPresent` and types nothing.
    Before every foreground, clear, paste and send step it re-checks for input from the person and stops with
    `UserInput`, a held-button error or `ForegroundLost`, leaving any pasted text as a draft. After the send it
    restores the person's window, focused control and pointer (the result's `Handback`). Card answers no longer
    call UIA `SetFocus` on the card before taking the foreground. New switches `-QuietSeconds`, `-MaxWaitSeconds`,
    `-IgnoreUserActivity`, `-NoRestoreFocus` and `-SpeakRequest`, appended last. Offline tests (348 and 31
    assertions plus 81 for the shared helpers). Live (2026-11-25, one machine, sender only): a manual pause
    returned `DoNotDisturb` and typed nothing; simulated typing for 8 s into a scratch window made the send wait
    until it stopped (43 of 43 characters landed there) and the window came back; a held mouse button kept the
    foreground away until release; a lock held by another process made it queue, then send; a key pressed in the
    gap before the first input step stopped the send with `UserInput`, nothing sent and no stray text. A key that
    arrives during one of the script's own steps is absorbed into that step (the exact read-back protects the
    pasted text). Answering a real card also passed live: the card (Red, Green, Blue, Other) was answered with
    `Select-ChoicePromptOption.ps1 -Option Green`, closed, echoed `User entered: Green`, and the person's window
    and focused control (the Claude prompt box) came back. Not tested live: a real presentation, several
    orchestrators at once, and whether the person's window returns after a `UserInput` stop (the result of a
    stopped send has no `Handback`).
  - v33 - `Send-CopilotPrompt.ps1` refuses at once with `InputOffScreen` when the chat input lies
    outside the visible screen, instead of failing after three attempts with a generic foreground
    error. A window pushed partly below the screen still reports `IsOffscreen` false, so the check
    compares the input's centre with each monitor's working area (taskbar band excluded) and names
    the fix: move the window and run again. It runs after the chat is found and before any draft
    check, clear, paste or click, shares the one input search with the second draft check (no extra
    lookup), and never blocks when the screen geometry cannot be read. It does not move the window;
    moving it would be a separate, opt-in decision. Live check on this machine (window moved so the
    input sat at y=1479 on a 1008-pixel working area): refused in 5.8 s with nothing typed and the
    input empty, against 15 to 17 s and three attempts before (the earlier figures are from the
    other machine). The multi-monitor, taskbar and empty-rectangle cases are covered by offline
    tests only. `-Trace` gains a `screenCheck` stage.

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
classifying chat state (`Watch-CopilotChatV1.ps1`, Step 3) and its known unreliability, the
standard decompose -> implement -> audit -> review -> approve -> commit loop (Step 5), and the
independent-verification discipline before approving any commit.

## Bundled scripts

All live in `scripts\` next to this SKILL.md. Each clears `DOTNET_ROOT` itself and accepts
`-ExePath` (or uses .NET UIA directly) — run `Get-Help <script> -Full` for every parameter.
The `.\<script>.ps1` examples in this file assume that `scripts\` folder is the current
directory; otherwise use the full path. The watcher, reading and `Select-ChoicePromptOption.ps1`
scripts also accept `-TitleContains '<project> - '` instead of `-Hwnd` (no match gives a plain
message, several matches the candidate list); `-Hwnd` wins when both are given.

| Script | Use it for | Changes anything? |
| --- | --- | --- |
| `Send-CopilotPrompt.ps1` | Step 2: guard drafts, new session (optional), clear, paste, verify, then Send; `-OverwriteInput` permits draft replacement | Sends a prompt |
| `Watch-CopilotChatV2.ps1` | Step 3 (default): light poll until Pending, Idle, or timeout; no prompt text | No |
| `Watch-CopilotChatV1.ps1` | Step 3: full-tree poll; returns prompt question/options, `AwaitingReply`, banners | No |
| `Get-CopilotChatTranscript.ps1` | Step 3: full text of the latest reply/replies, with structural `Kind` per message | No |
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
  Read-only scripts (`Watch-CopilotChatV1.ps1`, `Watch-CopilotChatV2.ps1`, `Get-CopilotChatTranscript.ps1`,
  `Compare-RepoSnapshot.ps1`) don't change the cursor.
- If a dot is ever left behind, `AgentCursor.ps1 -Restore` clears everything (or the user
  can sign out and back in). A session flag older than 12 hours is ignored.
- Only one session colour shows at a time; the first one started owns it. If `-Session Start`
  reports that a UiAutomation (green) session is already active, it was left behind or another
  run is in progress - say so to the user rather than clearing it.

Prefer these over ad-hoc `agentdebug-ui.exe` calls; the raw commands below are what to fall
back on if a script is missing or fails.

**When scripts are blocked:** do not change or bypass execution policy. Use ui-interaction's
script-free cursor-session and verified-host focus-handback guidance, with kind `Orchestrator`.
The bundled send/watch/choice scripts are not available in that environment: use documented
CLI primitives only where the same read-back and submission checks can be preserved. In
particular, do not replace the choice script with an unverified radio click; if the intended
answer cannot be verified, ask the user to answer the card. Do not promise unattended
orchestration when policy prevents a required verification step. Return focus to the separately
identified host window after action batches when requested; never confuse it with the target
VS window. Use `activate --hwnd <verified host hwnd> --restore true` only when the chosen
binary advertises restore support, then verify foreground state; restoration can still leave
activation denied. No automatic chat-pane or caller-window discovery is implied. Stop the
indicator at every handback, including errors and questions.

## Learned scripts (saved by the orchestrator, curated by the user)

The table above lists the **core** scripts. Code you write during a session for a repeatable
orchestration step (handling Keep/Undo or a tool-permission prompt, typing a custom card answer,
waiting for a build in the target, scrolling the transcript) is saved next to them, so later
sessions reuse it instead of re-deriving it.

- **Where:** the repo copy, `<skills repo>\agent-orchestrator\scripts\`
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
- Known limitations doc: `%USERPROFILE%\.copilot\toolkits\AgentDebugToolkit\docs\KNOWN_OPEN_FINDINGS.md`.
- A Stop hook (if the user has one configured for a chime) fires at the end of every turn, so the
  chime can also play when a turn ends while background work is still pending (for example a
  background watcher). A chime is not proof that the whole task is finished.

## User handoff alerts

When independently enabled, follow `push-notifications` and `read-aloud` for user-facing alerts;
do not enable either mode just because orchestration starts. A watcher reporting Idle, Pending
or a footer is a cue to read and verify, not proof that a deliverable is complete. Do not send
completion alerts for individual polls, watcher launches or unfinished implementation tranches.

Before a user handoff, finish reading the reply and any necessary verification, prepare the
question/options or final response, return requested host focus and stop the session indicator.
Classify the overall request: running work is not completion; an unresolved blocker requiring
the user gets Blocker, an approval/choice gets Question, and only a fully verified finished
deliverable gets Completed. Never label the investigation successful because one subtask passed.
Check this on error/early exits too; deduplicate unchanged blockers and do not send both Question
and Blocker for one handoff. A failed alert attempt must not trigger recursive notifications.
Only then send the qualifying generic push, wait, perform the active TTS announcement, wait,
and immediately open the question or publish the ready reply. No preparation may intervene.
If the supervisor can answer the target agent's question within the user's authorization, do
not alert the user unnecessarily. Use this host chat's approved repository label, not the target
repository's name, and never send target chat text, code or diagnostics to the push service.

## Step 0: Version Check

Run this **once**, at the very start of a new orchestration session — do not repeat it on every
individual verb call (click, inspect, poll, etc.) within that session; it must not get pulled into
Step 3's polling loop. This is a cheap check (one `git fetch` and one line read, no UIA calls
involved), so do it every time a new session starts rather than skipping it to save time.

1. Find the repo clone: read `skillsRepo` from `%USERPROFILE%\.copilot\skills-source.json`, which
   `Install-Skills.ps1` writes:
   `(Get-Content "$env:USERPROFILE\.copilot\skills-source.json" -Raw | ConvertFrom-Json).skillsRepo`.
   Call it `<skills repo>` below. If the file or the folder does not exist, stop and ask the user
   where the clone is rather than silently skipping the check or assuming a different location.
2. Check GitHub: `git -C "<skills repo>" fetch --quiet origin`. This
   changes no working file. If it fails (offline, no upstream), say once that GitHub could not
   be checked and continue with the clone alone.
3. Read this skill's entry from the repo's small `skills-index.json` (about 2 KB), not from the
   whole `SKILL.md` (which can be over 100 KB). The repo version is the higher `version` of the
   two copies below, and its `whatsNew` is the change to report. Keep only the printed `version`
   and `whatsNew`:
   - GitHub's copy (skip if the fetch failed): `(git -C "<skills repo>" show "@{u}:skills-index.json" | Out-String | ConvertFrom-Json).skills.'agent-orchestrator'`
   - The clone's copy: `(Get-Content "<skills repo>\skills-index.json" -Raw | ConvertFrom-Json).skills.'agent-orchestrator'`
   - If neither can be read (a repo from before the index existed), read only the version line,
     never the whole file: `Select-String -Path "<skills repo>\agent-orchestrator\SKILL.md" -Pattern 'CURRENT_SKILL_VERSION\s*=\s*\d+' | Select-Object -First 1`.
4. Compare the repo version to this file's own `CURRENT_SKILL_VERSION` (the version of whatever
   copy is currently loaded/running).
5. If the repo's version is higher: tell the user what's new (the index's `whatsNew` line; if more than one version behind, say how
   many and offer to list the older changelog entries) and whether the newer version is only on GitHub (clone not pulled
   yet) or already in the clone. Ask via `ask_user` whether to pause and update now. On yes, run
   `& "<skills repo>\Install-Skills.ps1" -Remote -Force`: it pulls the
   clone (fast-forward only, never when tracked files have uncommitted changes), installs every
   changed skill, and clones, updates and builds the toolkits; tell the user the new text applies
   from a new chat session. On no, proceed with the current session and do not ask again in it.
6. If versions match: proceed silently — no need to announce anything.
6a. Toolkit check (also when the versions match). Skip it if step 5 just ran the installer
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
6b. Apply ui-interaction's exact-executable `info`/capability preflight to the chosen executable,
   including any explicit `-ExePath` or portable package. Reuse an already verified result for
   that same binary; never infer its features from the managed checkout or an installer marker.
   Use new budget/restore/selection flags only when advertised. If debugger automation is needed,
   also follow vs-debug's separate binary check and explicit VS-instance targeting. These checks
   do not start UI interaction, bypass script policy or grant mutation permissions.
7. If the repo copy's `scripts\SCRIPTS.md` exists, read it so the learned scripts are in context,
   and mention the count in a few words (e.g. "2 learned scripts indexed").
8. Start the hands-off indicator: `AgentCursor.ps1 -Session Start` (blue dot).

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
back through ValuePattern or TextPattern independently of the CLI's paste verification.
Windows native argument quoting preserves literal double quotes and backslashes, including on
Windows PowerShell 5.1. It clicks Send **only** if the input matches the original prompt exactly, and retries otherwise
(stray keystrokes typed into the window during a paste were observed being sent along with the
prompt). Before input changes it refuses non-empty drafts, including whitespace-only text;
`-OverwriteInput` deliberately restores the previous clear-and-replace behavior. The review
wrapper forwards its existing switch. An unreadable or ambiguous input is not proof of emptiness.
Before anything else it also refuses a window owned by the process chain that runs the script
(`OwnHostWindow`), so an agent cannot type into its own chat; pass `-AllowOwnHost` only when that is
intended. Windows of other processes, including other main or Insiders Visual Studio instances,
are unaffected. A detached script with a broken parent chain cannot be recognized this way.
`Sent: false` means nothing was sent — read `Error` and `InputText`. Omit `-NewSession`
to reply in the current conversation. It also refuses, before typing anything, while the chat
shows a working-directory mismatch or untrusted-workspace banner (see Step 4); don't pass
`-IgnoreBanners` unless the user agreed.

- **Stale window handles.** An hwnd is only valid until that Visual Studio instance closes; a
  restart gives a new one. Pass `-TitleContains '<project> - '` instead of `-Hwnd` and the script
  looks the window up itself, failing with a plain "no window" message when none matches and
  with the candidate list when several do. If a
  handle is stale, `Error` now says the window no longer exists rather than just "could not bring
  to foreground". The same applies to the watcher scripts: look the hwnd up again first.
- **Finding the chat.** If the input is not showing, `Send-CopilotPrompt.ps1` first selects the
  `Chat` tab (it can sit behind a sibling tab such as Git Changes in the same pane), and if the
  pane then shows only the session list it creates a new session, so a send into a window with
  no chat open still works. It never creates a session when the input is already showing. Pass
  `-NoNavigate` to require the chat to be open already, and `-NewSession` to always start a new
  one (it waits up to 30s for the input). Do the same by hand when you use raw verbs:
  `click --strategy Name --value Chat --controlType TabItem`, then `createNewThread`.
- **A person may be using the machine.** The send and the card-answer scripts do not barge in. They queue
  behind other agents, then wait until there has been no typing, click or scrolling for 3 s (`-QuietSeconds`;
  moving the pointer alone does not count) and
  nothing is held, presented or paused; while waiting, the cursor shows an amber dot and a short sound plays
  once (after 30 s, a spoken request when you pass `-SpeakRequest` and speech is on in this chat, otherwise the
  sound again). If the person is still busy after `-MaxWaitSeconds` (120), the result has `Sent: false` and an
  error starting `UserActive`, `DoNotDisturb` (for example a presentation, full-screen app, Windows quiet time
  or a manual pause), `SessionNotPresent` (locked screen) or `UiBusy`, and nothing was typed or clicked: tell
  the user and try again later; do not loop. A stop in the middle (`UserInput`, `MouseButtonInUse`,
  `ModifierInUse`, `ForegroundLost`) leaves any pasted text as a draft in the target; nothing is sent. When
  the send succeeds, `Handback` says whether the person's window, focused control and pointer were restored
  (`Restored`, `RestoredAfterUserInput`, `UserInput`, `NotVerified`, ...). Use `-IgnoreUserActivity` only when
  nobody is at the machine, and `Set-AgentUiPause -Minutes N` (AgentCursor.ps1) before screen sharing, which
  Windows does not report. The amber dot means "waiting for you to pause"; red still means "acting now".
- **Chat input off-screen.** When the input's centre lies outside every monitor's working area (a
  window moved partly below the screen, or under the taskbar), the script returns `Sent: false` with
  an `InputOffScreen` error before typing or clicking anything. UIA keeps reporting `IsOffscreen`
  false for such a window, so do not rely on that flag. Ask the user to move the Visual Studio
  window back (or do it deliberately yourself with their agreement), then send again; the script
  does not move windows and does not retry.
- **`-Quiet`** returns `InputText` as `$null` on success, so a long prompt is not echoed back
  into your context. Failures still return it, except text-free Steer availability/click failures.
- **Brief the agent so it does not stop to ask.** Many repos make the agent ask permission for
  each follow-up fix, which costs one round trip per fix. Put the decisions you can already make
  in the task text: what is pre-approved ("apply in-scope fixes without asking"), what is not
  ("do not touch files X, Y; do not commit, stage or push"), and what counts as blocked ("stop
  and report only if a build, test or permission prevents progress"). Only pre-approve what the
  user has authorized; commit and push need the user's explicit say-so.
- **Steer a running agent; send a new turn only when idle.** Steering is the supported way to
  redirect an agent or ask for progress without stopping its current work. Use
  Send-CopilotPrompt.ps1 -Hwnd <verified-hwnd> -Steer -Quiet -Text '<authorized redirect>'.
  With a busy chat, an empty input shows Stop; entered text replaces it with Steer (Name Steer,
  AutomationId SteerButton, Button with InvokePattern), and SendButton is absent. The user's
  live POC verified that clicking SteerButton cleared the input, added the message to the
  transcript, and the agent answered and continued without stopping. The new script path is
  validated offline only. It checks busy before typing, preserves all draft/own-host/banner
  guards and exact read-back, and clicks only SteerButton; missing/disabled Steer or lost busy
  state returns Sent=false with a text-free reason. It does not navigate/create a chat and
  refuses Steer with NewSession. NoSend still means paste/verify without submission.
  Without Steer, wait for verified Idle before normal Send. Never press Enter or click Stop
  to force submission, and never fall back from Steer to Send. Verified unsent text stays a
  protected draft; OverwriteInput is only for deliberate replacement of that text.
- **Stuck-agent progress check.** First verify the busy target and fresh footer/transcript,
  git status and relevant artifact times; answer any user message before these checks. State
  the expected response deadline (for example, launch time plus 90 seconds, with time zone)
  and exact recovery check before yielding. Steer this fixed single-line question:
  'Progress check only: report your current step, last completed step, and any blocker; do not change scope, stop work, or run extra tools; then continue the existing task.'
  Verify Sent=true and that this exact new question appears in the current transcript. Wait
  using one tracked async watcher (Watch-CopilotChatV2.ps1 -Hwnd <verified-hwnd>
  -RequireBusyFirst -TimeoutSeconds 90 -NoDetail -NoBeep) and retain/read its shellId as in
  Step 3; keep individual tool waits below about two minutes. A working agent can answer Steer without becoming Idle:
  read the fresh transcript at the stated deadline, not only the completion footer. If no
  reply to that delivered question arrives by the deadline, classify it as stuck for supervision
  and report the timeout/last-observed artifact facts. This is an operational escalation, not
  proof of the underlying cause. Failed delivery or unreadable transcript means unverified,
  not stuck. Do not automatically Stop, resend, broaden scope or overwrite a draft.
- **Keep each Copilot round small.** Give one work item per prompt, with its acceptance checks.
  Rounds that bundled several items, plus their own audits and repeated full test runs, took
  20 to 25 minutes and 50 to 85 credits each, and one stretch produced a single huge streamed tool
  call that looked like a hang (the Copilot log under `%TEMP%\VSGitHubCopilotLogs` showed it was
  still streaming). A read-only review of an existing diff took under 8 minutes and 3 to 8
  credits and found real defects, so prefer: implement small, then a separate read-only review
  prompt ("do not edit, build or run tests; ranked findings only, at most N"), then fix. Tell the
  agent to run the full test suite once per round, after its last edit, and to repeat it only
  before the final report of a work item and only if files changed since the last green run.

The raw equivalent, for fallback:

Prefer **clipboard paste over synthetic typing** for reliability with longer text (user
preference, confirmed this session):

```powershell
& $exe type --hwnd <h> --strategy Name --value "Ask Copilot" --text "<task text>" --paste --verify
```

- `--strategy Name --value "Ask Copilot"` targets the chat input via its Name. The Name stays
  while the box holds a draft, so it identifies the input but says nothing about whether the box
  is empty; read the text for that (TextPattern, or ValuePattern where exposed). This is currently the only reliable selector for the real
  Copilot Chat input/Send button, because they expose no `AutomationId` — `AutomationId=WpfTextView`
  is ambiguous (resolves to either the chat input or the code editor pane depending on UIA
  traversal/focus state). This is a fact about this specific control, not a generic
  ui-interaction gotcha, so it's recorded here rather than there.
- `--paste` avoids issues with special characters/newlines that synthetic typing can mangle.
- Windows PowerShell 5.1 can strip or split embedded double quotes in direct native calls.
  Use `Send-CopilotPrompt.ps1` for quoted text; its native transport preserves the arguments and
  independently reads the input before clicking Send. The raw example is not quote-safe there.
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

WARNING: Run the watcher as a tracked async shell command: shell tool mode async, retain the
returned shellId, and read that same ID on the completion notice. Never launch the supervising
watcher via Start-Process, a hidden window or a scheduled task: an untracked watcher gives no
completion notice. A reported real run lost 5.4 hours when the supervisor ended its turn waiting
for a notice that never came. V2's internal one-shot V1 detail read is not a separate supervising
watcher. Host interactivity or output redirection cannot reliably prove shell tracking, so no
heuristic startup detection is used.

Before ending any turn that waits on background work, state the expected finish time (with time
zone; label estimates), the watcher timeout/deadline, and the exact recovery check to run, including
the retained shellId and artifact paths. Keep each individual tool wait under about two minutes;
the tracked worker itself may run longer. When the user writes, answer their message first, then
check fresh artifact timestamps (the current reply/footer against the launch time, git status in
the target repository, and relevant file last-write times) before trusting Idle. A footer with no
correlatable timestamp is not proof of freshness; reconcile the reply with current artifacts.

Two reusable watcher scripts are bundled with this skill in `scripts\` (next to this SKILL.md —
always available even if the toolkit source isn't up to date; they still call the toolkit's `agentdebug-ui.exe`):

- **`Watch-CopilotChatV2.ps1` — the default.** One small probe per poll (about 7 % of a core, median
  probe under a second), silent while polling, never activates the window. When the wait ends Pending
  or Idle it runs V1 once and merges the result, so it returns everything V1 does (`Question`,
  `Options`, `Recommended`, `MorePages`, `Banners`, `LastMessage`, `LastMessageTail`, `AwaitingReply`,
  `CompletionFooter`) plus `NotVisible`, `ChatSwitched`, `WindowGone`, `ProbeError` and `Upgraded` (true when the
  light probe said Idle but the detail step found an open prompt: the result is changed to Pending; read
  `PromptKind` and answer it). `-NoDetail` skips that final step, and with it the upgrade. It sees a card or prompt only in the last few messages while the list is near its end; run it
  with `-CrossCheck` after a Visual Studio or Copilot update.
  Without `-RequireBusyFirst`, two consecutive polls with a footer at the end, no stop button and
  no card or permission prompt return Idle even if busy was never seen. After sending a prompt,
  keep `-RequireBusyFirst` so a previous footer cannot use that fast path; its existing busy/grace
  and quiet rules remain unchanged. When a wait may start idle, budget `-TimeoutSeconds` above
  `-QuietSeconds` plus `-StartGraceSeconds`, with room for poll/probe overhead. Timeout means no
  terminal state was observed, not necessarily that the chat is busy; read the note's wait facts.
- **`Watch-CopilotChatV1.ps1` — the full-tree watcher.** Heavy (about 70 % of a core), a full tree dump
  per poll. Use it directly only when you need its verbose per-poll lines, `-NotifyOnDone`
  or `-RequireWorkingFirst`.

The header of each script lists its pros and cons, and `scripts\tests\` lists their test cases (start
at `tests\README.md`; read the script's file before changing it). Everything below that describes
states, markers, `-RequireWorkingFirst`, `AwaitingReply` and `-NotifyOnDone` is V1
behavior; V2 takes `-RequireBusyFirst`, `-QuietSeconds` and `-TraceFile` (see its header). V1's
`-ProgressFile` stores poll text; updated V2's same-named option stores JSON-lines heartbeats as
documented below, not V1 output. V1 is also committed
in the AgentDebugToolkit repo at `tools\Watch-CopilotChat.ps1` (old name, not renamed yet; it can be
out of sync). V1 classifies state from the UIA tree (NOT by button-name heuristics like
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
.\Watch-CopilotChatV1.ps1 -Hwnd 0x691588 -RequireWorkingFirst -TimeoutSeconds 300 -PollIntervalSeconds 12
```

How to wait cheaply: the cost of a wait is the number of tool calls, not the minutes (see the monitoring-cost measurements in scripts\tests). Start ONE long watcher as a tracked async shell command (Watch-CopilotChatV2.ps1 -TimeoutSeconds 1800 or more; it accepts up to 7200). Retain shellId, verify startup once, and state the expected finish time and exact recovery check before ending your turn. On the completion notice, read that shellId to retrieve the result and exit status; the notice itself is not the result. Do not poll with repeated short foreground calls or start a monitoring sub-agent just to wait.

**Long-operation visibility:** announce the current phase before a long wait. Updated V2 accepts
`-HeartbeatSeconds 30` for host progress and/or `-ProgressFile <local jsonl path>` for machine-readable
progress; older installed scripts do not. It records phase/state, operation, elapsed seconds,
last successful probe/time (null until observed), outer probe retry count and cleanup ownership.
It reuses the normal probes, adds no polling and sends no pushes. Default polling remains silent.
Heartbeats are emitted between probes/phase changes, not while an in-flight UIA call is stuck;
they do not establish device progress or provide a hard watchdog. File-only progress defaults to
30 seconds. Treat watcher Idle as ObservationReady, Timeout as StillWaiting, Pending as NeedsInput,
and read/visibility failures explicitly; none of those classifies the overall task as completed.
Before handback, report actual cleanup state, including any focus/indicator cleanup that failed.

**Long-wait pattern (when you need to wait for something that is not a Copilot reply, such as a build or a timer).** Send ONE Copilot turn that runs `Start-Sleep` for the wait, and keep ONE background `Watch-CopilotChatV2.ps1` waiting for that turn to end. Nothing of yours runs while it waits. Measured (see `scripts\tests\Monitoring-cost.md`): 672 s, 135 polls, zero tokens used while waiting. The only calls are the send, the background watcher, and its completion notice.

**Idle is not always "done".** An agent can end its turn by asking for approval in plain text, with
no card, and that looks exactly like a finished task. When the last message ends with a question
or phrases such as "please approve" or "approve or decline" (`-QuestionPattern`), the result has
`AwaitingReply: true` and a `Note`. Treat it as a question: read `LastMessageTail` (the last 600
characters, set only in this case; `LastMessage` keeps the start of a long reply and can omit a
question at the end), answer it with `Send-CopilotPrompt.ps1` (Step 4, case 1) if you are
authorized to, otherwise report it to the user. The check is a heuristic in both directions:
a `false` is not proof the task is complete, and a `true` can be a false alarm (for example, a
reply that merely quotes "let me know whether" while discussing it), so read the tail before
acting.

Two V1 options help a supervisor that cannot stream output: `-ProgressFile <path>` appends every
`[poll ...]` line to a file as well as the console, and `-NotifyOnDone` beeps when the watch ends
(Pending, Idle or Timeout). When `AwaitingReply` is true the result also has `LastMessageTail`,
the last 600 characters, because `LastMessage` keeps the start of a long message. The default maximum poll interval is 30s, so a reply that finishes
mid-sleep is noticed within about half a minute.

**Launch one asynchronous watcher, not repeated short foreground waits.** When host output is
useful, enable the optional heartbeat/progress file above. Do not increase UI polling or create
extra chat turns merely for a heartbeat. Wait for the runner's completion notice, then read the
result once and independently verify the reply. A heartbeat or a single transient Idle sample
is not permission to stop the watcher early, bypass its stability checks or announce success.
Runner output may be buffered; a local progress file provides inspectable facts, not guaranteed
real-time chat streaming. A timeout ends this wait, not the supervised task or debuggee.

### Long-running commands, test progress and hardware cleanup

- For a command that may exceed about two minutes, prefer `powershell` with `mode="async"`
  rather than a long synchronous `initial_wait`. A user can move a synchronous call to the
  background, so never rely solely on its initial response returning the final result. Retain
  the returned `shellId`, verify startup once, and use `read_powershell` with that same ID to
  retrieve output and the final exit status after completion. Read at meaningful checkpoints
  when progress is needed; do not busy-poll or restart a command because output is quiet.
  Keep the process attached; background execution is not permission to detach it.
- Test runners can buffer test console output until the run ends. Before launching a long
  test, identify its actual live log/trace or existing analyzer and the run's starting offset.
  Tail only new records for that run, using the existing helper's documented arguments or,
  for a plain text log, `Get-Content -LiteralPath <verified-log> -Tail 0 -Wait`. Use a separate
  tracked async tail, stop that tail when the run finishes, and still retrieve the test runner's
  final exit status and results. Do not mistake old records, a tail's exit or missing output
  for test completion. If no live source exists, say progress is unavailable; do not infer a hang.
- Every test progress update must name the current step AND current parameter-loop iteration
  (index plus actual parameter values), taken from run-correlated trace records. Track loop
  changes while tailing, not just step lines. If the iteration cannot be established, say
  "iteration unknown" rather than guessing from elapsed time, step counts or a prior run.
  Distinguish last-observed progress from the runner's present state when records are stale.
- Before hardware execution, identify the target repository's stable, reusable cleanup-only
  command and document its invocation as the recovery step after every failed or aborted run.
  Require explicit target/repository arguments; missing arguments must fail non-interactively
  with a clear parameter name and usage example before device access. Do not invent a command,
  combine cleanup-only with another test or normal-state exercise, or execute it without the
  required hardware authorization. Cleanup must independently read back and print the final
  device state against the documented safe baseline; exit code zero alone is not verification.
  A timeout, null cleanup handle or failed read-back leaves state unverified: report that
  explicitly, preserve the original test failure, and report cleanup failure separately.

If the watcher is missing, use only a verified raw fallback: scope a probe to the needed chat
control and, on a capable binary, use `inspect --hwnd <h> --maxDepth 25 --nameContains <label>
--maxNodes 1000 --maxDurationMs 2000`. Treat incomplete/error/zero-partial-match results as
unknown, not Idle or proof that no prompt is waiting. Reacquire or deliberately adjust the scope/
budget before another read. Do not recreate an unbounded full-chat tree loop; if the required
state/answer checks cannot be preserved, ask for help rather than promise unattended operation.

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

**Unavailable/partial observations:** stale UIA elements can reflect virtualization, but do not
classify every `unhandled-exception` as harmless noise. Reacquire the verified target and allow
one fresh read-only probe for an unavailable element; report persistent/unexpected failures.
Inspect traversal/state errors and completeness before using a bounded result. Unknown is not
Idle, an empty reply, or permission to answer a different prompt.

**Verify cheaply.** Most of a supervised run is checking state, so use the cheapest check that
answers the question, in this order: (1) the `Watch-CopilotChatV1.ps1 -Hwnd <h>` result (`State`,
`PromptKind`, `Banners`); (2) `Get-CopilotChatTranscript.ps1 -Hwnd <h> -Last 0 -IncludeFooter
-AsText` for the reply text, after moving the chat list to its end with `Set-ChatScroll.ps1 -Hwnd <h>
-ToEnd` (the list is virtualized, so a reply below the visible area is not returned until the list
is scrolled, and an unscrolled read can look like "no reply yet" while the reply is already there).
Check that the scroll actually moved: the helper returns `PercentBefore`, `PercentAfter` and
`Moved`; `Moved` false with a percent short of 100 means the list did not scroll, so do not trust
the read. `ScrollPattern.SetScrollPercent` does not move this list, and `scroll-container
--verticalPercent 100` may not either, so do not rely on them alone; `Read-CopilotReply.ps1` does
its own scroll and check; (3) `find-first --hwnd <h> --strategy Name --value "<element name>"`
for a single element (`--value "Ask Copilot"` is found whether or not the input holds text, so it
proves the chat input exists, not that it is empty, and
`--value "Allow this time"` is found only while a permission prompt is waiting) or `inspect --hwnd
<h> --nameContains <text> --maxDepth <small>`; (4) a screenshot only when layout or an unknown
dialog matters. Never run an unfiltered `inspect` of a chat window: its output can be very large
and token-heavy. On capable binaries, bound raw inspection with `--maxNodes`/`--maxDurationMs`
and preserve incomplete/unknown results rather than classifying a partial tree as complete.
These flags do not retrofit bundled watcher/transcript scripts: their current implementations
are unchanged; do not pass nonexistent script parameters or assume those scripts are bounded.
`Send-CopilotPrompt.ps1` independently checks the input text and refuses drafts by default.
Finding the `Ask Copilot` placeholder alone does not establish an empty input. Pass
`-OverwriteInput` only when replacing a draft has been explicitly approved.
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

   **Why generic selection is not card-answer verification:** `SelectionItemPattern.Select()` marks the radio selected
   but the newer card still submitted its previous choice (asked for Option 2, card echoed
   Option 1). And `click --strategy Name` hits `ambiguous-match` (the RadioButton and its
   TextBlock share a Name) or the ToolTip gotcha below. New `select-item`/`select-row` verification
   proves a UIA selection postcondition, not which answer the chat app will submit; it does not
   replace this script's click/submit/echo contract. If the script is unavailable and unique
   targets can be established, the raw fallback still **requires two clicks, not one**:
   ```powershell
   & $exe click --hwnd <h> --strategy Name --value "<exact option text>" --controlType RadioButton
   & $exe click --hwnd <h> --strategy Name --value Submit --controlType Button
   ```
   On ambiguity, narrow the target or ask the user; never pick the first match. An authoritative
   selected-state read can help before Submit but still does not replace the submitted echo.
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
   & $exe inspect --hwnd <h> --maxDepth 25 --nameContains "User entered:" --maxNodes 1000 --maxDurationMs 2000
   ```
   This example requires bounded-inspection support. A filtered echo probe alone cannot show
   that Submit disappeared: separately check the relevant card closed or advanced. Require the
   fresh echo for this submitted card, not an old match; partial/uncertain results are unverified.
   Via the last chat message(s) or that fresh echo, confirm the submitted option matches
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

   "Always allow" and "Allow in this session" are not buttons: they are MenuItems in the "More
   confirmation options" dropdown (`ExtraActionsButton`). Use `-MenuItem '<exact name>'
   -AllowPersistent`; the script opens the dropdown, invokes the item and checks the prompt closed.
   Without `-AllowPersistent` it refuses. Only when the user asked for a lasting permission.

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

- Don't claim the cause of an unverified refusal as fact. InputNotEmpty with an independently
  empty UIA read does not prove a placeholder, newline, zero-width character or attachment chip
  caused it. Inspect the refusal's draft length and code-point summary; distinguish observations
  from hypotheses. OverwriteInput succeeding proves only that the guard was bypassed, not why
  it refused. Never weaken the default protection of any draft, including whitespace-only text,
  without a concrete, testable cause and explicit authorization.
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
- Don't assume a previously-known hwnd/pid is still valid across a long gap — re-verify (a
  restarted Visual Studio has a new hwnd; `Send-CopilotPrompt.ps1 -TitleContains` looks it up).
- Don't assume restoring a window grants foreground focus. On capable builds use explicit
  `activate --hwnd <verified hwnd> --restore true` when restoration is intended, then verify.
  Activation can fail with `stale-context`; input can fail with `foreground-activation-failed`.
  If scripts are allowed, `Set-AgentForegroundWindow` from `AgentCursor.ps1` provides the
  existing verified fallback; if blocked or still unsuccessful, ask for manual activation.
  Never bypass policy, send dummy keys to restore, or loop activation/input attempts.
- Don't write a commit message with `Set-Content -Encoding utf8` in Windows PowerShell 5.1: it
  adds a byte-order mark, which ends up at the start of the commit subject. Write the file with
  `[IO.File]::WriteAllText($path, $msg, (New-Object Text.UTF8Encoding($false)))`, and pass it
  with `git commit -F <file>`. `git commit -F -` with a here-string misparses the message there.
- Don't blame the repo when Visual Studio's Git Changes pane shows nothing but `git status`
  disagrees: look for stale `.git\index.lock` / `next-index-*.lock` files with no git process
  running (the pane then warns that a Git process may be running). Delete them only with the
  user's go-ahead, then restart that Visual Studio instance if the pane stays empty.
- Don't use `AutomationId=WpfTextView` for the chat input — it's ambiguous; use
  `--strategy Name --value "Ask Copilot"` for input, `--strategy AutomationId --value SendButton`
  for Send.
