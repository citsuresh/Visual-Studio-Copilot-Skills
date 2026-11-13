# Project State

This file is overwritten (not appended) at the end of each working session.

## Current focus

Making installs and updates easy on any machine. `Install-Skills.ps1` has `-Prune`, `-Check`, `-Remote`
and `-MaxAgeHours` (committed up to `43cc3fa`), and every skill's Step 0 checks the GitHub upstream once
per session and asks before running `Install-Skills.ps1 -Remote -Force`. This session made that check
cheap: a generated `skills-index.json` (version + one-line `whatsNew` per skill) is read instead of the
whole `SKILL.md`. `scripts/Update-SkillsIndex.ps1` generates it (`-Check`, `-Stage`, range warnings);
`.githooks/pre-commit` regenerates and stages it, `.githooks/pre-push` warns (never blocks) about a
missing version bump over the whole push; `Install-Skills.ps1 -Check` prints `INDEX:`. Skill versions
now: vs-debug 8, ui-interaction 19, ui-navigation-orchestrator 7, vs-chat-history 10, agent-orchestrator
18, project-memory-management 2, graph 25 (text change only, no bump). Sandbox cases I-20 to I-23 passed.
This repo remains docs-only: no tracked `.sln`/`.slnx`, code graph, or Key Flows file.

## Recently changed

`skills-index.json`, `scripts/Update-SkillsIndex.ps1`, `.githooks/pre-commit`, `.githooks/pre-push`,
`.gitattributes`, `Install-Skills.ps1` (`INDEX:` line), the `SKILL.md` of seven skills (Step 0 reads the
index), `README.md`, `docs/CODE_SUMMARY.md`, `docs/DESIGN_DECISIONS.md`, `tests/Install-Skills.tests.md`.
The edited skills are not installed yet.

## Open tasks/bugs

- The new Step 0 text (fetch, index read via `git show "@{u}:skills-index.json"`, `ask_user`, then the
  install) has not been run by a skill in a real chat, only the commands behind it. Until the edited
  skills are installed, the running copies still use the old check.
- The hooks need `git config core.hooksPath .githooks` once per clone (set on this one); web-UI edits and
  `--no-verify` bypass them. No GitHub Action exists (check-only one was offered, not decided).
- The `install-skills` skill itself has not been run in a real chat (only the script was tested), and
  the first install on a brand-new machine still needs the spelled-out prompt in the README (Option 0).
  The printed `git clone` lines for missing companions were not seen (none was missing here).
- Not tested: `Speak-Text.ps1` on a machine with no voice (simulated only); whether a later chat
  follows "enable tts" in practice (it did in this chat).
- Not run live: tool permission prompts, workspace banners, the V2 Idle-to-Pending upgrade path, a
  card above a scrolled-up chat list, the `Send-CopilotPrompt.ps1` new-session path. All
  `AgentCursor` and `Compare-RepoSnapshot` cases are marked not run; `Install-Skills` I-01 to I-19 ran
  in a sandbox only (the `-Prune -Force` combination with files to delete was not run).
- The earlier notes on `Read-CopilotReply.ps1` (empty reply on a long reply) and on monitoring-cost
  measurements were stale: the first was fixed 2026-10-31 (header of the script), the second is
  recorded in `agent-orchestrator/scripts/tests/Monitoring-cost.md`. Not re-run today; a live
  `Read-CopilotReply.ps1` check needs a second VS chat window.
- AgentDebugToolkit repo (separate): `tools/Watch-CopilotChat.ps1` still has the old name and is not
  synced with V1; make the MCP `ui_inspect` read-only by dropping `screenshot`; improve the
  list-windows flag error message; add a test trait for the interactive-desktop click test.
- No code graph or Key Flows file is generated here; no build or test suite applies.
