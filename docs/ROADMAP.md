# Roadmap

Edited deliberately when priorities change — not automatically overwritten each session.

## Near-term

- (none currently planned)

- Optional TTS audio ducking in `Speak-Text.ps1`: an `Add-Type` C# helper beside the script, opt-in through
  `%USERPROFILE%\.copilot\tts-settings.json`, restoring the volume in `finally` (decided 2026-11-13, not started).

## Backlog

- Consider refining Step 0a's docs-only detection further if a real edge case beyond
  sample/example keywords and auto-generated `.vs\*.slnx` scaffolding is found.
- Consider a check-only GitHub Action for the skills repo (catches web-UI edits and skipped hooks; cannot block).
- Consider a minimum toolkit version per skill in `skills-index.json`.
