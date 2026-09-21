---
name: ui-navigation-orchestrator
description: 'Navigate a target WinForms/WPF application to a requested screen or feature, and hand off to the vs-debug skill when the request is to debug it, using a lightweight per-target-app navigation-tree cache stored in that app''s own repo. The cache starts empty (or from an optional one-time codebase-comprehension bootstrap) and is otherwise kept current cheaply and automatically from live observation as navigation happens. Use for: "navigate to feature X", "debug this screen", "explore/map the application". Composes the ui-interaction and vs-debug skills. Replaces the retired ui-debug-map skill.'
---

## Skill Version

- `CURRENT_SKILL_VERSION = 4`. Compare against the source-of-truth copy at
  `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\ui-navigation-orchestrator\SKILL.md` once at the
  start of a session.
- Changelog:
  - v1 — initial version, replacing `ui-debug-map`. Drops the per-feature `map.json`/folder
    schema, `NavigationTree.txt`-as-derived-duplicate, `lastVerified`, and the `UnresolvedMapFindings`
    persistence mechanism entirely, in favor of one lean tree file per target app plus lighter,
    in-the-moment discrepancy handling. `ui-interaction` and `vs-debug` were extracted out as
    separate, independently mature skills this skill composes rather than reimplements.
  - v2 -- added the "Code-comprehension procedure" under Creation: concrete, ordered steps for
    doing the codebase-reading pass (orient to the app's own navigation framework first, walk
    outward one branch at a time, determine label/menu-vs-leaf/successor per page, enumerate a
    menu's real backing list rather than guessing it, flag runtime-conditional branches, and
    leave uncertain structure out rather than fabricating it). Previously this step was only
    described at a high level ("read the codebase, mark things unconfirmed") with no guidance on
    how to actually do that reading well.
  - v3 -- added an explicit "Step 0: Version Check" step (run once per request, never per
    navigation step, and never pulled into a sweep's per-item loop), matching
    agent-orchestrator's pattern.
  - v4 -- made the code-graph-skill soft dependency explicit under Updating: this skill
    never hardcodes another skill's output path/schema, and now states plainly that a
    missing, unreadable, or reformatted graph output must degrade this step to a plain code
    search rather than error or guess at a stale format. Flagged as a real, live coupling to
    project-memory-management-graph's output worth watching if that skill's format changes.

# UI Navigation Orchestrator

Get an agent to a requested screen or feature in a target application, and — when the request
calls for it — into the exact source code that handles it, using a lightweight, self-correcting
navigation-tree cache rather than a heavyweight persisted schema. This skill is the experimental,
still-maturing layer in this trio: `ui-interaction` and `vs-debug` are stable mechanism skills
this one composes; this skill's own tree-cache approach is expected to keep evolving, and is
deliberately decoupled from the other two so it can be simplified or dropped without touching
either of them.

## Prerequisites

- Depends on the **ui-interaction** skill for every live UI action (click, read, wait), and the
  **vs-debug** skill whenever a request needs source-level debugging, not just navigation.
- This skill does not call `agentdebug-ui.exe`/`agentdebug-vs.exe` directly — it always goes
  through those two skills.

## Step 0: Version Check

Run this **once**, at the very start of a navigate/debug/explore request — not on every
individual navigation step, and it must never get pulled into the per-item loop during an
"explore and map the app" sweep.

1. Read `CURRENT_SKILL_VERSION` from the repo copy at
   `C:\MyFiles\Git\Visual-Studio-Copilot-Skills\ui-navigation-orchestrator\SKILL.md`. Use the
   same "ask, don't guess" fallback as elsewhere if this repo path doesn't exist.
2. Compare that repo version to this file's own `CURRENT_SKILL_VERSION`.
3. If the repo's version is higher: tell the user plainly what changed and that the installed
   copy is stale. Recommend running `Install-Skills.ps1`, but let the user decide whether to
   update now or proceed with the current session.
4. If versions match: proceed silently.

## The navigation tree

- **Location:** stored in the *target application's own repo*, never in this skill's folder —
  e.g. `docs/ui-navigation-tree.txt`. Each target app gets its own file (or one per
  endpoint-type/workflow, matching how the app itself is structured).
- **Format:** a plain indented hierarchical list, one line per navigable item, mirroring the
  app's actual menu/screen nesting. Write the marker legend below as a header comment at the top
  of the file itself, so any future agent that opens the tree understands the conventions without
  needing this `SKILL.md` open.
- **Markers:**
  - `[ClassName]` — the page/handler class this item leads to. A coarse, durable anchor (survives
    most refactors), not an exact file/line/call-stack — those are cheap to resolve fresh via
    `vs-debug` whenever actually needed, and would otherwise go stale on nearly every unrelated
    code edit.
  - `?` — unconfirmed: this line came from static code analysis only, not yet checked against the
    running app. Removed the first time a live visit confirms the line.
  - `*` — conditional: only shown/reachable when the device, permissions, or configuration
    supports the feature. Its absence in a given session is expected, not a discrepancy.
  - `†` — title inferred: the exact display string wasn't found in source/resources, best guess
    only.
  - A short free-text note under an item — only for genuinely non-obvious interaction behavior (a
    control needing special handling, e.g. it exposes no UIA children and needs a specific
    technique) worth remembering so a future agent isn't back to trial-and-error. Not for routine
    items.
  - A bare item name with nothing else — seen in a menu, not yet drilled into. Never write a
    placeholder like `"not-explored"`; either record what's actually known, or leave the line
    bare.

## How the tree gets populated

### 1. Creation — optional, expensive, requires confirmation

- Triggered only when asked to navigate/debug in a target app that has no tree file yet.
- Before doing it, tell the user plainly: no tree exists; building one means reading the whole
  target codebase to infer menu/workflow/page structure (there is no shortcut structural tool
  assumed here — this is direct code comprehension, genuinely expensive); ask whether to do this
  now, or just proceed live without one for this specific request.
- **If declined:** do not force it. Either leave the file absent or create it empty, and proceed
  with the current request exactly as in Updating mode below (see next section). Ask again next
  time creation would be relevant — don't remember a permanent decline.
- **If accepted:** follow the code-comprehension procedure below. Write every inferred line
  marked `?`, plus `*`/`†` where applicable. Never mark anything confirmed from code alone.

#### Code-comprehension procedure

There is no structural tool doing this for you (no Roslyn-based extraction is assumed) — this is
an agent actually reading the codebase the way a person would to understand what the app's menus
look like. Work through it in this order rather than grepping for isolated keywords:

1. **Orient to this app's own navigation framework before enumerating anything.** Find the
   application's entry point (e.g. `Program.cs`/`Main`, or the startup project's main form) and
   trace how it reaches its first real screen. Along the way, identify the common
   base class or interface that "screens" in this app implement (e.g. a shared page base class, a
   `Workflow`/`IDirectNavigation`-style interface, a routed-page framework) — this defines what
   counts as a navigable item here. Every app's framework is a little different; don't assume the
   patterns from one target app carry over to another without re-confirming them.
