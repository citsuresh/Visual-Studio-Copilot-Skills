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
| C-07 | Permission prompt, `-Button 'Allow this time'` | Clicks that button; `CardClosed` true | Not run: tools are auto-approved |
| C-08 | `-Button` naming a lasting permission (for example "Always allow") without `-AllowPersistent` | `Success` false, refuses, nothing clicked | Not run live (the refusal is in the code since v3; not re-verified) |
| C-09 | No card open | `Success` false, "No ChoicePrompt options found." | Not run on a clean chat |
