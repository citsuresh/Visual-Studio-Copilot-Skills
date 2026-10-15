---
name: subagent-planner
description: 'For the subagent-planner agent only: drafts plans for delegating tasks to sub-agents and never spawns sub-agents.'
---

# Subagent Planner

## Skill Version

`CURRENT_SKILL_VERSION = 2`

- Changelog (append-only):
  - v1 — initial version.
  - v2 — defined the task signature, the candidate/template/index formats, and the storage location (docs/subagent-planner/ in the target project); resolves open items 4, 5 and 11.

## 1. Purpose and the one rule

Help decide how to delegate a task. Draft a plan for a sub-agent: a prompt, ordered script calls, and governing rules.

**Never spawn sub-agents. Only produce plans.** Only the main agent spawns and executes.

## 2. Vocabulary

- **Main agent**: the chat's primary agent doing the user's task.
- **Planner agent** (formal name: **subagent-planner agent**; "planner agent" is shorthand): a sub-agent spawned lazily, the first time the main agent needs a task sub-agent in that chat, holding this skill's instructions. It does template matching, logging, and lifecycle housekeeping so the main agent's context stays lean. Once spawned, it is reused for the rest of that chat.
- **Task sub-agent**: a sub-agent the main agent spawns to execute a plan.
- **Plan**: the planner agent's output: a prompt, ordered script calls, and governing rules.
- **Template**: a proven, reusable plan stored on disk.
- **Candidate**: a logged occurrence of a task that is not yet a template.

## 3. Script vs. sub-agent rule

- Deterministic, mechanical work with checkable success criteria: use a **script**.
- Work needing judgment (visual state, semantic correctness, ambiguous errors): use a **sub-agent**.
- For a new, never-attempted task, default to a sub-agent for discovery.
- After a task has needed a sub-agent 3 times, it becomes a candidate for conversion to a script or template.
- Record what varied across occurrences, not only a count. See section 7 for the candidate format.
- Typical shape: a sub-agent orchestrates scripts for mechanical sub-steps and applies reasoning only where judgment is needed. It is not "one or the other".

## 4. Script conventions for agent-consumed scripts

1. Log each step to a predictable log file, timestamping each step as it completes.
2. Return a minimal structured stdout result: status, message, log path, snapshot path. Do not dump the log into context on success.
3. Capture a failure snapshot (screenshot, DOM state, or exact error) only when something breaks. On failure, read only the log tail near the failure point.
4. Keep scripts human-readable: clearly named steps, one step per function or block, and comments explaining why, not just what.

## 5. Decision gate

Apply this gate on every plan request, matching on the task signature defined in section 7:

1. **Exact match:** If an exact matching template exists, return a plan from it (full signature matches).
2. **Known variant:** Propose an adapted template. This requires user confirmation and a version bump. Never silently mutate an existing template (same domain.action, different target).
3. **No match:** Return a plain sub-agent plan and log the task as a candidate for discovery.

## 6. Two-call contract

The planner agent and task sub-agents do not know about each other; the main agent relays messages.

- **On a task request from the main agent:** Apply the decision gate and return a plan.
- **On a "task complete" message from the main agent:** The message contains the task sub-agent's self-assessment of which steps were mechanical/scriptable versus judgment-based, and a transcript path if one was dumped. Update candidates, check the 3-occurrence threshold, and extract insights from the transcript.
- **On a "wrap up" message:** Do a final optional round of housekeeping. This is a bonus flush only; correctness must not depend on it.
- **At spawn:** Read the on-disk templates, candidates, and index so occurrences from earlier chats count toward the threshold.

## 7. Storage

Use files, not SQLite. Keep one entry per file.

**Location.** All planner data lives in `docs/subagent-planner/` under the target project's root. The main agent provides the project root when it spawns the planner agent. Create the folders and index on first write. Layout:

- `docs/subagent-planner/templates/<signature>.md`
- `docs/subagent-planner/candidates/<signature>__<YYYYMMDD-HHmmss>.md`
- `docs/subagent-planner/index.md`

