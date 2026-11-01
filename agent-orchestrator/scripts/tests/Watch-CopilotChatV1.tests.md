# Watch-CopilotChatV1.ps1: test cases

Script: `..\Watch-CopilotChatV1.ps1` (full UI tree per poll). Read [README.md](README.md) first. V2 runs V1 once
at the end of a wait to collect details, so every V2 detail case in
[Watch-CopilotChatV2.tests.md](Watch-CopilotChatV2.tests.md) also exercises V1. Use the same prompts. "Last
result" is from 2026-10-31 unless stated.

A parity rule: whatever V1 returns must still be returned by V2 (through its detail step). When V1 gains a field,
add a case here AND check that `Watch-CopilotChatV2.ps1` merges it (`Add-Detail`).

| ID | Setup / action | Expected | Last result |
| --- | --- | --- | --- |
| V1-01 | Choice card open | `State` Pending, `PromptKind` ChoicePrompt, `Question`, `Options`, `Recommended` (labels containing "Recommended"), `MorePages` false | Pass (via V2 detail, skills and toolkit chats) |
| V1-02 | Two-question card | Pending, `MorePages` true | Pass (via V2 detail) |
| V1-03 | Free-text card | Pending; `Question` from the field label | Pass: this Copilot showed radio options "Enter text" / "Skip", so `PromptKind` was ChoicePrompt, never FreeTextPrompt. The FreeTextPrompt branch (a bare `FormField` Edit with Submit/Cancel) is not run |
| V1-04 | Tool permission prompt open | Pending, `PromptKind` PermissionPrompt, `Options` = the prompt's own buttons (not the chat header buttons) | Pass 2026-11-01 (toolkit window: Pending, PermissionPrompt, `Options` Allow this time / Deny, `Banners` empty) |
| V1-05 | Workspace trust card ("Do you trust this folder?") | Pending, PermissionPrompt, buttons `Trust once` / `Do not trust` | Pass 2026-11-01 (a window opened on an untrusted folder, answered by nobody): Pending, PermissionPrompt, Question "Do you trust this folder?", Options `Trust once` / `Do not trust`; `Banners` also listed WorkspaceTrustWarningBanner ("Chat is disabled because this workspace is not trusted.", no buttons) next to the mismatch banner |
| V1-06 | Plain-text question reply | `State` Idle, `AwaitingReply` true, `LastMessageTail` set, `Note` says Idle is not done | Pass |
| V1-07 | Normal reply | Idle, `Completed` true, `CompletionFooter`, `LastMessage`, `AwaitingReply` false | Pass |
| V1-08 | Reply with no completion footer | Idle only after `-IdleWithoutFooterPolls` stable polls, `Note` says to check the transcript | Not run |
| V1-09 | `-RequireWorkingFirst -StartGraceSeconds 100` on an idle chat, `-TimeoutSeconds 12` | `State` Timeout at about 12 s | Pass |
| V1-10 | `-ProgressFile <path>` | Every `[poll ...]` line also appended to the file | Pass (7 lines) |
| V1-11 | `-NotifyOnDone` | Three rising beeps when the watch ends | Code path only; not verified by ear |
| V1-12 | Banner showing (`HarnessWorkspaceMismatchBanner`, `WorkspaceTrustWarningBanner`) | `Banners` lists Id, Text, Buttons in any state | Pass 2026-11-01 (skills window, session folder differs from the open folder): `Banners` = HarnessWorkspaceMismatchBanner with its text and buttons `Update working directory` / `Close message`; State Idle; nothing clicked |
| V1-13 | `-AsJson` | JSON object on the output stream; per-poll lines go to the console stream (V2 drops them with `6>$null`) | Pass |
| V1-14 | `-Hwnd` of a closed window | Defined behavior: today V1 loops on "no parseable data" until Timeout (V2 reports WindowGone at once) | Not run; known weakness |
| V1-15 | Probe cost | About 4 s per poll and high CPU on a long chat | Observed earlier (about 70 % of a core at 5 s) |
