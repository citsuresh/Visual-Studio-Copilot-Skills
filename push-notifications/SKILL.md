---
name: push-notifications
description: 'Optional generic-only Pushbullet phone alerts for task completion, questions and blockers. Use when the user asks to start push notifications or enable push notifications, stop push notifications or disable push notifications, or explicitly send/test a phone alert. Independent of TTS and foreground state; off by default in each new chat. Use stable titles for MacroDroid and prefix the body with an approved non-sensitive repository name. Never include secrets or task details in notification text.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 3`.
- Changelog:
  - v1 - Opt-in current-chat Pushbullet alerts, start/enable and stop/disable aliases,
    fixed MacroDroid-compatible titles, approved repository prefixes, generic-only payloads
    and masked local credential setup with a nearby setup helper.
  - v2 - Bundle sender and setup scripts with the installed skill, removing the source-checkout
    dependency while keeping credential location, privacy rules and ready-handoff timing unchanged.
  - v3 - Default the encrypted XML beside the installed scripts and protect its filename from
    installer copying/pruning; existing credentials require an explicitly approved local migration.

# Push Notifications

Off by default in each new chat. Loading this skill again does not reset a mode already
explicitly chosen in the current chat. Do not persist the enabled state to another chat or
another agent. Credentials may persist locally; notification consent does not.

## Commands

| User request | Action |
| --- | --- |
| `start push notifications` / `enable push notifications` | First check whether the local credential XML exists. If missing, keep pushes off and give short setup guidance; otherwise validate the remaining prerequisites and enable the three event kinds for this chat. |
| `stop push notifications` / `disable push notifications` | Stop automatic pushes immediately; do not push the acknowledgement. |
| Explicitly send a notification or repeat a recent notification test | Send only the requested event, even if automatic mode is off; do not change the mode. |

Interpret actual user intent, not substring matches. Quoting commands, planning a skill or
discussing examples does not turn a mode on or off. If intent or the requested event is unclear,
clarify rather than guessing.

Push mode is independent of TTS, auto TTS, foreground-window state and desktop input. Changing
push mode must not change any speech mode. Do not send an extra push merely because TTS runs.

Every start/enable request must perform the XML presence check, even if a previous chat was
configured. If it is missing, do not announce that pushes are enabled, attempt a notification,
or ask for the token in chat. Briefly explain that setup is needed and point to the masked setup
helper described below. Explicitly say: "Push notifications are not enabled yet. After the XML
is ready, run enable push notifications or start push notifications again." Creating the file
or replying that setup is finished must not automatically enable pushes. Only a fresh explicit
start/enable request rechecks setup and enables the mode. An existing file is not proof of a
valid token or phone delivery; never imply that it is.

## Privacy contract

Only send the fixed generic event text below and one explicitly approved, non-sensitive
repository name. Keep the titles unchanged for MacroDroid:

| Event | Title | Body after the approved repository prefix |
| --- | --- | --- |
| Completed | `Copilot - Completed` | `A Copilot task has completed.` |
| Question | `Copilot - Question` | `A Copilot question needs your attention.` |
| Blocker | `Copilot - Blocker` | `A Copilot task is blocked and needs your attention.` |

Example body: `Public-Repo: A Copilot task has completed.`

- Use this chat's repository, not a supervised agent's repository. Never send a filesystem path
  as its name. A repository name can itself be confidential: if it is not already known to be
  public or explicitly approved for notifications, obtain an approved non-sensitive alias in
  chat before sending. If no safe name is known, do not send a push or invent a name.
- Never include code, chat excerpts, logs, exception messages, stack traces, command output,
  filenames/paths, branches, commits, issue descriptions, customer/device identifiers, personal
  details, secrets, passwords or tokens in the notification. Do not summarize tasks into a body.
- Do not add a free-text body parameter or construct arbitrary HTTP payloads. Use the fixed-text
  sender, which accepts only an event and an optional approved repository label.
- The Pushbullet access token is used only for HTTPS authentication to the fixed Pushbullet
  endpoint, never as notification text. Never print it, put it on a command line, paste it into
  chat, send it to another agent or commit it. The encrypted token file stays outside Git.
- Pushbullet is an external service. Generic text is intentional data minimization, not a claim
  of end-to-end encryption or guaranteed confidentiality. All linked devices receive the push
  unless the user has explicitly selected a device through the sender's `-DeviceId` option.

## Setup and sender

1. Resolve the installed skill folder at `%USERPROFILE%\.copilot\skills\push-notifications`.
   Runtime scripts ship in its `scripts` subfolder through `Install-Skills.ps1`; no source
   checkout or `skills-source.json` lookup is needed to send or set up notifications.
2. Resolve `<installed skill>\scripts\Send-PushbulletNotification.ps1`. This is the bundled
   sender; do not copy its logic into another script. If it is missing, report an incomplete
   installation and ask to use `install-skills` to update/install; do not silently substitute
   a source-checkout sender.
