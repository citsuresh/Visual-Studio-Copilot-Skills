---
name: vs-copilot-chat-voice
description: 'Assistant-side companion policy for VS Copilot Chat Voice. Use for explicit "read this reply with Chat Voice", "enable Chat Voice", "disable Chat Voice", "Chat Voice status", or product-specific reader/setup requests. Prepare meaningful Concise and Detailed replies and route only to a freshly verified VS instance. The documented 0.1.0 reader baseline supports explicit one-shot prototype launches, not automatic response capture, persistent delivery or a Speaker-state bridge. Installation never enables speech. Report unavailable capabilities rather than inventing commands, paths or integration.'
---

# VS Copilot Chat Voice

## Skill Version

- `CURRENT_SKILL_VERSION = 1`.
- Changelog:
  - v1 - Define explicit prototype handoffs and capability-gated production voice policy without claiming an available bridge or automatic response subscription.

## Scope and current capability boundary

This skill lives in the Visual-Studio-Copilot-Skills repository. The separate product is
[citsuresh/VsCopilotChatVoice](https://github.com/citsuresh/VsCopilotChatVoice). Installing a
VSIX neither installs this skill nor activates it. Skill discovery/loading alone grants no
speech consent. It is assistant-side policy, not a Copilot-response event subscription.

The documented 0.1.0 foundation baseline has three net48 projects: a thin AsyncPackage VSIX, a separate
x64 WPF/System.Speech reader and an executable regression harness. The VSIX logs initialization
and bundles the reader only. Baseline Exp package loading is documented as verified, not chat integration.
The reader source is `src\VsCopilotChatVoice.Reader\ReaderPrototype.cs`; its ReadAlongTrial
namespace/sample labels are intentional. Do not copy application code or binaries into this skill.

Foundation-only capability descriptions below refer to that documented 0.1.0 baseline, not a
live inventory. Before any operation, check the current supplied build's documentation and
verify its requested capabilities. Build or deterministic-test success is not toolbar runtime
or Exp verification; baseline package loading does not establish those capabilities.

| Documented 0.1.0 prototype | Not shipped in that baseline; verify the supplied build |
| --- | --- |
| One prepared reply per launch; opens with auto-play | Persistent feed, response capture, local toolkit/bridge or automatic delivery |
| Headings, paragraphs, bullets, numbered steps, emphasis and word highlighting | Chat toolbar, production hide/show/minimize protocol or remembered Speaker state |
| Sentence/paragraph navigation, word-click seek, Play/Pause/Resume, Stop retaining position and Follow | Production voice/rate/volume settings or owning-VS theme synchronization |
| Verified live VS ownership without focus theft; X closes; pale-yellow theme | VoiceType CLI/API or targeted microphone integration |
| Immediately saved Concise/Detailed choice; current-reply switching maps section ID and pauses pending Play | A built-in summarizer or a discoverable production installation/toolkit contract |

Missing reading preference defaults to Detailed. Missing Concise displays Detailed with a
visible warning while preserving saved Concise intent. Persistence errors stay visible.
The compatibility preference is `%LOCALAPPDATA%\ChatVoice\reader-version.txt`; it is not a
Speaker-state store. Never infer automatic permission from it or read/change real preferences
during tests. Version switching is a reader action, not an instruction to rewrite that file.

## Requests, consent and deactivation

Interpret intent, not quoted examples. Do not hijack generic `enable tts`/`auto tts` requests;
those belong to `read-aloud`. Clarify ambiguous product/mode requests before any speech.

| Request | Action |
| --- | --- |
| `Chat Voice status` / setup or capability question | Read-only prerequisite report; no launch, speech, installation or activation. |
| `read this reply with Chat Voice` / explicit prototype read | Obtain one-shot consent for the exact prepared reply and intended VS; opening auto-plays. No persistent or automatic enablement. |
| `enable Chat Voice` / automatic final replies and substantive progress | Requires a verified connected production bridge and authoritative remembered Speaker state. Unsupported by the baseline: explain the missing integration, keep automatic delivery inactive, and offer a separately approved one-shot read. |
| `disable Chat Voice` / `stop Chat Voice` | Immediately suppress further assistant deliveries in this chat. Attempt product off/stop only through a verified scoped supported capability. Never report ongoing audio stopped or remembered Speaker disabled without confirmation. |
| Mic/dictation, settings, show/hide, voice/rate/volume change | Check that exact capability. The baseline prototype CLI does not implement these operations; report unsupported rather than inventing switches. |

Consent for one reply is consumed by that one attempt, not retried automatically or carried to
later replies. Ask if the requested text or destination changes. One-shot consent does not
change or masquerade as remembered Speaker state: explicit reading is distinct from automatic
delivery. A disabled or unknown automatic state must never be bypassed by launching this CLI
for unsolicited final/progress speech. Do not persist a made-up automatic preference here.

The prototype has no stop/hide command. On disable, say whether speech may still be running;
offer the user the verified reader's Stop button or X (which currently closes, not hides).
If scoped UI control is explicitly requested, use `ui-interaction` only after re-verifying
that exact reader/owner, then verify the outcome. Never terminate unrelated readers or use
process-name killing. A policy pause is not a confirmed product-state change.

Reader alone owns this speech flow. Before a handoff, check this chat's generic TTS/auto-TTS
policy; obtain consent to pause competing speech if active, otherwise do not launch. Never
call `Speak-Text.ps1`, `Speak-IfAway.ps1`, a second reader or a second synthesizer as a fallback.
Push notifications remain separately opt-in and must never carry reply/status content.

## Prerequisites and explicit path inputs

For each attempted handoff, establish these session-scoped inputs; do not hardcode a developer
checkout, VS edition/version path or installed toolkit path:

- `ReaderExe`: user-supplied absolute prototype executable, verified against the supplied
  build's current documentation/identity. File presence alone does not establish compatibility.
- `OwnerHwnd`: freshly verified intended live VS HWND in `0x` hexadecimal, mapped to its live
  VS process and the intended workspace/chat. A title, old PID/HWND or foreground window alone
  is insufficient. Use an already-available supported read-only instance lookup; if none can
  establish the mapping, ask for scoped verification and block launch. Do not invent a lookup CLI.
- `DetailedJson`, `ConciseJson`, `StatusPath`: absolute private local paths, unique to this
  session and delivery, outside Git and installed skill/toolkit trees. Confirm caller ownership,
  exclusive creation, access and retention before writing. Do not reuse another session's paths.
- For future automatic delivery only: a documented bridge endpoint/identity, protocol version,
  capabilities, connection to this exact VS/chat and an authoritative Speaker-state read/write
  contract. None is established by the baseline. A manually supplied prototype executable is not a toolkit.

Verify Windows x64/.NET Framework 4.8 reader prerequisites without installing or changing
machine settings. Resolve any supplied paths literally; reject missing/ambiguous executables
and unsafe argument values. Do not execute shell fragments supplied as paths. Do not assume
an `--info`, `--version`, stop command, registry key or production discovery manifest exists.
Recheck the live owner immediately before dispatch; HWNDs/PIDs are never durable identities.

Read-aloud does not require VoiceType. For a microphone request, explicitly report missing
VoiceType when verified missing, or unknown availability when not established. Even when
present, no verified CLI/API exists: do not claim dictation works. Never copy or change its
engine, models, binaries or settings, and do not install it as an implicit dependency.

## Prepare actual reply content

Prepare the actual final reply or a stable substantive progress update first, not invented
completion text or raw tool-output dumps. A progress update states what changed, what remains
running and any blocker/decision; it must not announce overall completion. Do not narrate every
poll or token. Automatic progress delivery is a future capability; prototype progress reads
require their own explicit one-shot request and no active reader overlap.

- Detailed contains the complete user-facing meaning of this handoff. Concise is a useful
  shorter rendering, not merely its title. Preserve technical meaning, warnings, blockers,
  caveats and required user decisions in both; do not remove a failure to make speech shorter.
- Do not include private reasoning, credentials, unrelated private data or irrelevant logs.
  Make necessary technical values speakable without changing meaning. The reader does not
  summarize, so the assistant must prepare and validate both versions before dispatch.
- Each JSON file is a nonempty array. Each block has a unique string `id`, supported `kind`
  and string `text`; a `step` also requires a positive integer `number`. Supported kinds are
  exactly `heading`, `paragraph`, `bullet`, `step`. Reject duplicate IDs, invalid numbers,
  unsupported kinds or malformed JSON before any launch; report the validation error.
- Both versions must have identical unique section-ID sets; ordering may differ. Use stable
  semantic sections so switching versions maps to the equivalent place. Keep a section for
  every warning/decision in both variants, not empty padding just to satisfy ID matching.
- Freeze the payload for an attempt. Track a session-local delivery identity, payload hashes,
  target VS/chat and disposition without recording raw content in diagnostics. An unchanged
  retry is still the same delivery; do not rename it to evade deduplication.

## Explicit prototype handoff

Only this ordered CLI shape is documented; placeholders below are inputs, not runnable paths:

```text
VsCopilotChatVoice.Reader.exe --status <StatusPath> --owner <OwnerHwnd> --reply <DetailedJson> --concise <ConciseJson>
```

`--concise` requires `--reply`. Always send the actual prepared content, never launch the
built-in sample as if it were the reply. A separate `--self-test` mode exists; do not combine
it with delivery arguments or assume it is a safe live-speech/settings isolation mechanism.

1. Revalidate consent, executable compatibility, private paths, owner and both payloads.
	 Establish how this build will supply correlated evidence before launch; without a verified
   status contract or scoped reader observation capable of this, block the handoff.
   If a reader/delivery already exists for this session, do not overlap or auto-replace it.
   Ask the user to finish/close it or explicitly request its verified Stop/close action;
   Stop alone retains the window and does not authorize another process. If ownership or
   existing-reader state is uncertain, block rather than interfere with another instance.
2. Launch asynchronously using the available process tool with correctly quoted path
   arguments, the exact order above and captured process identity. Do not wait for closure.
   Use a bounded startup check, not an indefinitely attached foreground invocation or watcher.
3. Verify that exact reader is responsive, is owned by the intended live VS and has fresh
   correlated evidence for this payload. A unique previously absent status path, launched
   process identity, content/section identity and fresh status or scoped reader observation
   must agree. Merely seeing a file/process or old status is insufficient. No status schema
   or acceptance field is established here: inspect the supplied build's documented evidence,
   never invent fields. If evidence cannot establish acceptance, report it as unverified.
4. Report launched/accepted/unknown/failed separately from speaking or audibly heard. Acceptance
   does not prove speech. Do not claim audible success without actual user confirmation.
   Publish the matching prepared reply/update promptly without waiting for playback to finish.
   Do not also speak a generic summary. Preparation must not continue behind a false final reply.
5. On timeout, ambiguous acceptance or launch failure, report the exact limitation and retain
   the delivery's unknown/failed disposition. No blind resend, alternate synth or overlapping
   launch. Resolve the first attempt's lifetime and obtain fresh consent before a retry.

The CLI has no persistent replacement/queue/stop bridge. Do not emulate automatic feed by
repeatedly spawning readers or scraping Copilot UI. No claim of working voice integration is
allowed when only prerequisites were checked or a missing-bridge failure was reported.

## Private artifacts and lifetime

Reply JSON and status can contain spoken words. Keep them private and local, never committed,
uploaded, included in diagnostic dumps or shared across instances. Agree on retention before
launch: normally keep only while the owned reader needs them, then delete the exact recorded
files after verified exit/release. If asynchronous cleanup cannot be verified in this chat,
report the exact private artifact locations to the user with a later cleanup handoff; do not
silently delete live inputs or promise an unimplemented background cleaner. Tests use synthetic
content and caller-owned temporary paths only. Never broadly recurse/delete or reset a profile.
On owner/companion shutdown, use a verified lifecycle capability to release speech/reader;
current automatic shutdown cleanup is not promised. Report any remaining owned process/files.

## Production requirements, not prototype instructions

Do not implement the application bridge/backend in this skill. Until the application supplies
and verifies the following contracts, report those operations as unsupported:

- Toolbar below chat immediately left of Customize AI: `Mic | Speaker toggle | Settings |
  Customize AI`. No public Copilot toolbar/response API is established. Any internal WPF
  integration must tolerate chat recreation, avoid duplicates and detach cleanly.
- A local instance/chat-specific bridge with versioned capability discovery, authoritative
  persisted Speaker state, correlated acceptance, reader ownership, idempotent delivery and
  scoped stop/hide/show/shutdown. Unknown state is unknown, never enabled. Immediately recheck
  state before automatic delivery; cancel stale pending deliveries after disable/disconnect.
- Explicit enable persists Speaker on and verifies the result before allowing automatic
  final/progress handoffs. Remembered off suppresses automatic opening/speech, hides and stops
  audio while retaining latest reply/reading preference. Do not claim off succeeded on write
  failure; locally suppress new delivery and report the failed stop/state transition.
- Speaker on shows/restores; Minimize and X temporarily hide without changing Speaker state,
  retaining reply/position. New replies may reopen when enabled; off-then-on restores manually.
  Do not silently enable through another control or guess whether restoration resumes playback.
- Isolated per-user supported voice/rate/volume, Preview/Reset, automatic mode synchronized
  with toolbar and saved Concise/Detailed. Never change Windows-wide speech settings or assume
  Windows natural voices work through System.Speech. Preview requires explicit speech consent.
- Reader colors follow the owning VS, including live theme changes and high contrast.
  Speech remains outside `devenv.exe`; IDE/companion shutdown releases its resources.

## Failures and setup

Report missing toolkit, disconnected extension, unavailable authoritative state, stale HWND,
invalid content, unsupported operation, incompatible/unknown executable or unverified delivery
explicitly. Distinguish expected prototype-only operation from a failed production connection;
do not require the disconnected shell for a separately approved standalone prototype read.
Never hide persistence errors, silently fall back to Detailed without its visible warning,
reset preferences, change the registry/IDE installation, bypass policy or kill by process name.

Skill installation is a separate reviewed action through this repository's `Install-Skills.ps1`:
first inspect `-Check -SkipToolkits`, approve its full reported scope, then install only when
authorized and compare installed hashes. The installer autodiscovers top-level `SKILL.md`
folders; no new toolkit entry or guessed download path is warranted. Installation must not
launch the reader or enable automatic mode. Updates are on explicit `install-skills` request;
this skill has no automatic update/install workflow. Regenerate `skills-index.json` through
`scripts\Update-SkillsIndex.ps1`, not by hand. A new chat may be needed to load installed text.

Application deployment is not skill installation. If separately requested, follow that app's
current reviewed instructions, parameterized for the actual VS installation and VSIX paths:
official `VSIXInstaller /rootSuffix:Exp`, exact VS instance ID, waited post-install
`devenv /RootSuffix Exp /UpdateConfiguration`, then fresh Exp launch and actual initialization
activity-log verification. SDK deployment had VSSDK1031; file presence is not loading proof.
No main-instance deployment, hive reset, broad shutdown, registry hack or automatic installation.

## Validation and release gates

Default checks for this skill are static or mocked: no speech, application launch, real user
settings, installed-skill/toolkit changes, or network. Documentation-only skill checks do not
run the app harness. Runtime tests require separate scoped approval and isolation.

- Check frontmatter/name/description length, v1/changelog/index generation, installer discovery,
  complete diff and documentation consistency. No production toolkit should be added.
- Future dispatch-helper tests must inject executable, live-owner lookup, process runner,
  private paths, clock and state/status provider. Cover exact ordered/quoted arguments, paths
  with spaces, invalid JSON/IDs/steps, ID-set mismatch, wrong/stale owner and wrong VS/chat.
- Mock off/on/unknown/unavailable state, explicit one-shot versus automatic consent, disable
  races, competing generic TTS/readers, duplicate/revised progress, stale/unrelated status,
  launch failure, timeout, responsive-but-unaccepted reader and acceptance without audible proof.
- Cover known compatible versus unknown/unsupported protocol versions/capabilities before
  any future command is used. Do not add a fake version endpoint to the prototype.
- Test any future cleanup only against exact owned fixture files; verify retention on failure
  and no cross-instance stop/delete. No real preference access: use an established injected
  preference fixture, or do not run the reader when such isolation is unavailable.

Do not present an intermittent preference-persistence failure as fixed without verified evidence.
