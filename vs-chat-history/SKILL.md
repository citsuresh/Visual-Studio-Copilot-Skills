---
name: vs-chat-history
description: 'Search and read the Visual Studio Copilot Chat history stored on this machine through the chathistory CLI (VsChatHistoryToolkit): full-text search over turns and checkpoints, list and filter sessions, show a session (repository, branch, solution, checkpoint titles), read capped excerpts of turns and checkpoints, count sessions, and, only when the user asks, rename a chat or undo the rename. Use for: "what did we decide about X in an earlier chat", "find the chat where I worked on Y", "which solution was that chat in", "how many chats do I have". Read-only except rename and undo-rename. Covers session-store.db only, so chats missing from that database are invisible. Chat text is confidential: show short excerpts only.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 4`. Compare against the source-of-truth copy at
  `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\vs-chat-history\SKILL.md` once at the start of a
  session (Step 0).
- Changelog:
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
`chathistory` command-line tool. The tool does the database work; this skill only says how to call
it, how to read its output, and what to keep private.

## Rules that always apply

- **Chat text is confidential** (Itron work). Never paste whole chats or long passages. Quote
  only short excerpts (a few lines) that answer the question, and only when the user needs the
  wording. Prefer a summary in your own words with the session id so the user can look it up.
- **Never read or copy the store yourself.** Do not open `session-store.db` with another tool, do
  not copy it, do not read `events.jsonl` or `workspace.yaml` directly, and do not run SQL. Use
  only the commands below. Every command except `rename` and `undo-rename` opens the database
  read-only. Every answer is capped; in a `rename` or `undo-rename` result every shown value
  (`old_title`, `new_title` and the name line, `user_named` line and summary in `before` and
  `after`) is cut to 200 characters and `truncated` is then true. Still report only the status,
  the titles and any warning, not the whole result.
- **Never write chat text into files, commits, PR descriptions or notes** unless the user asks.
  Redact credentials, tokens, account numbers and personal data if they show up in an excerpt.
- **State the coverage.** Every result has `"coverage": "session-store.db only"`. The chat pane can
  list more chats than the database holds, so "not found" means "not in session-store.db".
- **Only `rename` and `undo-rename` write.** They change one chat's `workspace.yaml` and stored
  summary and append to an undo log, `%LOCALAPPDATA%\VsChatHistoryToolkit\rename-log.jsonl`, which
  holds chat titles and summaries and is as confidential as the chats: never print, quote or share
  it. Use these two commands only when the user asks (see Renaming).

## Prerequisites / environment

- Tool: `chathistory.exe`, built from `C:\MyFiles\Git\VsChatHistoryToolkit`
  (`src\VsChatHistoryToolkit.Cli`). Expected at
  `C:\MyFiles\Git\VsChatHistoryToolkit\src\VsChatHistoryToolkit.Cli\bin\Debug\net8.0\chathistory.exe`.
  If the folder does not exist, stop and ask the user where the toolkit is; do not guess.
- If the exe is missing or older than the source, build it:
  `dotnet build C:\MyFiles\Git\VsChatHistoryToolkit\VsChatHistoryToolkit.slnx` (needs the .NET 8
  runtime; the machine's default SDK may be newer, which is fine).
- Clear `DOTNET_ROOT` first (`Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue`), as with
  the other skills here.
- Visual Studio may be running; reads work while it is open. Each call takes about 0.3 to 0.8
  seconds, `show` can take a few seconds for a session with a very large event log.
- Full contract: `C:\MyFiles\Git\VsChatHistoryToolkit\docs\CLI_CONTRACT.md`.

## Step 0: Version Check

Run this **once**, the first time this skill is used in a session, not on every command.

1. Read `CURRENT_SKILL_VERSION` from the repo copy at
   `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\vs-chat-history\SKILL.md`. If that path does not
   exist, ask the user rather than guessing.
2. Compare it with this file's own `CURRENT_SKILL_VERSION`.
3. If the repo version is higher, say plainly what changed and that the installed copy is stale;
   recommend `Install-Skills.ps1` and let the user decide.
4. If the versions match, continue silently.

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
| `chathistory usage <id> [--by-turn]` | token and cost figures of one chat | `recorded`, `total` / `main` / `subagents` (`requests`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`, `reasoning_tokens`, `nano_aiu`, `duration_ms`), `first_at`, `last_at`, `by_model[]`, `by_turn[]` with `--by-turn` |
| `chathistory files <id> [--limit N]` | files a chat edited or created | `recorded`, `files[]`: `file_path`, `tool_name` (`edit`/`create`), `turn_index`, `first_seen_at` |
| `chathistory files --path <text> [--limit N]` | which chats touched a file whose path contains the text (ASCII case-insensitive) | `sessions[]`: session id, title, file count, last turn; newest first |
| `chathistory usage-top [--from DATE] [--to DATE] [--by requests\|tokens\|aiu] [--limit N]` | rank chats by usage in a period (default by `nano_aiu`) | `sessions[]`: `session_id`, `title`, `requests`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `reasoning_tokens`, `nano_aiu`, `last_at` |
| `chathistory doctor` | read-only health report of the store (deletes nothing) | row and folder counts, rows without a folder, folders without a row, chats without turns or usage, the 10 largest event logs; counts are omitted (and `truncated` set) when the folder listing fails |
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
  chat's own. `nano_aiu` is the stored cost unit; its relation to the credits shown in the chat
  window is **not verified**, so report the stored value as `nano_aiu`, never convert it, and do
  not call it credits. `recorded: false` is a normal answer: the chat has no usage rows (about a
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

**How big or costly was a chat.** `show <id>` for `turn_count`, then `usage <id>` for requests and
tokens (`peak_input_tokens` and `last_input_tokens` are the chat's real context size, from main-chat
requests only); add `--by-turn` to find the expensive turns (at most 100 turns; `truncated` says more). To
rank chats by cost use `usage-top --from <date>` (then `usage <id>` on the top few). For all chats together use the `usage` section of `stats` (by model and month).

## Renaming (writes; only when the user asks)

1. Run `rename <id> "<title>" --dry-run` first and show the user the old and new title. The id must
   be the exact session id (from `sessions` or `search`).
2. If the user confirms, run it without `--dry-run`. A title is trimmed, control characters are
   removed, and it must be 1 to 120 characters (longer is refused, not cut). Put `--` before a title
   that starts with `-`.
3. **Never rename the chat you are working in.** The tool cannot tell which chat is the current one;
   it only checks for activity in the last 10 minutes (changes to the chat's event log or
   `workspace.yaml`, or a recent turn) and refuses with exit code 4. Do **not** add `--force`
   yourself: tell the user why it was refused, and run it with `--force` only if the user explicitly
   says to. (Tested: a forced rename of a recently used chat works and Visual Studio does not
   write the old title back, but that is the user's call, not yours.)
4. Always end by telling the user: **"New title appears after Visual Studio restarts."** The chat
   list is read once at start-up.
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
- Rename and undo are the only writes, and only for one session by exact id.
