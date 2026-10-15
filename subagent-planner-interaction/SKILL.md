---
name: subagent-planner-interaction
description: 'For the main agent only: explains how to work with the subagent-planner agent (spawning it, the messages to send, and relaying its notices, questions and suggestions). The planner agent and task sub-agents must not use it.'
---

# Subagent Planner Interaction

## Skill Version

`CURRENT_SKILL_VERSION = 2`

- Changelog (append-only):
  - v1 — initial version.
  - v2 — reply collection verified by a test (read_agent, wait until idle, take the last turn); wrap-up reply handling; item 6 resolved by planner skill v4; bullet indentation fixed.

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
  governing rules). The planner's reply is collected with `read_agent` (see "Collecting the
  reply" below).
- **Task complete:** After every task sub-agent finishes, send one short "task complete"
  message containing that sub-agent's self-assessment (which steps were mechanical/scriptable
  and which needed judgment) and its transcript path if one was dumped. Collect its reply as
  described in "Collecting the reply" below; it may carry notices.
- **Wrap up:** At End Session, send a "wrap up" message only if a planner agent exists in
  this chat. If none exists, do nothing and do not spawn one. Collect the reply as described
  in "Collecting the reply" below, because it may carry notices or a mention of a new skill
  suggestion; show them to the user per section 6.

**Collecting the reply (verified by a test):**

- `write_agent` only confirms delivery; it does not return the reply.
- Call `read_agent` for the planner. If its status is "running", the planner has not finished
  its turn: call `read_agent` again. When the status is "idle", the planner has finished.
- `read_agent` returns the whole conversation history as numbered turns. The reply to the latest
  message is the response in the last turn; take only that.
- How long to wait before giving up is UNRESOLVED, see item 3 in section 8.

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
  thinks of this idea", and bring the planner agent's answers back to the user.

## 7. Data rule

Never put customer data, credentials, or personal or sensitive details in messages to the
planner agent. Redact them.

## 8. Unresolved items

1. **UNRESOLVED** — How the main agent holds the planner agent's ID for the rest of the chat:
   not decided. Respawn on "no agent found" is the fallback.
2. **UNRESOLVED** — First-spawn latency: spawning the planner and reading its state costs time.
   Whether and how to measure it is not decided.
3. **UNRESOLVED** — How long the main agent waits for the planner's reply before giving up: not
   decided. (The method itself, read_agent until status is "idle" and then the last turn, was
   verified by a test; replies took about 5 to 13 seconds in a trivial test, and a real plan
   will take longer.)
4. **UNRESOLVED** — Whether Visual Studio Copilot lets the main agent load this skill on request
   and follows the pointer in `copilot-instructions.md` reliably: reported by the user, to be
   verified by a test.
5. **UNRESOLVED** — Whether more task types become exempt from the planner, or the main agent
   decides case by case: not decided.
6. **RESOLVED (v2)** — The planner skill v4 says the planner mentions a new suggestion in its
   reply to the main agent, so the end-of-reply suggestion note in section 6 works.
