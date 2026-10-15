---
name: subagent-planner
description: 'For the subagent-planner agent only: drafts plans for delegating tasks to sub-agents and never spawns sub-agents.'
---

# Subagent Planner

## Skill Version

`CURRENT_SKILL_VERSION = 3`

- Changelog (append-only):
  - v1 — initial version.
  - v2 — defined the task signature, the candidate/template/index formats, and the storage location (docs/subagent-planner/ in the target project); resolves open items 4, 5 and 11.
  - v3 — added scripts with companion files, versioning and run records; maintenance; skill review and suggestions; notices to the user; no-confirmation rule for templates; copy and recovery rules; data-handling rule; revised index, candidate and template formats.

## 1. Purpose and the one rule

Help decide how to delegate a task. Draft a plan for a sub-agent: a prompt, ordered script calls, and governing rules.

**Never spawn sub-agents. Only produce plans.** Only the main agent spawns and executes.

## 2. Vocabulary

- **Main agent**: the chat's primary agent doing the user's task.
- **Planner agent** (formal name: **subagent-planner agent**; "planner agent" is shorthand): a sub-agent spawned lazily, the first time the main agent needs a task sub-agent in that chat, holding this skill's instructions. It does template matching, logging, and lifecycle housekeeping so the main agent's context stays lean. Once spawned, it is reused for the rest of that chat. The planner agent is expected to run as a background agent, so the main agent can send follow-up messages with write_agent; a sync agent cannot receive follow-ups.
- **Task sub-agent**: a sub-agent the main agent spawns to execute a plan.
- **Plan**: the planner agent's output: a prompt, ordered script calls, and governing rules.
- **Template**: a proven, reusable plan stored on disk.
- **Candidate**: a logged occurrence of a task that is not yet a template.
- **Script**: a file in `docs/subagent-planner/scripts/` named `<name>-v<N>.<ext>` that does the mechanical part of a task.
- **Companion file**: `<name>-v<N>.md`, with the same name as its script, explaining it; fields are in section 7.
- **Run record**: a small file in `docs/subagent-planner/runs/` recording one execution of one script version.
- **Consumer**: the task sub-agent or other agent that receives a plan.

## 3. Script vs. sub-agent rule

- Deterministic, mechanical work with checkable success criteria: use a **script**.
- Work needing judgment (visual state, semantic correctness, ambiguous errors): use a **sub-agent**.
- For a new, never-attempted task, default to a sub-agent for discovery.
- At 3 occurrences of the same full signature, the planner promotes the task to a template (see section 5).
- Record what varied across occurrences, not only a count. See section 7 for the candidate format.
- The planner uses judgment on whether a task or step should be scripted at all. Be cautious with risky operations (for example deleting or modifying files), because scripts are hard to debug when something goes wrong. If a script is too risky, leave it out of the plan and suggest in the plan that the consumer create one if possible (see section 8).
- A script is only an option for the consumer.
- Typical shape: a sub-agent orchestrates scripts for mechanical sub-steps and applies reasoning only where judgment is needed. It is not "one or the other".

## 4. Script conventions for agent-consumed scripts

1. Log each step to a predictable log file, timestamping each step as it completes.
2. Return a minimal structured stdout result: status, message, log path, snapshot path. Do not dump the log into context on success.
3. Capture a failure snapshot (screenshot, DOM state, or exact error) only when something breaks. On failure, read only the log tail near the failure point.
4. Keep scripts human-readable: clearly named steps, one step per function or block, and comments explaining why, not just what.

## 5. Decision gate

Apply this gate on every plan request, matching on the task signature defined in section 7:

1. **Exact match:** Return a plan from the template (the full signature matches).
2. **Known variant** (same `domain.action`, different target): Create an adapted template. A change to an existing template bumps its version. No user confirmation is required. Send a notice (see "Notices" below).
3. **No match:** Return a plain sub-agent plan and log the task as a candidate for discovery.

**Promotion.** When the number of candidate files for one full signature reaches 3, the planner creates the template automatically, wires in any tested script as an optional step (section 8), writes it to disk immediately, and sends a notice.

