# Prompt: write the implementation plan for the iOS On-site Permission Manager

You are a senior engineer in the DuckDuckGo apple-browsers monorepo (repo root = your working directory). Your only deliverable is **`docs/on-site-permission-manager/implementation-plan.md`**, committed on the current branch **`bartosz/on-site-permissions`** (the documentation branch for this feature). Do not implement any product code, do not create implementation branches, and do not touch Asana. If the working tree is not on `bartosz/on-site-permissions`, stop and say so.

## Sources of truth

- `docs/on-site-permission-manager/requirements.md` — authoritative product requirements (compiled from Asana and Figma; do not open asana.com or figma.com links).
- `docs/on-site-permission-manager/tech-design.md` — the reviewed architecture and the 6-PR delivery plan (§5). The plan you write must follow it; where you find a genuine conflict with the code, flag it in the plan rather than silently deviating.
- The codebase. Ground every file-level claim by reading the actual code — the tech design cites file:line anchors; verify the ones you build steps on. Spawn sub-agents freely to explore in parallel.
- `docs/on-site-permission-manager/platform-precedents.md` — shipped macOS/Android behavior with code citations. Tie-breaker rule for anything the docs don't settle: Asana-derived requirements first, then macOS behavior unless it doesn't make sense on mobile, then Android.

**Audience constraint:** the implementing agent will have **no Asana and no Figma access**. The plan must be self-sufficient — everything the implementer needs (requirements, UI structure, copy, assets, Asana links to paste into PR descriptions) must be in the plan or in the two source docs. requirements.md §5–§6 already carry the full screen inventory and exact copy extracted from Figma; build on those, never on "see Figma".

## Current status: no blockers

The plan must state this explicitly, near the top: **implementation can start now; there are no blockers.** Kick-off has not run yet — the DRI decided to start on sensible defaults rather than wait, because no open kick-off item threatens the architecture. Concretely:

- The Feature Flags Registry entry for `sitePermissions` exists: https://app.asana.com/1/137249556945/project/1211834678943996/task/1217880888140745. Link it from the flag's doc comment in Phase 1.
- The privacy confirmations are provisionally greenlit as sensible defaults: Fire exempts fireproofed sites; Fire and Remove All clear per-site records only and preserve global defaults; the permission key is host-only. Proceed on these; formal ratification may follow kick-off.
- The open design/copy questions (the OQ table in requirements.md) do not block any phase: proceed on the recorded working defaults (see Defaults policy below).

## Defaults policy (instead of blocking gates)

The implementing agent must never stall on an open OQ. The plan converts every former decision gate into a documented assumption:

- Use the working defaults already recorded in requirements.md (OQ table, FR clarifications) and tech-design.md (D-sections). OQ-8/9/10/13/20 were resolved by the platform-precedents review (2026-08-26) — use the current doc text, not earlier drafts.
- Where an OQ has no recorded default, choose the simplest option consistent with the Figma copy digested in requirements §5–6, and record it.
- Two defaults to state outright:
  - **OQ-2 (combined camera+microphone):** one combined dialog. WebKit passes a single decision handler for the pair, so sequential independently-answered dialogs are impossible. Combined copy follows the bracketed dynamic-list pattern from requirements §6.
  - **OQ-4 (copy inconsistencies):** use the Figma copy verbatim as captured in requirements §5–6; where two phrasings coexist, prefer the one that scales to multiple permissions. Mark all new strings for copy review — do not wait for it.
- The plan must include an **assumptions register**: one table row per assumed default (OQ → default chosen → phase where it lands), so post-kick-off corrections are cheap and targeted.
- The agent stops to ask the user only on a genuine contradiction with no recorded or derivable default — not on a known OQ.

## What the implementation plan must contain

Write it so that an agent with no access to this conversation can execute it end to end.

1. **Overview** — one page: what is being built, the decided constraints (iOS-standalone, single package, single flag, Duck.ai exception, global-Never absolute), and links to the two source docs.
2. **Working rules for the implementing agent** — reproduce the rules in the next section verbatim as a checklist section of the document.
3. **Six phases, one per PR of tech-design §5.** For each phase:
   - Branch name and base (see branching rules below).
   - Scope: what ships, what is explicitly out of scope for the phase.
   - Assumptions in effect: the OQ-numbered items the phase touches and the default applied (per the Defaults policy). No phase has a blocking precondition — the registry and privacy gates are already satisfied (see Current status).
   - Ordered implementation steps with **concrete, verified file paths** — files to create, files to modify (with the anchor you verified), pbxproj/scheme edits where needed (package registration, `TestableReference`).
   - Tests to write, and the exact verification commands.
   - **UI specification** (for UI-bearing phases): dialog/sheet/screen anatomy, exact copy strings (lifted from requirements §5–6), icon assets by DesignResourcesKit accessor name, states and variants, dark-mode and accessibility notes. The implementer has no Figma access; structural and copy correctness is the bar — the DRI will run a separate design-fidelity pass with Figma access after implementation.
   - Flag-off safety checklist for the phase (from tech-design "Merge & release safety").
   - Exit criteria: build green, targeted tests green, review loop completed, history clean, log updated.
