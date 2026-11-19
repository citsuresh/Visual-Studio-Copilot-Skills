---
name: vs-chat-history
description: 'Search and read local Visual Studio Copilot Chat history through the chathistory CLI (VsChatHistoryToolkit), and rename chats only when the user asks. Use for: "what did we decide about X in an earlier chat", "find the chat where I worked on Y", "which solution was that chat in", "how many chats do I have", or "rename this chat". Rename this responding chat through the bundled independent idle-handoff script, not during generation; other idle chats can use the native UI directly. CLI history coverage is session-store.db only; UI observations are separate. Chat text is confidential: show short excerpts only.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 13`. Compare against the source-of-truth copy at
  `<skills repo>\vs-chat-history\SKILL.md` (the clone path is in
  `%USERPROFILE%\.copilot\skills-source.json`, see Step 0), and against that clone's
  GitHub upstream, once at the start of a session (Step 0).
- Changelog:
  - v13 - Replaces experimental direct self-renaming with the bundled independent idle-handoff
    worker; other idle chats retain the direct UI route. Preserves CLI activity/force, restart
    and undo safeguards. Handles verified empty clipboards and checks foreground once before
    input; incomplete snapshots and denied activation still stop the worker.
  - v12 - Allows user-requested current-chat renaming through the verified Visual Studio
    session-list UI; keeps CLI activity/force, restart and undo safeguards separate. The UI
    self-rename workflow is pending a controlled live test, not verified by earlier CLI tests.
  - v11 — The skills repo clone is found through `%USERPROFILE%\.copilot\skills-source.json` and
    VsChatHistoryToolkit through `%USERPROFILE%\.copilot\toolkits\VsChatHistoryToolkit`, instead of
    fixed `C:\MyFiles\Git` paths, and Step 0 gains a toolkit check (clone, update and build through
    `Install-Skills.ps1`). Needs the `Install-Skills.ps1` from the same change; no command changed.
  - v10 — Step 0 reads this skill's version and what's new from the repo's small `skills-index.json`
    instead of the whole `SKILL.md`, so the update check costs about 2 KB, not up to 100 KB. If the
    index cannot be read it falls back to a filtered read of the version line. No other step
    changed.
  - v9 — Step 0 now also checks the repo's GitHub upstream (`git fetch`, then reads the upstream
    copy of this file), not only the local clone, and offers to run
    `Install-Skills.ps1 -Remote -Force` when a newer version exists. Same trigger as before: once
    per session. No other step changed.
  - v8 — adds `rollup` (events summaries combined across the most recent chats: tool, skill and
    permission counts, compaction statistics, session-end totals, chats without a log or session-end
    event). No existing step changed.
  - v7 — subagent requests count toward `credits` (verified against a chat footer on a turn that used
    subagents): quote `total`, not `main`. Wording fix only.
  - v6 — adds `credits` (the credits the chat window shows, as the sum of `request_multiplier`) to
    `usage`, `stats`, `usage-top` (`--by credits`) and `activity`; replaces the v5 advice not to
    report credits. No existing step changed.
  - v5 — adds `events <id>` (bounded summary of a chat's event log: compactions, session-end
    facts, tool, skill and permission counts, aborts, subagents) and `activity` (turns, chats,
    requests and `nano_aiu` per day); states what the credits check found (`nano_aiu` is not the
    chat's credits). Date bounds now keep fractional seconds. No existing step changed.
  - v4 — adds `usage-top` (chats ranked by usage in a date range) and `doctor` (read-only health
    report of the store). No existing step changed.
  - v3 — adds the `files` command (files a chat edited or created; chats that touched a file) and
    `peak_input_tokens` / `last_input_tokens` in `usage` (the chat's real context size). No
    existing step changed.
  - v2 — adds the `usage` command (token and cost figures of one chat, optionally per turn) and the
    usage section of `stats`; both read the `assistant_usage_events` table. No existing step changed.
  - v1 — initial version. Wraps the `chathistory` CLI of VsChatHistoryToolkit (search, sessions,
    show, turns, checkpoints, stats, rename, undo-rename). Written from the toolkit's contract and
    from its Stage 2 runs against a real store with Visual Studio open.

# VS Chat History

Search and read past Visual Studio Copilot Chat conversations on this machine by calling the
`chathistory` command-line tool. The tool does the database work. For user-requested renaming,
use the bundled idle-handoff worker for this responding chat and direct native UI for other
idle chats, both through `ui-interaction`. Never directly rename a generating chat. CLI history
reads and stored-session renaming remain separate workflows.

## Rules that always apply

- **Chat text is sensitive** (work chats). Never paste whole chats or long passages. Quote
  only short excerpts (a few lines) that answer the question, and only when the user needs the
  wording. Prefer a summary in your own words with the session id so the user can look it up.
- **Never read or copy the store yourself.** Do not open `session-store.db` with another tool, do
  not copy it, do not read `events.jsonl` or `workspace.yaml` directly, and do not run SQL. Use
  only the supported CLI commands below for store access. Every command except `rename` and `undo-rename` opens the database
  read-only. Every answer is capped; in a `rename` or `undo-rename` result every shown value
  (`old_title`, `new_title` and the name line, `user_named` line and summary in `before` and
  `after`) is cut to 200 characters and `truncated` is then true. Still report only the status,
  the titles and any warning, not the whole result.
- **Never write chat text into files, commits, PR descriptions or notes** unless the user asks.
  Redact credentials, tokens, account numbers and personal data if they show up in an excerpt.
- **State the coverage.** Every CLI result has `"coverage": "session-store.db only"`. The chat pane can
  list more chats than the database holds, so "not found" means "not in session-store.db".
  Native UI observations cover only the verified Visual Studio window; do not describe them as
  CLI database results or assume a session missing from the database cannot appear in the UI.
- **Writes require a rename request.** Native UI renaming and CLI `rename`/`undo-rename` are
  allowed only when the user asks (see Renaming). Among CLI commands, only those two write:
  they change one chat's `workspace.yaml` and stored summary and append to an undo log,
  `%LOCALAPPDATA%\VsChatHistoryToolkit\rename-log.jsonl`, which holds chat titles and summaries
  and is as confidential as the chats: never print, quote or share it. UI renames do not create
  this toolkit's undo-log entries; do not use CLI undo to reverse an untracked UI rename.

## Prerequisites / environment

- Tool: `chathistory.exe`, from VsChatHistoryToolkit, which `Install-Skills.ps1` clones and builds on
  this machine at `%USERPROFILE%\.copilot\toolkits\VsChatHistoryToolkit` (expand `%USERPROFILE%` to an
  absolute path before using it). Expected at
  `%USERPROFILE%\.copilot\toolkits\VsChatHistoryToolkit\src\VsChatHistoryToolkit.Cli\bin\Debug\net8.0\chathistory.exe`.
  If the folder or the exe does not exist, Step 0's toolkit check says what to do; do not guess a
  path or use a different clone.
- The exe is built by the toolkit's `scripts\agent\Build-Toolkit.ps1`, which `Install-Skills.ps1`
  runs (needs a .NET 8 or later SDK). Do not build it by hand.
- Clear `DOTNET_ROOT` first (`Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue`), as with
  the other skills here.
- Visual Studio may be running; reads work while it is open. Each call takes about 0.3 to 0.8
  seconds, `show` can take a few seconds for a session with a very large event log.
- Full contract: `%USERPROFILE%\.copilot\toolkits\VsChatHistoryToolkit\docs\CLI_CONTRACT.md`.

## Step 0: Version Check

Run this **once**, the first time this skill is used in a session, not on every command.

1. Find the repo clone: read `skillsRepo` from `%USERPROFILE%\.copilot\skills-source.json`, which
   `Install-Skills.ps1` writes:
   `(Get-Content "$env:USERPROFILE\.copilot\skills-source.json" -Raw | ConvertFrom-Json).skillsRepo`.
   Call it `<skills repo>` below. If the file or the folder does not exist, ask the user rather than
   guessing.
2. Check GitHub: `git -C "<skills repo>" fetch --quiet origin`. This
   changes no working file. If it fails (offline, no upstream), say once that GitHub could not
   be checked and continue with the clone alone.
3. Read this skill's entry from the repo's small `skills-index.json` (about 2 KB), not from the
   whole `SKILL.md` (which can be over 100 KB). The repo version is the higher `version` of the
   two copies below, and its `whatsNew` is the change to report. Keep only the printed `version`
   and `whatsNew`:
   - GitHub's copy (skip if the fetch failed): `(git -C "<skills repo>" show "@{u}:skills-index.json" | Out-String | ConvertFrom-Json).skills.'vs-chat-history'`
   - The clone's copy: `(Get-Content "<skills repo>\skills-index.json" -Raw | ConvertFrom-Json).skills.'vs-chat-history'`
   - If neither can be read (a repo from before the index existed), read only the version line,
     never the whole file: `Select-String -Path "<skills repo>\vs-chat-history\SKILL.md" -Pattern 'CURRENT_SKILL_VERSION\s*=\s*\d+' | Select-Object -First 1`.
4. Compare the repo version with this file's own `CURRENT_SKILL_VERSION`.
5. If the repo version is higher, say what's new (the index's `whatsNew` line; if more than one version behind, say how many and
   offer to list the older changelog entries) and whether the newer version is only on GitHub (clone not pulled yet) or already in
   the clone. Ask via `ask_user` whether to update now. On yes, run
   `& "<skills repo>\Install-Skills.ps1" -Remote -Force`: it pulls the
   clone (fast-forward only, never when tracked files have uncommitted changes), installs every
   changed skill, and clones, updates and builds the toolkits; tell the user the new text applies
   from a new chat session. On no, continue and do not ask again in this session.
6. If the versions match, continue silently.
7. Toolkit check (also when the versions match). Skip it if step 5 just ran the installer
   successfully. Run this read-only command, which changes nothing:
   `& "<skills repo>\Install-Skills.ps1" -Check -Remote -MaxAgeHours 6 | Select-String '^TOOLKIT: VsChatHistoryToolkit '`
   and act on the status word in the line:
   - `UpToDate`: continue silently.
   - `NotInstalled`, `NeedsBuild` or `Behind`: tell the user what the line says and ask via
     `ask_user` whether to run `& "<skills repo>\Install-Skills.ps1" -Remote -Force` (it clones or
     fast-forwards the toolkit and builds it, about a minute, and also installs changed skills). On
     yes, run it and check the exit code. On no, continue only if `chathistory.exe` exists
     (`Behind` works with the installed build); otherwise stop, because this skill cannot work
     without it.
   - `Diverged`, `NotAClone`, `NoDotnetSdk` or `NoGit`: report the line once and change nothing;
     continue only if `chathistory.exe` exists.
   - No `TOOLKIT:` line (an older installer): continue only if `chathistory.exe` exists, otherwise
     ask the user.
   Do not ask again in this session.

## Commands

Output is JSON on stdout (use it; add `--text` only when showing output to a person). Property
names are `snake_case`. Every success has `ok`, `command`, `coverage` and `truncated`.

| Command | Use it for | Key output |
| --- | --- | --- |
| `chathistory search <terms...> [--limit N]` | find chats that mention words | `hits[]`: `session_id`, `source_type`, `source_id`, `snippet` |
| `chathistory sessions [--repo S] [--cwd S] [--branch S] [--from DATE] [--to DATE] [--limit N]` | list or filter chats, newest first | `sessions[]`: `id`, `title`, `title_source`, `repository`, `cwd`, `branch`, `start`, `end`, `turn_count` |
| `chathistory show <id>` | one chat's details | `session`, `solution`, `solution_source`, `user_named`, `checkpoints[]` (`number`, `title`) |
| `chathistory turns <id> [--index I \| --range A-B] [--max-chars N]` | read turns in small pieces | `turns[]`: `index`, `timestamp`, `user_message`, `assistant_response`, `truncated`; `total_turns` |
| `chathistory checkpoints <id> [--full]` | a chat's checkpoints | `checkpoints[]`: `number`, `title`, `overview` (and with `--full` more fields) |
| `chathistory usage <id> [--by-turn]` | token and cost figures of one chat | `recorded`, `total` / `main` / `subagents` (`requests`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`, `reasoning_tokens`, `nano_aiu`, `credits`, `duration_ms`), `first_at`, `last_at`, `by_model[]`, `by_turn[]` with `--by-turn` |
| `chathistory files <id> [--limit N]` | files a chat edited or created | `recorded`, `files[]`: `file_path`, `tool_name` (`edit`/`create`), `turn_index`, `first_seen_at` |
| `chathistory files --path <text> [--limit N]` | which chats touched a file whose path contains the text (ASCII case-insensitive) | `sessions[]`: session id, title, file count, last turn; newest first |
| `chathistory usage-top [--from DATE] [--to DATE] [--by requests\|tokens\|aiu\|credits] [--limit N]` | rank chats by usage in a period (default by `nano_aiu`) | `sessions[]`: `session_id`, `title`, `requests`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `reasoning_tokens`, `nano_aiu`, `last_at` |
| `chathistory doctor` | read-only health report of the store (deletes nothing) | row and folder counts, rows without a folder, folders without a row, chats without turns or usage, the 10 largest event logs; counts are omitted (and `truncated` set) when the folder listing fails |
| `chathistory events <id>` | what happened inside one chat, from its event log (never prints message text, tool arguments or paths) | `scan` (`complete`), `event_counts[]`, `tools[]`, `permission_kinds[]`, `skills[]`, `aborts`, `subagents_started`, `compaction_count`, `compactions[]` (prompt size before and after, trigger, limit), `shutdowns[]` (premium requests, `nano_aiu`, lines changed, context breakdown, per-model requests and cost) |
| `chathistory rollup [--from DATE] [--to DATE] [--limit N]` | `events` combined across the most recent chats (default 20, max 100), read-only, 60 s and 512 MiB budget; limits apply when each scan starts | `chats_considered`, `chats_scanned`, `chats_skipped`, `chats_without_log`, `chats_with_incomplete_scan`, `chats_without_shutdown`, `event_counts[]`, `tools[]`, `skills[]`, `permission_kinds[]`, `aborts`, `subagents_started`, `compactions` (`count`, `by_trigger[]`, medians and max prompt size, median tokens removed), `shutdown_totals`, `top_chats_by_compactions[]` |
| `chathistory activity [--from DATE] [--to DATE] [--limit N]` | turns, chats, requests and `nano_aiu` per day (UTC), newest first | `days[]` |
| `chathistory stats` | counts, and usage over all chats | `total_sessions`, `total_turns`, `by_repository[]`, `by_cwd[]`, `by_month[]`, `usage` (`sessions_with_usage`, `total`, `by_model[]`, `by_month[]`) |
| `chathistory rename <id> "<title>" [--force] [--dry-run]` | rename a chat (writes) | `applied`, `old_title`, `new_title`, `note` |
| `chathistory undo-rename <id> [--force] [--dry-run]` | restore the last rename | same shape as rename |

How to read results:

- **Search is by word, not by substring.** `search` matches whole words and numbers; punctuation
  separates terms and all terms must match. `search "build error"` finds chats with both words, and
  `search "#include"` searches `include`. Try other wording or fewer terms before concluding that
  nothing exists. A hit's `session_id` is the id to pass to the other commands.
- **`truncated: true` means there is more or something was shortened.** Do not assume you have seen
  everything. For `search` and `sessions`, narrow the query or filters, or raise `--limit` (up to
  100) when the row limit was what cut the list; for `turns`, page with `--range`. `stats` and
  `checkpoints` cannot be paged: `stats` shows the top 25 per group, `checkpoints` returns at most
  50, and `--full` can truncate more than the default.
- **Caps are fixed.** `--limit` defaults to 20 (maximum 100); `turns` returns at most 10 turns per
  call (default `0-9`) and at most 4000 characters per message field (`--max-chars`); a response's
  total turn text is capped at 40 000 characters. A capped string can be one character longer than
  its cap (a trailing ellipsis).
- **Titles.** `title` comes from the chat's saved name (`title_source: name`), else its summary
  (`summary`), else it is empty (`none`). `user_named: true` means the name was set by a person.
- **Times.** `end` is the time of the chat's last turn (UTC, ISO-8601), not its last file update.
  `--from` and `--to` filter on that end time; use `yyyy-MM-dd` (a date-only `--to` includes that
  day).
- **Solution.** `solution` is read from the IDE context of the chat's user messages.
  `solution: "unknown"` with `solution_source: "none"` means the whole log was scanned and no
  solution line exists. `solution: "unknown"` with `solution_source: "incomplete"` means the scan
  stopped at a limit, so it does not prove the solution is absent (`truncated` is then also true).
  A solution name longer than 200 characters is shortened. The solution is never guessed from
  folders or chat text.
- **Usage figures are as stored, one row per model request.** `input_tokens` is the whole prompt of
  each request, so a chat's summed input counts the re-sent context again every request: report it
  as "tokens processed", split into input, cached (`cache_read_tokens`), `output_tokens` and
  `reasoning_tokens`, and never call it the chat's length. For the conversation's length use
  `turn_count`; the `--by-turn` request counts are usage volume (several model requests can serve
  one turn), not length. `subagents` are requests made by subagents of that chat; `main` are the
  chat's own. `nano_aiu` is the stored, token-metered cost unit. It is **not** the credits shown in
  the chat window (checked on 94 chats: there is no fixed conversion), so report the stored value
  as `nano_aiu`, never convert it, and do not call it credits. The credits figure is `credits`:
  the sum of `request_multiplier` over the requests, which matched the credits the chat window
  shows after each reply on 7 of 7 turns checked (`usage --by-turn` gives it per turn). Quote `total`: subagent requests count (a turn with two Opus requests at 15.0 and two subagent requests at 1.0 showed 32.0 in the chat window); `main` and `subagents` show the split. `credits` is omitted (null) when the store has
  no `request_multiplier` column; per chat, `events` `shutdowns[]` also has
  `total_premium_requests`. `recorded: false` is a normal answer: the chat has no usage rows (about a
  quarter of chats have none), or the store has no usage table, or the table lacks a column the
  tool needs (`note` says whether the chat has no rows or the usage table is unavailable).
  Usage numbers are confidential in aggregate like the chats: report totals the user asked for.
- **`cwd` can be a parent folder**, not the repository root; prefer `repository` and `branch`.

## Typical workflows

**Find an earlier discussion.** (1) `search` with 2 to 4 distinctive words. (2) For the best few
`session_id` values, `show <id>` to see title, repository, branch, solution and checkpoint titles.
(3) If the wording matters, `turns <id> --range a-b --max-chars 600` for just the relevant turns.
(4) Answer in your own words, naming the session id and date; quote at most a few lines.

**Find chats by place or time.** `sessions --repo <part of name> --from 2026-10-01 --limit 20`, then
`show` or `turns` on what matches. Filters are case-insensitive "contains".

**Summarise a long chat.** `checkpoints <id>` first (titles and overviews are the chat's own
summaries); read turns only for details the checkpoints lack.

**Count or overview.** `stats` (top 25 per group; check `truncated`).

**Which chat touched a file.** `files --path <part of the path>`, then `show <id>` on the best hit.
`files <id>` lists what one chat changed. Only edits and creations made through the chat's tools are
recorded, so reads, and changes made outside the chat, are not.

**What happened in a chat (compactions, tools, aborts, lines changed).** `events <id>`. If `scan.complete`
is false the log was only partly read (`truncated` is set): say so. Use it for "how often did it
compact", "what did it spend premium requests on", "which tools or skills did it use".

**Trends across chats (which tools or skills, how often chats compact).** `rollup --from <date>`. If `truncated` is true some chats were skipped or only partly read (budget, unreadable log, long compaction lists): say so, and narrow the date range or `--limit`. `by_trigger` and the medians cover only the first 25 compactions of each chat. `chats_without_shutdown` is not a crash count: the cause is not established (the session may still be open, or it ended without writing one), so do not call those chats crashed.

**How big or costly was a chat.** `show <id>` for `turn_count`, then `usage <id>` for requests and
tokens (`peak_input_tokens` and `last_input_tokens` are the chat's real context size, from main-chat
requests only); add `--by-turn` to find the expensive turns (at most 100 turns; `truncated` says more). To
rank chats by cost use `usage-top --from <date>` (then `usage <id>` on the top few). For all chats together use the `usage` section of `stats` (by model and month).

## Renaming (writes; only when the user asks)

### Choose the route by generation state, not the "Active session" label

Use an exact user-approved title; propose one and obtain approval if needed. Do not silently
trim, truncate or replace it. Invoke `ui-interaction` and follow its exact-executable preflight,
foreground/input guards, explicit read-back and cursor cleanup. Verify the intended VS host
and conversation, not the first `devenv`, newest database row or first matching title.

| Target | Route |
| --- | --- |
| This chat, whose agent is responding | Independent idle-handoff worker below; end the response before it renames. |
| Another chat, verified idle | Direct native UI below; the delayed worker is unnecessary. |
| Another chat still generating, or state unknown | Do not rename yet. Wait for verified idle or ask the user; do not stop its agent. |

The observed UI label **"Active session" means selected/displayed**, not proof of generation
or idle. A missing Cancel button in the session list is not proof another chat is idle; verify
the intended conversation itself. Preserve drafts and never send a message to establish state.

### Shared fast lookup: use the observed controls, not whole-window dumps

These selectors were observed in the tested VS Insiders chat pane. Verify them once in the
intended host; they are not a guarantee across VS versions or languages. Scope reads to the
unique visible pane with **Name `Chat` and ClassName `GenericPane`**, not a document editor or
an ancestor also named Chat. Reuse its identity during the run, but reacquire controls/row
names after navigation. A missing/ambiguous control is a reason to stop or perform one narrow
fresh discovery, not to guess a row or click coordinates.

| Purpose | Observed selector / authoritative read |
| --- | --- |
| Header / conversation identity | AutomationId `title`; exact Name includes title and working directory. |
| Return to list | AutomationId `backToHistory`, Button. |
| Actual draft | AutomationId `WpfTextView`, Name `Ask Copilot`, inside the exact chat pane; read its document text, not its Name. |
| Generation indicator | AutomationId `CancelButton`, Name `Cancel`; inspect in the displayed target conversation, not the list. |
| Session list / rows | AutomationId `session`; each row's open control is `ItemOpenButton`, Button. |
| Selected row | Name `Active session: <title>, <relative time>`; selected is not synonymous with generating. |
| Other row | Name `Session: <title>, <relative time>`; obtain the complete fresh Name before input. |
| Context action | Name `Rename`, MenuItem. |
| Inline title editor | Name `Rename`, Edit; fresh ValuePattern value is the title, not a cached property or accessibility label. |

Read only the header, draft, Cancel state, matching row and rename editor needed for the next
decision. Prefer direct UIA property/ValuePattern reads or scoped `find-all`/`get-text` over
`inspect`/`read-visible-text` on the entire VS window. Do not fetch history/database rows just
to locate a conversation already verified in the UI. Do not capture screenshots when these
controls are readable. Use the existing worker for self-renaming rather than rebuilding these
UI steps in an ad hoc script.

### This responding chat: bundled independent idle-handoff worker

Use `scripts\Invoke-IdleChatRename.ps1` relative to this installed skill's directory. It is the
canonical bundled implementation, not a script to recreate or an instruction to edit the
chat store. It requires 64-bit Windows PowerShell, readable UIA, the selected `agentdebug-ui.exe`
and `ui-interaction\scripts\AgentCursor.ps1`. Do not bypass execution policy if scripts are
blocked; report the limitation and offer a manual idle rename instead.

1. Obtain approval for the exact title and for an independent worker that can outlive this
   chat/tool call. A rename request alone is not blanket consent for a detached process. Keep
   the original conversation displayed while preparing; do not enter its rename editor.
2. Read fresh host PID, UTC process-start ticks, explicit hex HWND (`0x...`), exact current
   header (including working directory), and old title from the intended host. The helper pins
   these facts and scopes to the visible `Chat`/`GenericPane`, not another pane named Chat.
   A nonempty draft or existing rename editor is a refusal; leave it untouched.
3. Finish all preparation and choose the exact final handoff message. Include a fresh per-run
   marker in that short message so an earlier response cannot release a later worker. Hash its
   UTF-8 bytes with SHA256 after normalizing CRLF and lone CR to LF and trimming surrounding
   whitespace. Hash the entire final message, not just its marker. It must say **scheduled,
   pending verification**, not that the title is already saved. Do not log the message text.
4. Build one parameter map using only freshly verified values:

   | Parameter | Value |
   | --- | --- |
   | `UiExe`, `CursorScript` | Exact verified UI executable and installed cursor-helper paths. |
   | `HostProcessId`, `HostStartTicks`, `WindowHandle` | Pinned host PID, `.StartTime.ToUniversalTime().Ticks`, and explicit hex HWND. |
   | `ExpectedHeader`, `OldTitle`, `NewTitle` | Exact observed header/old title and exact approved new title (1..120 characters). |
   | `ReadyMessageHash` | SHA256 of the entire final handoff message from step 3. |
   | `ResultPath` | Unique new absolute JSON path in an existing private session folder outside Git. |
   | `DelaySeconds` | Use `2` for an independent launch; the backward-compatible default remains `20`. |

   Run the helper once with that map and `-ValidateOnly`; require `validated:true` and
   `mutationAttempted:false`. It checks identity/header/draft and performs no input or writes.
   Defaults remain `IdleTimeoutSeconds=120`, `StableIdleSeconds=3`, `PollMilliseconds=500`,
   `VerificationSeconds=5`; shortening the initial delay does not bypass the idle checks.
5. Launch the **same installed helper** with the same map, without `-ValidateOnly`, in a separate
   hidden Windows PowerShell process (`-NoLogo -NoProfile -NonInteractive -STA`). Use a short-lived
   `Start-Process` launcher with no `-Wait`, unique private stdout/stderr files and a recorded
   worker PID/start time. Preserve argument values exactly; an `-EncodedCommand` invocation can
   transport properly quoted paths/parameters, but is not execution-policy bypass. Use the tool's
   independent/detached launch mechanism only with the permission from step 1.

   **Do not run the worker itself as a tracked async tool/job or wait for it in this response.**
   That kept this chat working during the live test and prevented the idle gate from opening.
   Verify once that the worker is alive, its private result reports `Waiting`, and the launcher
   has exited before handoff. A failed/missing startup result is not a successful schedule.

   **Launch recipe:** In a short-lived independent tool invocation, let `$workerScript` be
   the installed helper's absolute path and `$renameParameters` the map from step 4, with
   `DelaySeconds=2` and without `ValidateOnly`. Use the following launcher rather than a
   tracked invocation of the worker itself. The permission in step 1 is required. If the tool
   has a detached/independent switch, use it for this short launcher, not a wait/poll job.

   ```powershell
   $ErrorActionPreference = 'Stop'
   if ([IntPtr]::Size -ne 8) { throw 'Use 64-bit Windows PowerShell for this launcher.' }
   $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
   $stdout = $renameParameters.ResultPath + '.stdout.txt'
   $stderr = $renameParameters.ResultPath + '.stderr.txt'
   foreach ($path in @($stdout, $stderr)) {
       if (Test-Path -LiteralPath $path) { throw 'Choose fresh private output paths.' }
   }
   $serialized = [Management.Automation.PSSerializer]::Serialize($renameParameters)
   $payload = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($serialized))
   $quotedScript = $workerScript.Replace("'", "''")
   $command = '$p = [Management.Automation.PSSerializer]::Deserialize(' +
       '[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(''' + $payload +
       '''))); & ''' + $quotedScript + ''' @p'
   $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
   $worker = Start-Process -FilePath $powerShellExe -ArgumentList @(
       '-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-EncodedCommand', $encoded
   ) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
   [pscustomobject]@{
       workerPid = $worker.Id
       workerStartTicks = $worker.StartTime.ToUniversalTime().Ticks
       resultPath = $renameParameters.ResultPath
       stdoutPath = $stdout
       stderrPath = $stderr
   } | ConvertTo-Json
   ```

   Wait only for this short launcher to finish and record its output. Check worker PID/start
   time and startup result once; if the result is not ready, make only bounded read-only
   startup checks, not UI polling or rename retries. Do not keep a tracked startup check
   alive for the worker's idle/rename phase. Never print the serialized parameters/command.
6. Finish any enabled generic notification/speech and cursor handback before the final message.
   Never send a Completed alert for merely scheduling. Then emit exactly the hashed handoff
   message and **end the response**: no further tools, polling, progress or follow-up messages
   while waiting for idle. The worker waits for that visible message, stable absence of Cancel,
   the same header, an empty draft and no editor before navigating. Changed context aborts.
   After that gate it makes one cursor-guarded, verified foreground request; denial aborts
   before navigation. It does not loop activation or retry a rename.
7. After a later user turn, read the private result rather than starting another rename. Claim
   completion only for `state:Completed` with `idleVerified`, `readyMessageSeen`,
   `foregroundVerified`, `typedTitleVerified`, `savedTitleVerified`, `reopenedTitleVerified`,
   `reopenedContextVerified` and `cursorCleanupVerified` all true. Missing/pending/failed results
   are not success. Inspect `failure`, `phase`, idle observations and phase/CLI timings; report
   the observed failure without exposing chat text. Do not treat stderr file size alone as an
   error: Windows PowerShell can emit module-preparation progress there.

The worker commits once, checks that the editor closed, verifies the saved row, and reopens
the same conversation with its title and exact handoff context verified. It never submits a
message, retries an uncertain rename, forces CLI writes, restarts VS or edits chat storage.
On a failure after mutation begins, report the recorded state and ask for manual assistance;
do not blindly repeat Enter, Escape or the rename.

**Observed validation:** Direct self-renaming during generation left the editor open twice.
Renaming another idle chat succeeded; one independently deferred idle self-rename also
succeeded. A tracked worker timed out before navigation. These support the workaround, not a
proven VS root cause or universal fix. The optimized independent rename-and-restore cycle
subsequently passed all idle/foreground/title/context/cursor checks. The new direct-idle test
needed clipboard-guard recovery and restored its original title/context, but its older caller
message was not exposed for the return check; this was not a clean full-pass test. Timings are
host-specific observations, not guaranteed durations or proof of a universal speedup.

### Another idle chat: direct native UI, no delayed worker required

Use this fixed order once identity, idle state and title approval are established:
**Back -> exact row -> Rename -> read old -> select/paste -> read typed -> Enter once ->
editor closed + saved row -> reopen target + verify -> return to caller + verify.**

1. Capture the caller's exact title/header and distinctive context so you can return. Preserve
   drafts. Click `backToHistory` once and require header `Sessions`. For a request such as
   "the second chat", enumerate visible UI rows in their actual list order, not database order.
   Identify that row before any title proposal; duplicate names require disambiguation.
2. Open the target only if needed to establish identity, idle state or an appropriate title.
   Read capped, distinctive content, require no visible Cancel in that target, and preserve
   its draft. If proposing a title, return to the verified caller before asking for approval;
   after approval reacquire the target and recheck header/idle state, not its full transcript.
   If the same target was already verified in this run and remains unambiguous/idle, do not
   reread its full contents.
   Return with `backToHistory`; require `Sessions` and reacquire that exact row's full Name.
3. Right-click that uniquely matched row, then invoke the unique observed `Rename` MenuItem.
   Do not right-click a guessed coordinate or whichever duplicate appears first. Require one
   visible `Rename` Edit with ValuePattern and read its value; it must equal the observed old
   title before typing. If the target starts generating or its state is unknown, defer.
4. Focus the editor and select all once. Paste the approved title with clipboard preservation
   (`paste-text --restoreDelayMs 1000` on the verified binary), then read a **fresh** editor
   ValuePattern value. Require exact equality and verified clipboard preservation. Do not use
   ValuePattern setting as an unverified substitute for typing, infer success from a CLI flag,
   or lower the clipboard wait merely to save time.
   Preservation requires `clipboardSnapshotComplete:true`; `clipboardRestored:true` means
   restored content, while an omitted restoration field with a complete snapshot means the
   clipboard was empty. Reject false, unknown or incomplete results, not that documented no-op.
5. Press Enter **once**. Require both the editor to disappear and the exact saved title to
   appear on the same uniquely identified row. Reacquire the full saved row Name; its relative
   timestamp may have changed. If the editor stays open, stop: do not repeat Enter/Escape,
   invoke CLI force or restart VS. Honor validation failures without silently changing title.
6. Open the saved target row once. Verify its new header and distinctive original context,
   then Back and reopen the original caller by its verified identity. Verify the caller's
   header/context and perform cursor/focus handback. Report incomplete checks as unverified.
   Earlier messages can be virtualized out of the exposed tree; use short, currently rendered
   distinctive context rather than repeatedly dumping/scanning the whole chat for an old hash.
   If context cannot be reacquired, report that limitation instead of declaring the wrong chat
   or claiming full verification from its header alone.

Batch adjacent input actions in one red-cursor block, but keep the old/typed/saved/reopened
read-backs: these are safety boundaries, not avoidable overhead. No delayed worker, detached
process, 20-second sleep, full-tree dump or repeated database search is needed for this route.

To undo a UI rename, use the appropriate idle-only UI route with the prior approved title
when asked. Do not assume CLI undo has recorded a native UI rename.

### CLI alternative: stored-session rename and undo

Keep the existing CLI safety contract. For this responding chat use the independent idle
worker above, never an automatic forced CLI rename. This route's dry-run, force, undo-log and
restart rules do not apply automatically to a native UI rename.

1. Run `rename <id> "<title>" --dry-run` first and show the user the old and new title. The id must
   be the exact session id (from `sessions` or `search`).
2. If the user confirms, run it without `--dry-run`. A title is trimmed, control characters are
   removed, and it must be 1 to 120 characters (longer is refused, not cut). Put `--` before a title
   that starts with `-`.
3. The tool cannot tell which chat is the current one; it only checks for activity in the last
   10 minutes (changes to the chat's event log or
   `workspace.yaml`, or a recent turn) and refuses with exit code 4. Do **not** add `--force`
   yourself: tell the user why it was refused, and run it with `--force` only if the user explicitly
   says to. (Tested: a forced rename of a recently used chat works and Visual Studio does not
   write the old title back, but that is the user's call, not yours.)
4. For this CLI route, always end by telling the user: **"New title appears after Visual Studio
   restarts."** This is the stored-title CLI behavior documented by the toolkit, not proof
   that a native UI rename also needs a restart.
5. `undo-rename <id>` restores the previous title and summary of the last rename (repeat to go back
   further). It refuses with exit code 4 if the title, the `user_named` line or the summary changed
   after the rename (someone or Visual Studio edited it); do not force that without the user's
   say-so.
6. Rename changes only the chat's `name:`/`user_named:` lines and its stored summary. Check the
   result's `applied` and `warnings` fields; a warning means the final undo-log entry could not be
   written, so tell the user.

## Exit codes and what to do

| Code | `error.code` | Meaning and action |
| --- | --- | --- |
| 0 | | success |
| 1 | `usage` | bad arguments or nothing searchable (only punctuation); fix the call |
| 2 | `not_found` | no such session row, a missing session folder or `workspace.yaml` (rename and undo), or nothing to undo; re-check the id with `sessions`/`search` |
| 3 | `store_unavailable`, `schema_mismatch` | reading failed: database missing or cannot be opened, an unsupported schema version, or an unexpected `schema_version` table (zero or several rows, or a NULL version); report the message to the user, do not work around it |
| 4 | `refused` | session looks active or recently used, a safety check failed, or undo target changed; report, do not use `--force` on your own |
| 5 | `write_failed` | rename or undo could not be applied (for example the database write lock, the undo log or the file replace failed); the message says what state was left (usually nothing changed); report it |
| 6 | `internal` | unexpected; report the message |

In JSON mode (the default) errors are JSON on stdout:
`{"ok":false,"coverage":"session-store.db only","error":{"code","message"}}`. With `--text`, errors
go to stderr as `error (<code>): <message>`.

## Limitations

- Coverage is `session-store.db` only. Some chats listed in Visual Studio are not in it.
- Search is word-based; it is not a substring or regular-expression search.
- Usage covers only chats that have rows in `assistant_usage_events`; it cannot say what a reply
  "cost" in the chat window's credits, and it has no per-message token count (one row is one model
  request, several of which can serve one reply).
- Large or recently written chats can be slow to `show` (the event log is scanned for the solution).
- The tool never prints a whole chat; use `turns` ranges for more, in small steps.
- CLI rename and undo are the only CLI writes, and only for one session by exact id. Native UI
  renaming is a separate user-requested workflow above, with its own identity/read-back checks.