2. **Walk the composition outward from the entry point, one level at a time**, mirroring how
   `NavigationTree.txt`-style rule 9 wants a live sweep to proceed: fully understand one branch
   (all its children) from source before moving to the next sibling, rather than jumping around
   the codebase unsystematically.
3. **For each page/screen class found, determine three things from its own code:**
   - Its display label — prefer an actual resource string (`.resx`) reference or a `Title`-style
     property/constant; if the exact string can't be traced to source (e.g. it only resolves at
     runtime from a compiled resource DLL), record your best inference and mark that line `†`.
   - Whether it is a **menu** (presents a further list of sub-items) or a **leaf** (a single
     action/command/data display with no further navigable children).
   - What page(s) can follow it — traced via explicit navigation calls
     (e.g. `ShowNextPage`/`MoveNext`-style calls, a workflow definition listing pages in sequence,
     or a direct `new SomePage()` construction) rather than guessed from naming similarity.
4. **For a menu page, find the actual backing list of items** — a data-driven collection (e.g. a
   list of command/operation definitions with names and handler references), an enum, or a
   sequence of explicit page constructions — and enumerate it directly rather than approximating
   the count or order. If the list can't be found or fully resolved, record only the items you
   could actually confirm from code; do not pad the tree with a guessed count.
5. **Watch specifically for runtime-conditional branching** — an `if`/`switch` whose outcome
   depends on data that varies per device/config/permission (not just a code path that always
   executes the same way). When found, mark that item `*` and note briefly, in one line, what the
   branch depends on (e.g. "branches on category count") — this is a legitimate code-level signal
   of conditionality even though confirming which branch actually fires for a given device still
   needs a live visit.
6. **Do not infer menu structure from behavior that only exists at runtime** (e.g. a plugin-loaded
   host application, or content assembled dynamically from configuration not present in this
   repo). If part of the app is hosted/loaded from outside this codebase, say so plainly in the
   tree (a short note, not a guessed structure) rather than fabricating screens for it.
7. **When in doubt, leave it out.** A bare item name with no `[ClassName]` is a legitimate,
   honest output of this procedure — it means "I saw evidence this exists but couldn't confidently
   resolve its class/label from code," which is strictly better than a wrong or invented entry.
   This mirrors the live-sweep discipline (rule 2 from the original design conversation): no
   placeholders, no fabricated certainty.
- This is a deliberate, occasional action — a first-time bootstrap, or later a conscious
  re-baseline after something like a major refactor — never something scheduled or repeated
  casually. There is no separate "verification" pass that re-scans the whole codebase on any kind
  of cadence; if a full re-check is ever wanted, that's just re-running Creation.