3. Default the encrypted XML to `<installed skill>\scripts\pushbullet-token.xml`, beside the
   installed sender and setup helper. The runtime defaults to its own script folder; manual repo
   forwarders explicitly use this installed location. Never put real XML in the source checkout,
   distribute it with the skill, or overwrite an existing credential. The installer excludes
   `pushbullet-token.xml` from copying and orphan/prune handling; Git ignores that filename too.
   Other custom credential filenames inside the installed tree are not protected: keep custom
   `-TokenPath` locations outside that tree. For a custom location the setup helper still puts
   a standalone helper beside the XML. Never run setup from the source checkout without an
   explicit credential path outside Git.
   When upgrading from v2, ask before copying the existing `%USERPROFILE%\.copilot\pushbullet-token.xml`
   into the new default location on this same Windows account/machine. Do not silently fall back
   to it, read/display its contents, replace a destination, or delete the original. Installation
   and credential migration require their own approval after the skill draft is approved.
4. If the XML is missing, leave pushes off and give only brief guidance: create an access token
   in [Pushbullet account settings](https://www.pushbullet.com/#settings/account), then run the
   resolved setup helper in the user's own PowerShell window. Paste the raw token only at its
   masked prompt; do not save an XML manually or paste the token into chat. The helper creates
   the encrypted XML automatically and must not accept a plaintext token argument. Do not run
   an interactive secret prompt inside an agent tool call. Do not request or receive the token.
   End the short guidance by saying pushes are not enabled yet and asking the user to issue
   `enable push notifications` or `start push notifications` again after creating the XML.
5. Encryption is Windows-user/machine-bound. Every new machine or Windows account needs its own
   setup; copying an XML from another machine is not a supported migration. If decryption fails,
   give the same short setup guidance without dumping errors or replacing the existing file.
6. The sender loads the encrypted `SecureString` in-process and rejects a plain string. Never
   read or display the file through chat tools. File existence alone does not establish token
   validity or phone delivery. The setup helper must not send an unsolicited validation push.
7. Confirm the approved repository label before enabling. A toggle acknowledgement is not itself
   a completed-task notification. If prerequisites are missing, report the problem rather than
   claiming push mode is ready.

Invoke the resolved script with named parameters, replacing the example name only with the
approved non-sensitive label:

```powershell
& $sender -Event Completed -RepositoryName 'Public-Repo'
```

Use `Question` or `Blocker` for the other events. The optional `-TokenPath` changes only the
local encrypted credential file; never pass a token value. `-WhatIf` previews without loading
the token or sending. Do not change or bypass execution policy if scripts are blocked; report
the limitation and leave pushes unavailable until an approved working sender is available.

`-Test` marks both title and body as a test, including a `[TEST]` title prefix. That prefix may
not match existing MacroDroid rules. For an explicitly requested MacroDroid routing test, send
the requested normal event title instead and explain that it is only a test in chat. Do not
claim a real task completed on the strength of such a test.

## When to send

- **Completed:** once after a meaningful user-requested task or approved delivery batch is
  actually finished and verified. Do not notify after each tool call, status update, design
  acknowledgement, internal implementation tranche, watcher launch or unfinished background task.
  A supervised agent's success claim needs the supervisor's verification first.
- **Question:** immediately before a question/approval tool blocks for the user's answer, or
  before ending with a plain-text question that needs an answer to proceed. Send it before the
  question opens, not after the user responds. Finish all preparation, draft rendering and
  validation first. Never bundle the alert into a preparatory command. Once the alert attempt
  finishes, only the required pre-question TTS may run before immediately opening the prepared
  question. If a new user request invalidates that decision before it opens, explain that the
  alert was premature rather than leaving the user searching for a question that is not there.
- **Blocker:** once when an actual blocker needs the user's intervention and prevents progress.
  Do not notify for every transient failure or for an issue the agent can resolve itself.
- Choose one event for a single handoff; do not send both Question and Blocker for the same
  situation. Do not send Completed while that handoff is waiting for input. Deduplicate unchanged
  pending questions/blockers and repeated background status reports.
- Finish all handoff preparation and verification first. The order is **qualifying push, then
  active TTS, then immediately the ready question or final reply**, skipping disabled modes.
  Follow read-aloud's foreground, repository identity and pre-question rules normally; its speech
  call remains the last tool before that handoff. No further preparation may intervene. Neither
  a push nor an error permits forced speech or an extra completion alert for unfinished work.

## Verification and failure

- The sender verifies the returned note title/body and reports server acceptance. That is not
  proof of phone delivery or MacroDroid execution; only report those after user confirmation.
- Pushbullet's normal self-pushes may share one Android category such as `Me`. Distinct titles
  support user-configured MacroDroid rules; do not claim independent Android categories or
  silently configure phone automation. Never claim hard real-time or guaranteed alert delivery.
- On an unavailable credential, failed request or unexpected response, report a concise failure
  in chat without dumping credentials, raw responses or task details. Do not recursively try to
  report a delivery failure through another push or automatically retry POSTs that may already
  have succeeded. Clearly pause automatic pushes until the user asks to retry/re-enable after
  fixing setup. Continue ordinary chat and any separately enabled TTS mode.
- Installing or updating this skill, changing credentials, creating phone automations, committing
  or pushing repository changes are separate actions requiring the applicable approvals.