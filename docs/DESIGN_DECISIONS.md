# Design Decisions

Append-only, dated log of non-obvious architectural/design choices. Never delete or rewrite
prior entries — if a decision is reversed, add a new entry referencing the old one instead of
removing it.

## 2026-08-07 — Skills distributed via a per-user copy, not a symlink or package

**Decision:** `Install-Skills.ps1` copies each skill folder's files into
`%USERPROFILE%\.copilot\skills\<skill-name>\`, rather than symlinking or installing via a package
manager.

**Rationale:** Keeps installation simple (plain file copy, no elevated permissions or package
registry needed) and makes it obvious when a locally-installed skill is stale relative to the
repo (the script hashes each file and only copies changed ones, prompting per-skill unless
`-Force` is passed).

**Alternatives considered:** Symlinking the skills folder directly into `.copilot\skills\` was
considered but rejected — Windows symlinks require elevated permissions/developer mode in some
environments, which would complicate first-time setup.

## 2026-08-07 — Each skill is versioned independently via `CURRENT_SKILL_VERSION`

**Decision:** Each skill's `SKILL.md` embeds its own `CURRENT_SKILL_VERSION` constant and a
changelog, and stores the last-synced version as an HTML comment marker in a target project's
`.github/copilot-instructions.md`. A cheap "Workflow 0: Version Check" compares the two on every
invocation.

**Rationale:** Lets a project that was set up under an older version of a skill detect that the
skill's workflows have since changed in a way that would benefit from (or require) re-running
Bootstrap — without the user needing to remember or manually track this per project.

**Alternatives considered:** None recorded (this is the mechanism as originally designed).
