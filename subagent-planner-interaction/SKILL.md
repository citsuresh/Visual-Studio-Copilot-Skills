---
name: subagent-planner-interaction
description: 'For the main agent only: explains how to work with the subagent-planner agent (spawning it, the messages to send, and relaying its notices, questions and suggestions). The planner agent and task sub-agents must not use it.'
---

# Subagent Planner Interaction

## Skill Version

`CURRENT_SKILL_VERSION = 1`

- Changelog (append-only):
  - v1 — initial version.

## 1. Purpose and audience

This skill is for the main agent only. The planner agent and task sub-agents do not apply it.
The main agent is the messenger between the planner agent, task sub-agents and the user:
the planner agent and task sub-agents do not know about each other, and the user cannot talk
to the planner agent directly. The planner agent's own instructions are in the
`subagent-planner` skill, which the main agent does not need to load.

## 2. When it applies

Never spawn a task sub-agent without first obtaining a plan from the planner agent. Code
review and audit tasks (including the Regression Auditor) are currently exempt from the
planner; this exemption may change.

## 3. Spawning the planner agent

Spawn the planner agent lazily, the first time a task sub-agent is needed in the chat. Use
the sub-agent spawn tool (`task`) in background mode; a sync agent cannot receive follow-up
messages. Tell it to use the `subagent-planner` skill and give it this project's absolute repo
root, because the planner stores its data under `docs/subagent-planner/` in the project.

If a planner agent was already spawned earlier in this chat, reuse it. If `read_agent`
returns "no agent found", respawn it; it reloads its state from disk. How the main agent
holds the planner's ID for the rest of the chat is UNRESOLVED, see item 1 in section 8.

## 4. Messages to the planner agent

Send messages with `write_agent`.

- **Task request:** Send the task and receive a plan (a prompt, ordered script calls, and
governing rules). Collect the planner's reply with `read_agent`, waiting for the planner to
finish its turn. This is a best guess that has not been verified yet: see item 3 in section 8.
- **Task complete:** After every task sub-agent finishes, send one short "task complete"
message containing that sub-agent's self-assessment (which steps were mechanical/scriptable
and which needed judgment) and its transcript path if one was dumped. Collect its reply the
same way; it may carry notices.
- **Wrap up:** At End Session, send a "wrap up" message only if a planner agent exists in
this chat. If none exists, do nothing and do not spawn one.

## 5. Spawning the task sub-agent

Spawn it with the plan as received from the planner agent. The plan itself tells the task
sub-agent what to report at the end.

## 6. Relaying to and from the user

- **Notices:** Show the planner agent's notices to the user in your normal reply. No
confirmation is needed.
- **Questions:** Relay the planner agent's questions to the user (for example, a request for
a test target or a go-ahead before it tests a risky script), and relay the user's answers back.
- **Instructions:** Relay the user's instructions to the planner agent. For example, if the
user later says the planner must ask for confirmation before some action, pass that on.
- **Suggestions:** When the planner agent reports a new suggestion to improve the skill, say
at the end of your reply: "the planner agent has a suggestion to improve the skill". Relay
the user's follow-up questions about it, and any request such as "ask the planner what it
thinks of this idea", and bring the planner agent's answers back to the user. This depends
on a planned update to the `subagent-planner` skill; see item 6 in section 8.

## 7. Data rule

Never put customer data, credentials, or personal or sensitive details in messages to the
planner agent. Redact them.

## 8. Unresolved items

1. **UNRESOLVED** — How the main agent holds the planner agent's ID for the rest of the chat:
   not decided. Respawn on "no agent found" is the fallback.
2. **UNRESOLVED** — First-spawn latency: spawning the planner and reading its state costs time.
   Whether and how to measure it is not decided.
3. **UNRESOLVED** — Whether collecting the planner agent's reply with `read_agent` (waiting for
   it to finish its turn) is correct, and how long to wait: this is a best guess, not yet
   verified. If a test shows that `write_agent` returns the reply itself, the `read_agent` step
   is dropped.
4. **UNRESOLVED** — Whether Visual Studio Copilot lets the main agent load this skill on request
   and follows the pointer in `copilot-instructions.md` reliably: reported by the user, to be
   verified by a test.
5. **UNRESOLVED** — Whether more task types become exempt from the planner, or the main agent
   decides case by case: not decided.
6. **UNRESOLVED** — The `subagent-planner` skill does not yet say that the planner agent mentions
   a new suggestion in its reply to the main agent, so the end-of-reply suggestion note in
   section 6 depends on a planned update to that skill.