### 2. Updating — default, cheap, mostly no confirmation needed

Happens automatically as a byproduct of actually using `ui-interaction`/`vs-debug` to fulfill a
navigate/debug request — not a separately invoked mode.

- **New item found, not in the tree at all:** add it directly as a confirmed line (no `?`). No
  confirmation needed — low risk, and a wrong addition is cheap to notice and fix later.
- **Existing `?` (unconfirmed) line confirmed correct by a live visit:** clear the `?`.
- **Existing `?` line found wrong by a live visit:** correct it directly and clear the `?` — this
  is exactly what the marker exists for; nothing confirmed is being overturned.
- **Existing confirmed (non-`?`) line found wrong:** do **not** silently overwrite it. Flag it to
  the user in the moment (interactive), or note it and raise it at the next check-in
  (unattended/autopilot) — let them decide whether to correct, remove, or leave it.
- **Expected item not found live at all:** leave the line exactly as-is; never delete an entry
  just because it wasn't found this time — the absence may be legitimate (permissions, device
  variant, config, feature flag). Flag it the same way as "found wrong," above.
- Before flagging either of the last two cases, it's worth checking the target app's source (and
  a code-graph skill's output, if one is set up for that repo) for a likely explanation — a
  renamed class, a feature-flag check — so the report to the user comes with a plausible cause and
  a proposed fix, not just a bare "this looks off." The user still approves, rejects, or redirects
  the fix; this skill never applies it unilaterally.
- **This is a soft dependency, not a hard one.** This skill does not hardcode any other skill's
  output file name, location, or schema (e.g. `project-memory-management-graph`'s graph output) —
  it's a genuine, live coupling to whatever that skill currently produces, even though it's
  phrased generically here. If a code-graph skill's output can't be found, doesn't parse as
  expected, or its format has changed since this was written, fall back silently to a plain code
  search instead of erroring out or guessing at a stale format. A missing or unreadable graph
  should degrade this step to "less informed," never block it.
- "Ignore this for now" from the user is session-scoped only — a new session re-flags the same
  thing as if seen for the first time, rather than remembering a permanent suppression.

## Systematic exploration vs. directed navigation

- **"Explore and map the app" (explicit):** proceed in strict order — finish one sibling
  (including all of its own children, recursively) before moving to the next; never skip ahead to
  a more interesting item. This ordering constraint applies only when this skill is itself
  choosing what to explore next.
- **"Navigate to X" / "debug X" (directed):** no ordering constraint. Consult the tree for a known
  route first; if found, drive it via `ui-interaction`. If X isn't in the tree, search the target
  codebase for a plausible location, then confirm it live before recording (same additive,
  no-confirmation treatment as any new discovery). If no plausible candidate is found at all, say
  so and ask — don't fall back to open-ended blind exploration of the live app.
- Either mode may incidentally record items beyond the immediate target (e.g. a parent menu passed
  through en route) — that's fine, record whatever is genuinely observed along the way.

## Mutating / state-changing actions

- **During self-directed exploration:** never execute a dialog or action that looks like it would
  change state — not just literally destructive ones, anything that modifies something —
  regardless of confidence in how safe it seems. Observe and record the dialog/prompt itself if
  genuinely seen, and leave that specific path unmapped. No exceptions during a sweep.
- **During a directed request that explicitly requires a mutating step** (e.g. "reboot the
  device"): proceed, but warn the user and get confirmation before actually triggering it, then
  record the real outcome once it has actually executed and been observed live.
- Non-exhaustive mapping is the accepted, permanent end state for anything gated behind a mutating
  confirmation. A sweep is best-effort, not a completeness requirement — don't treat these gaps as
  bugs to "fix" by becoming more willing to auto-confirm dialogs.

## Debugging hand-off

- When a request needs source-level debugging (not just reaching a screen): navigate there via
  `ui-interaction`, then hand off to `vs-debug` — attach, set a breakpoint anchored to the tree's
  `[ClassName]` breadcrumb (or a class found via fresh code search if the line is `?`/unconfirmed
  or absent), and resolve the exact handler/line/call stack live.
- The tree only ever stores the coarse `[ClassName]` anchor, never exact line numbers or call
  stacks — those are cheap to resolve fresh via `vs-debug` each time and would otherwise go stale
  on nearly every unrelated code edit.

## What doesn't live here

- Generic UI-automation gotchas that aren't specific to this app's navigation structure (a
  toolkit-level quirk any consumer could hit) belong in **ui-interaction**'s own documentation,
  not in this skill or in any target app's tree file — that way a toolkit fix only needs updating
  in one place.
- No per-item JSON schema, no folder-per-feature structure, no separate pending-findings file — a
  discrepancy is either resolved in the moment or raised at the next check-in; nothing here
  persists a queue of open items beyond what the tree itself and ordinary conversation already
  carry.
