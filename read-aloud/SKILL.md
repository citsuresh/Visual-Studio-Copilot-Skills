---
name: read-aloud
description: 'Optional read-aloud (text-to-speech) mode for the current chat: speaks a short summary of each reply aloud with the Windows default voice. Use whenever the user says "enable tts" or "start tts" (turn it on) or "disable tts" or "stop tts" (turn it off), or asks to have replies read aloud, or asks to lower other audio while it speaks. Also use for the separate auto tts mode, which speaks only when Visual Studio is not the foreground window: enable auto tts or start auto tts (turn it on), disable auto tts or stop auto tts (turn it off). Off by default; applies to the current chat only. Installed by Install-Skills.ps1 together with its scripts.'
---

# Read-aloud (TTS)

Off by default. Nothing is spoken until the user says "enable tts" or "start tts", or turns on the
separate auto tts mode below. This applies to the current chat only, never to later chats.

## Turning it on and off

- "enable tts" / "start tts": from now on, after each reply, speak a summary (below). Say "TTS on" once
  in your reply; that reply is spoken too.
- "disable tts" / "stop tts": stop speaking. Say "TTS off" once. Do not speak that reply.

## Speaking

After each reply, run the script with a spoken summary of 1 to 3 sentences (no code, paths, tables or
long output; write numbers and symbols the way you would say them):

```powershell
& "$env:USERPROFILE\.copilot\skills\read-aloud\scripts\Speak-Text.ps1" -Text "<summary>"
```

- Run it in 64-bit Windows PowerShell or PowerShell 7. The script itself reports a 32-bit host.
- The voice is the Windows default. Never set, select or prefer a voice.
- If the script file does not exist, say once that the `read-aloud` skill is not fully installed
  (`Install-Skills.ps1` installs it) and stay silent.
- Exit code 2 with the output `NoVoice` means no usable voice: say so once and stay silent for the rest
  of the chat. Exit code 1 means it could not start (message in the output): report that once and stay
  silent.
- Wait for it to finish; do not run two at once.

## Auto TTS (speak only when you are in another window)

A separate mode from plain tts, for hearing that the agent is done only after switching to another
window. Off by default; current chat only.

- `enable auto tts` or `start auto tts`: turn it on. Say Auto TTS on once in your reply.
- `disable auto tts` or `stop auto tts`: turn it off. Say Auto TTS off once. That reply is not spoken.
- The modes are independent: `disable tts` does not turn auto tts off, and `disable auto tts` does not
  turn plain tts off. If plain tts is also on, it wins: speak every reply as above and skip this call.

While it is on, as the very last step of EVERY reply, including the reply that turns it on, run this one
command in the foreground and wait for it. Run it alone as the last tool call of the reply, after all other
tool calls have finished and never in the same parallel batch as other calls, otherwise it can speak
before the work is done. The text is a one-sentence completion summary, with the same
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
it reflects only the moment the reply finishes.

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