4. **A phase-0 section**: implementation starts from up-to-date `main` (fetch first); the registry and privacy gates are already satisfied, so phase 0 is only branch setup.
5. **Assumptions register** (see Defaults policy) and a short list of any genuine ambiguity you could not resolve from the docs plus a default — do not guess silently, but do not manufacture blockers either.

## Working rules to embed (for the implementing agent)

- **Branching.** One phase = one branch = one PR. Phase 1 → `bartosz/on-site-permissions-1`, created **off `main`**. Each subsequent branch forks off the previous one (`bartosz/on-site-permissions-2` off `-1`, and so on — a stacked train). The documentation branch `bartosz/on-site-permissions` is never a base for implementation branches.
- **Documentation stays on the documentation branch.** Never commit anything under `docs/on-site-permission-manager/` (including the project log) to an implementation branch. All plan updates, logs, and notes go to `bartosz/on-site-permissions`.
- **Project memory.** Use the `/keep-project-log` skill: maintain `project_log.md` and lesson files on the documentation branch. Log phase completions, review outcomes, applied/skipped suggestions, and decisions.
- **Verification.** Use XcodeBuildMCP (load the `xcodebuildmcp-cli` skill) to build and to run the **selected tests relevant to the change** — the package test target and the touched app suites — not the full suite by default. **Never manually test changes in the simulator (launching the app and driving its UI) unless the user gives explicit permission.** Building and running unit tests is always allowed.
- **Per-phase review loop.** When a phase is code-complete: spawn an independent review agent on the phase's diff to run (a) a normal correctness code review and (b) a Ponytail over-engineering/simplification review. When it returns: apply no-brainer fixes automatically; for suggestions with trade-offs, use good judgment and record the decision in the project log. Re-run the targeted tests after applying fixes.
- **Per-phase PR description.** When a phase is done (after the review loop), write `docs/on-site-permission-manager/pr<N>-description.md` — e.g. `pr1-description.md` — containing a suggested pull-request title and body for the phase's branch: follow the repo PR template if `.github/PULL_REQUEST_TEMPLATE.md` exists; link the phase's Asana task from the table below; summarize the changes, the flag state, and steps to test. Commit this file on the **documentation branch** (`bartosz/on-site-permissions`), never on the implementation branch.

  Asana task per PR (paste into descriptions; do not try to open them):
  | PR | Asana task |
  |---|---|
  | 1 | https://app.asana.com/1/137249556945/task/1217863452475658 |
  | 2 | https://app.asana.com/1/137249556945/task/1217863452475659 |
  | 3 | https://app.asana.com/1/137249556945/task/1217863452475660 |
  | 4 | https://app.asana.com/1/137249556945/task/1217863452475661 |
  | 5 | https://app.asana.com/1/137249556945/task/1217863452475662 |
  | 6 | https://app.asana.com/1/137249556945/task/1217863452475663 |
- **Sub-agents.** Spawn and delegate freely (exploration, test writing, reviews).
- **Git.** Commit as you go with clean, logical history — squash fixups before declaring a phase done (note: interactive rebase is unavailable in this environment; use non-interactive equivalents such as `git reset --soft` + recommit, or `git commit --amend`). End every commit message with the repo's Claude co-author trailer. **Never push.** Never force-touch branches you did not create.
- **Repo rules.** Before writing code in an area, read the matching `.cursor/rules/` file (`code-style.mdc`, `anti-patterns.mdc`, `pixels.mdc`, `user-defaults-storage.mdc`, `project-structure.mdc`). Pixels use PixelKit + JSON5 definitions validated with `npm run validate-pixel-defs` (from `iOS/`); never put domains in pixel parameters.
- **Flag safety.** Every phase must leave the app releasable with `sitePermissions` off: legacy WKUIDelegate matrices verbatim, no shim registration, nil menu/settings builders. The Fire worker is the one deliberate flag-off exception (Phase 1).

## Constraints on the plan itself

- Phase contents come from tech-design §5 — do not re-scope, merge, or reorder phases.
- Where the tech design defers a decision to an OQ, the plan applies the Defaults policy and records the assumption — it neither blocks nor invents undocumented answers.
- Keep it practical: paths, steps, commands, checklists. No architecture re-litigation — that is settled in the tech design.
- Before finishing, self-check: could an agent execute Phase 1 tomorrow from this document alone, without reading this prompt?

When the document is complete, commit it on `bartosz/on-site-permissions` (co-author trailer, no push) and summarize what you wrote and any conflicts or open questions you found.