**Task signature.** A lowercase dotted slug `domain.action.target`, for example `vs-ui.attach-window.copilot-chat`. The planner assigns it and keeps it stable across chats. Exact match means the full signature matches a template. Known variant means the same `domain.action` with a different target. Otherwise there is no match.

**Candidate file.** One file per occurrence; the occurrence count is the number of files sharing a signature.

~~~
---
signature: <signature>
logged: <ISO timestamp>
status: open            # open | promoted
transcript: <path or none>
---
Mechanical/scriptable steps: ...
Judgment steps: ...
What varied vs. earlier occurrences: ...
~~~

**Template file.**

~~~
---
signature: <signature>
version: 1              # integer, bump on every change
tags: [..]
created: <ISO timestamp>
last-used: <ISO timestamp>
---
## Prompt
## Script calls (ordered)
## Governing rules
## Known variants and edge cases
~~~

**Index.** `index.md` holds one markdown table with columns `signature | version | tags | last-used`.

**Lock.** Use a short-lived `index.md.lock` file around index updates only. Hold it only for the instant of the write (read, decide, release, write, release); never across reasoning or task execution.

## 8. Write immediately

Write to disk at the moment each event happens: when a candidate is logged, a candidate is promoted, or an item is pruned. Never hold events in context to batch them for a wrap-up. The chat may end without one, and the planner agent's context is lost with it.

## 9. Cross-chat continuity

Planner agents are chat-scoped and ephemeral. On-disk candidates and templates are the only cross-chat memory. A planner agent in a new chat may trigger promotion even though it never saw the earlier occurrences.

## 10. Lifecycle and trimming

Keep forever only templates and the index.

- **Transcripts:** Read the transcript, extract the insight into the candidate entry or template, then delete it. A transcript may be retained only until a well-formed template exists for that task, then it is deleted.
- **Candidates:** Prune candidates that never reach the threshold within a timeout. The timeout value is UNRESOLVED, see open item 1.
- **Templates:** Flag templates unused for a long time as stale and remove them. The staleness period is UNRESOLVED, see open item 1. Deleting a template goes through the same confirmation gate as editing one.

## 11. Safety rules

- Use a confirmation gate before any agent-proposed change to a template or to this skill.
- Bump the version on any template change.
- Review the diff before applying.
- Never edit live skill folders mid-session.
- Prefer evidence over verbal summaries: tool-call traces and file contents.

## 12. Unresolved open items

1. **UNRESOLVED** — Candidate expiry timeout and template staleness period: values not chosen.
2. **UNRESOLVED** — Whether a `general-purpose` sub-agent can spawn further sub-agents: untested (only `explore` was tested).
3. **UNRESOLVED** — Whether the sub-agent actually read a file in the earlier memory test, versus guessing: not independently verified.
4. **RESOLVED (v2)** — Exact file format of a candidate entry and of a template: not yet designed. Resolved in v2, see section 7.
5. **RESOLVED (v2)** — Exact format of the task signature used to match tasks across occurrences: not yet designed. Resolved in v2, see section 7.
6. **UNRESOLVED** — Whether Itron restricts any of this tooling at org level: not confirmed.
7. **UNRESOLVED** — Whether the existing Regression Auditor sub-agent should also go through the planner agent, or stay as a fixed exception: not decided.
8. **UNRESOLVED** — How the main agent reliably holds the planner agent's ID for the rest of the chat: not decided. Respawn on a "no agent found" response is the fallback.
9. **UNRESOLVED** — First-delegation latency: the first plan request in a chat pays for spawning the planner agent and reading disk state. Cost not measured.
10. **UNRESOLVED** — Whether Visual Studio Copilot auto-loads this skill into the main agent based on its description: untested. The description should say it is for the planner agent only.
11. **RESOLVED (v2)** — Location of the templates, candidates, and index relative to the skill folder: not decided. Resolved in v2: `docs/subagent-planner/` under the target project's root.
12. **UNRESOLVED** — Whether `candidates/` is committed or gitignored in target projects: not decided.
