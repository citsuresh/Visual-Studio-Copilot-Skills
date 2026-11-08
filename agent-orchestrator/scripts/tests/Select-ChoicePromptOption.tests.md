# Select-ChoicePromptOption.ps1: test cases

Script: `..\Select-ChoicePromptOption.ps1`. Read [README.md](README.md) first. It clicks in a real chat: only
answer cards YOU created for the test. "Last result" is from 2026-10-31 unless stated.

| ID | Setup / action | Expected | Last result |
| --- | --- | --- | --- |
| C-01 | Choice card open, no `-Option` | Lists the options (`Options`), clicks nothing, `CardClosed` empty | Pass |
| C-02 | `-Option 'No'` (single-question card) | Selects it, verifies it is selected, clicks Submit; `Success` true, `CardClosed` true, `Echo` shows the answer | Pass |
| C-03 | Two-question card, `-Option` for page 1 | Selects, clicks "Next question"; `CardClosed` false, `NextQuestion` names page 2 | Pass |
| C-04 | Page 2, `-Option` | Submits; `CardClosed` true, `Echo` shows both answers | Pass |
| C-05 | `-Option` that is not on the card (for example a label you assumed, "Alpha", when Copilot showed "Option A") | `Success` false, error "Expected exactly one option named ...", nothing clicked | Pass (it happened once; the card stayed open) |
| C-06 | Free-text card (radio options "Enter text" / "Skip") | `-Option 'Skip'` closes it | Pass |
| C-07 | Permission prompt, `-Button 'Allow this time'` | Clicks that button; `CardClosed` true | Pass 2026-11-01 (toolkit window; a list-directory prompt created by a test prompt; `Success` true, `CardClosed` true; `Options` also lists "More confirmation options") |
| C-08 | `-Button` naming a lasting permission (for example "Always allow") without `-AllowPersistent` | `Success` false, refuses, nothing clicked | Pass 2026-11-01 for "Always allow" (`Success` false, error says it looks like a lasting permission, nothing clicked, prompt still Pending). Limit found: "Always allow" and "Allow in this session" are menu items in the "More confirmation options" dropdown, not buttons, so `-Button` cannot click them even with `-AllowPersistent` |
| C-09 | No card open | `Success` false, "No ChoicePrompt options found." | Partial 2026-11-01: on a clean chat, `-Option 'No'` gave `Success` false, "Expected exactly one option named 'No'; found 0." Nothing clicked. The documented text "No ChoicePrompt options found." is for a run with no `-Option` and was not seen |
| C-10 | `-MenuItem 'Always allow'` without `-AllowPersistent` | `Success` false, error says the menu items grant a lasting permission, nothing clicked | Pass 2026-11-02 (temp copy of v15, skills window: `Success` false, lasting-permission error, nothing clicked) |
| C-11 | Permission prompt open (set Copilot tool approvals to ask; touch a path outside the workspace), `-MenuItem 'Allow in this session' -AllowPersistent` (the user must agree to the lasting setting) | Opens the "More confirmation options" dropdown (`ExtraActionsButton`), invokes the MenuItem by exact Name, `Success` true, `CardClosed` true, red dot while it acts | Not run (needs a live prompt and the user's agreement) |
| C-12 | Prompt open, `-MenuItem 'No such item' -AllowPersistent` | `Success` false, `Options` lists the menu items seen, the dropdown is closed again, prompt still Pending | Not run (needs a live prompt) |
| C-13 | No prompt open, `-MenuItem 'Always allow' -AllowPersistent` | `Success` false, "Expected exactly one enabled 'More confirmation options' button ... found 0", nothing clicked | Not run (needs -AllowPersistent, which the auto-mode permission check blocked in this session; run by hand) |
| C-14 | `-MenuItem` together with `-Button` or `-Option` | `Success` false, "Use only one of -Option, -Button and -MenuItem." | Not run (uses -AllowPersistent in the other case; run by hand) |
| C-15 | `-TitleContains` that matches no window | `Success` false, "No window title contains '...'. Nothing was touched." | Pass 2026-11-02 (temp copy of v15) |
| C-16 | `-TitleContains` that matches several windows | `Success` false, error lists each `Hwnd 'Title'` | Pass 2026-11-02 for the shared helper `Resolve-CopilotWindow.ps1` (title ' '); not run through this script |
| C-17 | Neither `-Hwnd` nor `-TitleContains` | `Success` false, "Pass -Hwnd or -TitleContains." | Pass 2026-11-02 |
| C-18 | `-TitleContains '<solution> - '` with a prompt waiting, no `-Hwnd` | Resolves the window and answers as with `-Hwnd` | Not run (needs a live prompt) |
