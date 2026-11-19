---
name: read-aloud
description: 'Optional read-aloud (text-to-speech) mode for the current chat: speaks a short summary of each reply aloud with the Windows default voice. Use whenever the user says "enable tts" or "start tts" (turn it on) or "disable tts" or "stop tts" (turn it off), or asks to have replies read aloud, or asks to lower other audio while it speaks. Also use for the separate auto tts mode, which speaks only when Visual Studio is not the foreground window: enable auto tts or start auto tts (turn it on), disable auto tts or stop auto tts (turn it off). Off by default; applies to the current chat only. Installed by Install-Skills.ps1 together with its scripts.'
---

# Read-aloud (TTS)

Off by default. Nothing is spoken until the user says "enable tts" or "start tts", or turns on the
separate auto tts mode below. This applies to the current chat only, never to later chats.

## Turning it on and off

- "enable tts" / "start tts": from now on, when each reply is ready, speak a summary (below). Say "TTS on" once
  in your reply; that reply is spoken too.
- "disable tts" / "stop tts": stop speaking. Say "TTS off" once. Do not speak that reply.

## Speaking

Finish preparing the reply first, then run the script with a spoken summary of 1 to 3 sentences
(no code, paths, tables or long output; write numbers and symbols the way you would say them).
Publish the reply immediately after speech finishes. Blocking questions follow the same ready
handoff rule below; do not announce a question while still preparing it:

```powershell
& "$env:USERPROFILE\.copilot\skills\read-aloud\scripts\Speak-Text.ps1" -Text "<summary>"
```

- Run it in 64-bit Windows PowerShell or PowerShell 7. The script itself reports a 32-bit host.
- The voice is the Windows default. Never set, select or prefer a voice.
- If the script file does not exist, say once that the `read-aloud` skill is not fully installed
  (`Install-Skills.ps1` installs it) and stay silent.
- Exit code 2 retains the legacy `NoVoice` marker; it means speech failed, not necessarily that
  no voice is installed. Read the accompanying `SpeechDiagnostic` reason/stage, bitness and
  HRESULT (when available), report the actionable limitation once, and pause speech. Do not
  retry automatically. Exit code 1 means startup failed; report once and stay silent.
- For diagnosis, `Speak-Text.ps1 -Diagnose` returns initialization/voice-availability facts
  without speaking, changing a voice, ducking audio or altering settings. A successful check
  is not proof of audible output. Check the same account, host bitness, default audio output
  and RDP audio routing as the failing session. After the user corrects setup, require a fresh
  enable/retest request and audible confirmation before claiming recovery. Never change push
  mode because speech failed, and never retry a push merely to test TTS.
- Wait for it to finish; do not run two at once.

## Ready handoff order (both modes)

1. Finish all preparation and verification needed for the handoff, including reading required
   background results, rendering drafts/diffs, returning requested focus and clearing UI session
   indicators. A question and its options, or the final reply, must already be ready.
2. If push notifications are independently enabled and this is a qualifying completion, question
   or blocker, follow `push-notifications` to send the generic repository-prefixed push first and
   wait for the attempt to finish. Do not send an extra push merely because TTS is on.
3. Apply the active speech mode once and wait for it to finish. Normal TTS wins over auto TTS;
   auto TTS retains its foreground check. Push mode never forces speech or bypasses `Silent`.
4. Immediately open the prepared question or publish the ready reply. No further editing,
   hashing, searching, testing, watcher launch or other preparation may intervene.

Skip disabled modes without enabling them. Never put a push or speech announcement into a
preparatory command, announce a question that is not ready to open, or claim completion while
required work is still running. If a new user request invalidates an already-announced decision,
explain that the alert was premature rather than implying an unanswered question exists.

## Repository identity and blocking questions (both modes)

- Begin every spoken summary with the verified name of this chat's repository, so the user can
  identify the correct VS window. When supervising another repository's agent, name this chat's
  repository, not the supervised target. If no repository is known, use the verified solution or
  workspace name; never guess a name or speak a full path.
- Only once a question or approval is ready to open, finish any qualifying push first, then speak
  the repository name and one short sentence explaining what decision is needed. Announce once
  per question batch, not once per option. Wait for speech, then open the question immediately.
  This is an explicit exception to the end-of-reply / last-tool-call timing rule: announcing
  after the question tool returns is too late to alert someone waiting in another window.
- Apply the active mode normally: plain TTS uses `Speak-Text.ps1` and always speaks; auto TTS
  uses `Speak-IfAway.ps1` and speaks only when this chat's VS window is inactive. If both are on,
  plain TTS wins and only one announcement is made. Neither mode is enabled by asking a question.
- Keep the existing missing-script, NoVoice and error handling. Do not bypass auto TTS's
  foreground check, force speech after `Silent`, or announce a question when both modes are off.
  Do not repeat the same question announcement after the answer; speak a normal completion
  summary only if subsequent work produces a new result or another decision is needed.

## Auto TTS (speak only when you are in another window)

A separate mode from plain tts, for hearing that the agent is done only after switching to another
window. Off by default; current chat only.

- `enable auto tts` or `start auto tts`: turn it on. Say Auto TTS on once in your reply.
- `disable auto tts` or `stop auto tts`: turn it off. Say Auto TTS off once. That reply is not spoken.
- The modes are independent: `disable tts` does not turn auto tts off, and `disable auto tts` does not
  turn plain tts off. If plain tts is also on, it wins: speak every reply as above and skip this call.

While it is on, once EVERY reply is ready, including the reply that turns it on, run this one
command in the foreground and wait for it, except for the blocking-question timing above. Run it
alone as the last tool call of a normal reply, after all other tool calls and any qualifying push
have finished and never in the same parallel batch as other calls. Publish the ready reply next;
otherwise speech can incorrectly imply that unfinished work is done. The text is
a one-sentence completion summary prefixed by the repository name, with the same
rules as Speaking (no code, paths or tables; never set a voice):

```powershell
& "$env:USERPROFILE\.copilot\skills\read-aloud\scripts\Speak-IfAway.ps1" -Text "<summary>"
```

The summary must be plain ASCII text with no double quotes, curly quotes, backticks or dollar signs,
because it is passed inside a double-quoted PowerShell string. It speaks only when Visual Studio is not in
front, and prints one line: Spoken (Inactive), Silent (Active), Silent (Unknown) or Silent (Error: reason).
Unknown or Error means silence: do not retry or
speak yourself, but report Error once, and NoVoice once as under Speaking. Do not skip the call because
the reply was short or the last call said Active. If the script file does not exist, say once that the
`read-aloud` skill is not fully installed and stay silent.

The host window is the Visual Studio running this chat, found by `Test-HostVsActive.ps1` (read-only,
called by Speak-IfAway) through the parent processes of PowerShell. Limits: another Visual Studio window
counts as Inactive; the agent must be a descendant of `devenv.exe`, otherwise the result is Unknown; and
it reflects only the moment each announcement is checked, including before a blocking question.

## Lowering other audio while speaking (optional, off by default)

If the user asks for it, create or update `%USERPROFILE%\.copilot\tts-settings.json`:

```json
{"duck":true,"duckPercent":25}
```

`duckPercent` is the percentage of their own volume that other applications keep while speaking
(default 25). To turn it off, set `"duck":false` (or delete the file). Only write this file when the user
asks. While speaking, the script lowers other applications' audio sessions on the default output
device and puts them back afterwards, including after an error. It also undoes an interrupted run on
the next speak, and leaves a volume alone that the user changed during speech. If ducking cannot run, the
text is simply spoken at normal volume.
