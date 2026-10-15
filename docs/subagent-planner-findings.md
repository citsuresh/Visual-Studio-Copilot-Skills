# Subagent planner: proof of concept findings

Status: shelved on 2026-10-15. This file lives on the branch `poc/subagent-planner`. `main` does not contain this work.

## The idea

A "planner agent" (a sub-agent) would draft plans for delegating tasks to "task sub-agents". It would remember recurring tasks as templates and, over time, turn repeated mechanical steps into scripts, so the main agent's context stays small and repeated work gets faster. The main agent would act only as a messenger between the planner, the task sub-agents and the user.

## What was built (all on this branch)

- `subagent-planner/SKILL.md` (v4): instructions for the planner agent only. Storage under `docs/subagent-planner/` in each target project (templates, candidates, scripts with companion files, run records, an index with success and failure counters, a suggestions file), task signatures, promotion to a template at 3 occurrences, maintenance, skill review, safety and data rules. It lists its unresolved items in section 15.
- `subagent-planner-interaction/SKILL.md` (v2): instructions for the main agent only: spawn the planner lazily in background mode, send messages with `write_agent`, collect replies with `read_agent`, relay notices, questions and suggestions to the user.
- `project-memory-management-graph/SKILL.md` v15 and v16: a pointer in the Bootstrap Step 6 template, a sentence in Begin Session, and a wrap-up step in End Session. v16 made the pointer bullet "copy verbatim", because Bootstrap had reworded it and lost the "main agent only" meaning.

## Verified facts about Copilot's agent tools (observed in tests)

- `task` spawns a sub-agent and takes a name and a mode (sync or background).
- `write_agent` works only on background agents. It only confirms delivery; it does not return the reply.
- `read_agent` returns the status ("running" or "idle") and the whole conversation as numbered turns. The reply to the latest message is the last turn. It can be called with `wait: true` and a timeout.
- `read_agent` returns a clean "no agent found" for an unknown ID; `list_agents` exists.
- A general-purpose sub-agent really reads files, has a `powershell` tool, and appeared able to spawn further sub-agents (observed once).
- The main agent loaded `subagent-planner-interaction` from the pointer in `copilot-instructions.md` and followed the intended flow (planner, plan, task sub-agent, "task complete", suggestion note).

## Measurements (one task, one project)

Task: list every public class named "Manager" in a small solution, in a project that has project memory and a code graph.

| Way of doing it | Seconds |
|---|---|
| Main agent directly | 21 |
| Sub-agent alone (inside the planner run) | 78 |
| Planner flow in full | 308 |

Breakdown of the planner flow: spawn the planner 4.5 s; planner works out the plan 123 s; spawn the task sub-agent 6.6 s; task sub-agent 78 s; "task complete" housekeeping 96 s. In the clean run the planner wrote nothing during planning, and the housekeeping step produced one 650-byte candidate note and an empty index.

## Problems seen

- The main agent saw the planner's files appear, took them for stray changes (the test prompt said "do not change any files"), deleted them, and the planner redid its work as script v2, v3 and v4. An earlier run was slowed by this. The planner's files must be protected from the main agent.
- The main agent started the task sub-agent before the planner had returned its plan (first `read_agent` without waiting).
- A planner suggestion in `skill-suggestions.md` claimed the planner had been spawned in sync mode and that `write_agent` failed. This contradicted the trace. Suggestions written by the planner should be treated as unverified.
- Bootstrap reworded the pointer bullet, losing "main agent only" and "load the skill" (fixed in v16).

## Why it was shelved

- On a typical small task the planner flow was about 15 times slower than the main agent doing the task directly, and the sub-agent alone was about 4 times slower. The main agent already has project memory and a code graph, and a fresh sub-agent starts without them.
- The expected payoff comes only from tasks that repeat and are slow. In this setup most bounded questions are answered in about 20 seconds, so few tasks would benefit.
- Making the planner opt-in (only on request) removes the cost, but then the same kind of task rarely recurs, so templates and scripts never get built. The learning needs frequent use, and frequent use needs it to be cheap. Neither was achieved.

## What would have to be true to bring it back

- Sub-agent use becomes common (many large or long-running tasks, or tasks that would flood the main agent's context), or repeated tasks turn out to be slow enough for scripts to save real time.
- First-time planning becomes cheap: a task with no match gets a plain plan immediately, with no exploration of the codebase and no scripts.
- Housekeeping does not block the answer: the main agent replies first and collects the planner's notices later.
- The main agent never deletes or edits the planner's files, and waits for the plan before spawning.

## Use cases where it could pay off (suggestions, not tested)

A sub-agent plus planner only pays off when a task is long, repeated, or large enough to flood the main agent's context. A task the main agent can do in about 20 seconds never qualifies.

1. Bulk, same-shape changes across many files (renaming an API across a solution, updating a logging call everywhere, migrating a config format). The first run teaches the pattern; later runs could use a script for the mechanical edits, and the sub-agent keeps hundreds of file reads out of the main chat.
2. Repo-wide inventories and audits with big outputs (every place a setting is read, every public API without tests, every TODO with its owner). The sub-agent returns a short report instead of thousands of lines.
3. Triage of large logs or test runs. A script that filters and counts them, written once and reused, is exactly what the skill was designed to produce.
4. Recurring multi-step maintenance chores with a fixed procedure (refreshing documentation for several projects, a release checklist, the same set of checks before each release). The 3-occurrence rule would fire here.
5. Parallel independent work (the same review across several projects). This needs a design change, because the planner currently plans one task at a time.
6. A very long chat that is running out of context, where offloading heavy reading keeps the main conversation usable.

Signs it is time to revive it: you wait several minutes on a single task, the same kind of task comes up three or more times in a few weeks, or the main chat regularly runs out of context. Before turning it on again, make the changes listed above (cheap first-time planning, non-blocking housekeeping, protected planner files) and make it opt-in rather than always-on. Then repeat the timing test on the real task.

## How to resurrect

Merge this branch into `main`, run `Install-Skills.ps1`, and re-run Bootstrap in the target projects (the graph skill at v16 changes the template). Then re-run the timing test.

## Parked ideas (not built)

Cross-project sharing of scripts; a global folder with planner-suggested promotion; a scripts repository or factory; a database used only as an index; a standalone server; checking the skill version only at start; slimming the counter bookkeeping; more task types exempt from the planner; the main agent skipping the planner for trivial tasks.

## Open items when shelved

How the main agent holds the planner's ID for the chat; first-spawn latency (now measured at about 123 s planning plus 96 s housekeeping, see above); how long the main agent should wait for the planner's reply; which counter decides "verified" and the failure threshold; whether Itron restricts agents or scripts (the user reports it does not, apart from no customer or sensitive data); candidates committed or gitignored. These are listed in the skills' own unresolved sections.
