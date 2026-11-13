---
name: read-aloud
description: 'Optional read-aloud (text-to-speech) mode for the current chat: speaks a short summary of each reply aloud with the Windows default voice. Use whenever the user says "enable tts" or "start tts" (turn it on) or "disable tts" or "stop tts" (turn it off), or asks to have replies read aloud, or asks to lower other audio while it speaks. Off by default; applies to the current chat only. Installed by Install-Skills.ps1 together with its script.'
---

# Read-aloud (TTS)

Off by default. Nothing is spoken until the user says "enable tts" or "start tts". This applies to the
current chat only, never to later chats.

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