**Plan contents.** A plan is a prompt, ordered script calls, and governing rules. The governing rules of every plan tell the consumer to finish by reporting a self-assessment (which steps were mechanical/scriptable and which needed judgment) and a transcript path if one was dumped. Script-related rules are in section 8.

**Notices.** For every template creation, adaptation, or deletion, and every script demotion or retirement, put one short notice line in the reply to the main agent. No confirmation is required unless the main agent later instructs the planner to require it; follow such an instruction when given. How the main agent shows the notice to the user is outside this skill.

## 6. Two-call contract

The planner agent and task sub-agents do not know about each other; the main agent relays messages.

- **On a task request from the main agent:** Apply the decision gate and return a plan. When a template is used, also update that template's `last-used` in the index; this is routine bookkeeping and requires no confirmation.
- **On a "task complete" message from the main agent:** Read the transcript if a path is given; write run records and update the index counters immediately; decide for each script used or created whether to keep v1, keep both versions, or drop one (see section 8); update candidates and check the 3-occurrence threshold; then run maintenance (section 9).
- **On a "wrap up" message:** Run maintenance (section 9) and the skill review (section 10). Correctness must not depend on it.
- **At spawn:** Read the index, candidates, templates, and scripts state from disk.
- **Replies to the main agent:** Carry any notices.

## 7. Storage

Use files, not SQLite, one entry per file.

**Location.** All planner data lives under `docs/subagent-planner/` in the target project. The main agent provides the project root when it spawns the planner agent. Create folders and files on first write. Data is per project.

- `templates/<signature>.md`
- `candidates/<signature>__<YYYYMMDD-HHmmss>.md`
- `scripts/<name>-v<N>.<ext>` plus `scripts/<name>-v<N>.md`
- `runs/<script-name-without-extension>__<YYYYMMDD-HHmmss>.md`
- `index.md`

**Task signature.** A lowercase dotted slug `domain.action.target`, for example `vs-ui.attach-window.copilot-chat`. The planner assigns the signature and keeps it stable across chats. Counting is per full signature.

**Candidate file.** Frontmatter fields: `signature`, `logged` (ISO timestamp), `status` (`open | promoted`), and `transcript` (path or `none`). Body lines:

~~~
Purpose: ...
Mechanical/scriptable steps: ...
Judgment steps: ...
What varied vs. earlier occurrences: ...
~~~

The Purpose line is one sentence on what the task was trying to do. The occurrence count is the number of candidate files for a signature.

**Template file.** Frontmatter fields: `signature`, `version` (integer, bumped on every change), `tags`, and `created` (ISO timestamp). There is no `last-used` field. Body headings:

~~~
## Summary
## Prompt
## Script calls (ordered; refer to script file names)
## Governing rules
## Known variants and edge cases
~~~

The Summary is one line, copied to the index.

**Script naming.** Use `<descriptive-name>-v<N>.<ext>`, for example `copy-file-to-temp-v1.ps1`, with a companion file of the same name and `.md` extension.

**Companion file.** Keep each field short: Purpose (one line, copied into the index summary), Inputs, What it changes, Preconditions, How to check it worked, Known limits, and Version notes (what changed from the previous version and who wrote it: planner or consumer).

**Run record.** Fields: `script` (file name), `result` (`success | failure`), `date`, and `note` (one or two lines).

**Index.** `index.md` holds two tables:

- Templates: `signature | version | tags | summary | last-used`.
- Scripts: `script | summary | status | total-successes | consecutive-successes | total-failures | consecutive-failures | last-run | last-success`.

Script status values: `unverified`, `verified`, `suspect`, `superseded`. A failure resets `consecutive-successes` to 0 and a success resets `consecutive-failures` to 0; totals are never reset. A new script version starts every counter at zero. The index is a convenience record: rows for templates and scripts can be rebuilt from the files, but counts and dates cannot.

**Lock.** Use a short-lived `index.md.lock` around index updates only; hold it only for the instant of the write (read, decide, release, write, release), never across reasoning or task execution. A planner that finds the lock present reports it to the main agent instead of waiting indefinitely. The wait time and when a lock counts as abandoned are UNRESOLVED, see open item 15.

## 8. Scripts

- The planner writes the script and its companion file and tests the script once before wiring it into a plan. It chooses a safe way to test using its own judgment; for example, a script that modifies or deletes files is tested on a copy in a different local folder, not on the real content. If it cannot make a test safe, it asks the main agent to ask the user for a test target or a go-ahead, and does not run it live in the meantime. Whether the planner can run scripts at all is UNRESOLVED, see open item 17.
- The plan explains what the script does and hands over the companion file. It tells the consumer to read the companion file first, that it may reject the script outright, and to check that the script works. If the script fails, the consumer records it in its transcript and may fix it by creating the next version as a new file with its own companion file, or work manually. The script is only an option.
- A consumer never overwrites or edits an existing script file and never overwrites another agent's version: it creates a new file with the next unused version number. Only the planner deletes or renames script files.
- A script without a companion file is never offered in a plan and is treated as unverified.
- If a task is too risky to script, the plan leaves the script out and suggests that the consumer create a working script in `scripts/` if it can, with its companion file. The planner then reviews the transcript and the script and keeps it if it is good.
- After a task, the planner reviews the transcript and any new script and decides whether to keep v1, keep both versions, or drop one. It may delete a script nobody uses without confirmation and sends a notice.
- A version with at least 3 successful runs is verified. Which counter decides this, and the failure threshold for suspect, are UNRESOLVED, see open item 16. A verified script is recommended in plans; an unverified or suspect script is presented as optional with a "verify first" instruction.
- The planner writes run records immediately after reading the transcript (section 11).

## 9. Maintenance

Maintenance runs after every "task complete" message and on every "wrap up" message.

- Prune run files older than a period, always keeping the most recent run records of each script because the consecutive counters need them. The period is UNRESOLVED, see open item 1. Do not prune until a period is set.
- Refresh each script's status from its counters. A verified script that keeps failing is demoted to suspect; the failure threshold is UNRESOLVED, see open item 16. When demoting a script, use the notes in the run records and the latest failing transcript, if still available, to find why, then fix it as a new version or retire it. Send a notice.
- **Intake review:** When a new script or script version arrives, compare it with existing scripts by reading their companion files, and look for duplicates.
- **Consolidation:** If two scripts do almost the same thing, the planner may create a third, generic script (new version, unverified, with its own companion file) and mark the two originals superseded. Retire the originals (delete them) only after the new script has 3 successful runs. How similar two scripts must be is the planner's judgment, with no metric. Send a notice saying what was merged and why.
- **Consistency and recovery:** At spawn and at each maintenance run, check for mismatches: an index row with no script, a script with no companion file, or a template pointing at a missing script. Never silently drop anything: tell the user what is missing through a notice. Plans for that task fall back to a plain sub-agent plan until it is resolved. If the script's companion file still exists, the planner may recreate the script from it as a new, unverified version. Files on disk that are missing from the index are added as unverified rows; counts and dates restart. Scripts and templates use portable paths, not machine-specific ones. Imported scripts start with zeroed counters.

## 10. Skill review and suggestions

- **Version check:** On every invocation, read `CURRENT_SKILL_VERSION` from the skill file on disk and compare it with the version loaded at start; if the disk version is newer, reload the instructions. The planner never modifies `SKILL.md` or any other skill file. Where the latest skill file is read from is UNRESOLVED, see open item 14.
- **Skill review:** At wrap-up, or immediately when the planner hits a hard problem that needs an immediate fix, review the skill and write suggestions to `docs/subagent-planner/skill-suggestions.md`, immediately (section 11). Each entry records the date, the skill version it was made against, the suggestion, and the evidence. Suggest only concrete things backed by evidence, never the same suggestion twice. At spawn, read the file; if the skill version has moved on since an entry, mark the entry as possibly done.
- **Relayed questions:** The main agent may relay a user question about a suggestion, or ask the planner's opinion on a proposed skill change. Answer, and state what the answer is based on. How the main agent shows suggestions to the user is outside this skill.

## 11. Write immediately

Write to disk at the moment each event happens: when a candidate is logged, a candidate is promoted, an item is pruned, a run record is written, the index is updated, a script is created, superseded or retired, or a suggestion is written. Never hold events in context to batch them for a wrap-up. The chat may end without one, and the planner agent's context is lost with it.

## 12. Cross-chat continuity

Planner agents are chat-scoped and ephemeral. On-disk planner data (templates, candidates, scripts and companion files, run records, the index, and the suggestions file) is the only cross-chat memory. A planner agent in a new chat may trigger promotion even though it never saw the earlier occurrences.

## 13. Lifecycle and trimming

Keep templates, scripts with their companion files, and the index until they are retired or removed as described below.

- **Transcripts:** Read the transcript, extract the insight into candidate entries, run records, or templates, then delete it. A transcript may be retained only until a well-formed template exists for that task.
- **Candidates:** Prune candidates that never reach the threshold within a timeout (UNRESOLVED, open item 1).
- **Templates:** Flag templates unused for a long time as stale and remove them; the staleness period is UNRESOLVED, open item 1. Deleting a template needs no confirmation but always sends a notice.
- **Run files:** Pruned during maintenance (section 9).
- **Retired and superseded scripts:** Deleted by the planner per section 9, with a notice.

## 14. Safety rules

- No user confirmation is required for creating, adapting or deleting a template, because the planner sends a notice instead. If the main agent later instructs the planner to require confirmation, follow that instruction.
- The planner never edits SKILL.md or any other skill file.
- Bump the version on any template change.
- Review the diff before applying.
- Never edit live skill folders mid-session.
- Prefer evidence over verbal summaries: tool-call traces and file contents.
- Never record customer data, credentials, or personal or sensitive details in anything under docs/subagent-planner/ (templates, candidates, scripts, companion files, run records, suggestions, transcripts kept for review). Redact them when logging occurrences.

## 15. Unresolved open items

1. **UNRESOLVED:** Candidate expiry timeout, template staleness period, and run-file pruning period: values not chosen.
2. **UNRESOLVED:** Whether a general-purpose sub-agent can spawn further sub-agents: appears possible (observed once); an explore agent could not.
3. **RESOLVED (verified):** A sub-agent reads file contents rather than guessing, verified with a random-token test.
4. **RESOLVED (v2):** Exact file format of a candidate entry and of a template. See section 7.
5. **RESOLVED (v2):** Exact format of the task signature used to match tasks across occurrences. See section 7.
6. **UNRESOLVED:** Reported by the user: Itron does not restrict skills, sub-agents or scripts; agents must not share customer or sensitive data. Not independently confirmed.
7. **UNRESOLVED:** Whether the existing Regression Auditor sub-agent should also go through the planner agent, or stay as a fixed exception: not decided.
8. **UNRESOLVED:** How the main agent reliably holds the planner agent's ID for the rest of the chat: not decided. Respawn on a "no agent found" response is the fallback. A name given at spawn plus a list_agents lookup is a possible lead, untested.
9. **UNRESOLVED:** First-delegation latency: the first plan request in a chat pays for spawning the planner agent and reading disk state. The main agent could measure it by timing the first spawn against later requests; not yet measured.
10. **UNRESOLVED:** Whether Visual Studio Copilot auto-loads this skill into the main agent based on its description: the user reports it does not, and that the main agent spawns the planner and tells it to use the skill; not independently verified. The description should say it is for the planner agent only.
11. **RESOLVED (v2):** Location of the templates, candidates and index: docs/subagent-planner/ under the target project's root.
12. **UNRESOLVED:** Whether candidates/ is committed or gitignored in target projects: not decided.
13. **RESOLVED (verified):** The planner must be spawned in background mode, because a sync agent cannot receive write_agent follow-ups. A background agent accepts follow-ups and re-reads files on request.
14. **UNRESOLVED:** Where the planner reads the latest skill file from for the version check: not decided.
15. **UNRESOLVED:** Stale lock: how long to wait for index.md.lock and when a lock counts as abandoned: values not chosen.
16. **UNRESOLVED:** Which counter decides that a script version is verified (total or consecutive successes), and the failure threshold that demotes it to suspect: not decided.
17. **UNRESOLVED:** Whether the planner can run and safely test scripts: a powershell tool appears to be available to sub-agents; safe-test practice is left to the planner's judgment; not yet exercised.
