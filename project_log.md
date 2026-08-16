# Project Log

## Current handoff
- Goal: Perform a final independent review of the three open Promo Queue pull requests against the standalone implementation plan, final architecture, and initial simplified proposal; produce an executive HTML review appendix; then hand the stack to human QA and rollout owners.
- Status: Local implementation is complete on the linear production stack: `bartosz/promo-q-simp-2` (`27962e9e52`) → `bartosz/promo-q-simp-3` (`afa4ace811`) → `bartosz/promo-q-simp-4` (`0978e46ee9`). The previously reported SharedState compilation issue and legacy conditional-host regression were fixed in the current heads. The three pull requests are open. Project documentation now lives only on `bartosz/promo-q-simp-master`.
- Completed: Production trees are free of `project_log.md`, `project_lessons/`, and `promo-queue-docs/`; branch ancestry and production-only diffs are clean. The handoff records passing focused suites and Debug builds for every layer, including final SharedState and legacy-mode coverage. The External Phase 4 handoff now exists. These results are recorded evidence and must still be independently sampled by the final reviewer.
- Next: Complete the evidence-backed branch-by-branch and integrated review, re-run proportionate tests with XcodeBuildMCP, assess proposal fidelity and test quality, and save the executive HTML report on `bartosz/promo-q-simp-master`. Then execute the manual matrix, fill PR/version/owner placeholders, merge and ship, and perform the human-owned remote rollout.
- Blockers: No known local implementation blocker. Manual scenarios requiring configured RMF/modal eligibility, PR integration, release-version confirmation, privacy-config review, cohort deployment, and rollout ownership remain human/external work.

## Decisions
### 2026-08-16 — Isolate project documentation from production pull requests
- Decision: `bartosz/promo-q-simp-master` is the sole branch for `project_log.md`, `project_lessons/`, `promo-queue-docs/`, executive review artifacts, and project-only handoff notes. The three production branches contain only code, tests, and required project wiring.
- Why: Reviewers should see focused production diffs, while architecture, execution history, and review artifacts remain durable without polluting or repeatedly restacking the open pull requests.
- Consequences: Documentation may be committed locally on the master branch but is not pushed unless explicitly requested. Agents read it with `git show` or a separate worktree and never copy/cherry-pick documentation commits into a production branch.

### 2026-08-15 — Keep diagnostics observational and cleanup acquisition-driven
- Decision: A diagnostic snapshot reports no owner for a deallocated weak token without pruning arbiter state; the next acquisition path performs stale-record cleanup.
- Why: Refreshing an internal debug screen must be a passive read and must not change production ownership or history.
- Consequences: Repeated snapshot reads are observational, explicit cooldown resets are the only diagnostic mutations, and normal acquisition recovery remains unchanged.

### 2026-08-15 — Keep review refinements within the simplified architecture
- Decision: Accept the reviewed startup-state, conditional-host, full-main-actor, trigger-fallback, identity-safe dismissal, explicit background/cooldown, minimal-diagnostics, and rollout-cleanup refinements.
- Why: They close concrete iOS lifecycle and integration gaps at the shared source without adding renderer registration, visibility callbacks, retain counts, timers, or a general state machine.
- Consequences: Phase 2 owns these refinements and focused public-behavior coverage. Phase 3 diagnostics are narrower, and rollout documentation records the expected regular-shown volume decrease.

### 2026-08-15 — Patch only the affected Phase 1 seams
- Decision: Phase 0 remains untouched. Phase 1 receives one typed modal ownership identity, a `Void` manager lease transfer, and one no-cache storage-read-failure test.
- Why: These are small maintainability improvements to already implemented foundation APIs; every other accepted review item belongs to Phase 2 or later.
- Consequences: The patch was applied on `bartosz/promo-q-simp-2` and carried through its descendants before Phase 2 was finalized.

### 2026-08-15 — Implement on the existing branch without synchronizing it
- Decision: Keep working on `bartosz/promo-q-simp-2` without rebasing or merging `main`.
- Why: Phase 0 is explicitly assigned to this branch, the worktree is clean, and synchronization would be an unnecessary git-state mutation.
- Consequences: Phase 0/1 was validated on that branch; the final open stack was later restacked onto the current `main` relationship recorded above.

## Recent progress
### 2026-08-16
- Moved all Promo Queue project documentation to `bartosz/promo-q-simp-master` and verified with tree-level checks that `bartosz/promo-q-simp-2`, `bartosz/promo-q-simp-3`, and `bartosz/promo-q-simp-4` contain none of the documentation paths.
- Added a final-review prompt that requires independent layer and integrated-stack review, proposal-fidelity scoring, proportionate XcodeBuildMCP validation, test-quality assessment, and a self-contained executive HTML appendix committed only on the master documentation branch.
- Restacked and opened the three production pull requests. Current production-only layer sizes are PR 1: 31 files, +906/-2,036; PR 2: 18 files, +1,276/-85; and PR 3: 15 files, +477/-74.
- Fixed the stale SharedState call sites in `27962e9e52` and preserved legacy conditional-host behavior in `afa4ace811`. The handoff records final affected SharedState runs of 14 tests with 0 failures on every relevant branch, final-stack Promo Queue coverage of 70 tests with 0 failures, and successful Debug builds.
- `git diff --check` passes for each production layer and the combined stack. Manual feature-state validation and external rollout remain pending and are not claimed complete.

### 2026-08-15
- The first three findings below describe an intermediate review state and are superseded by the 2026-08-16 fixes and handoff evidence above; they are retained as project history.
- Independent completion review superseded the earlier final-verification claim: XcodeBuildMCP passed 101 selected unit tests, 11 modal-coordination integration tests, and the `iOS Browser Alpha` Debug simulator build, but targeted `SharedStateTests` compilation fails because three call sites still reference the deleted `MockNewTabPagePromoCoordinator` API. The combined `git diff --check main...HEAD` also fails on trailing whitespace in two Promo Queue documents.
- Static review found a flag-off regression risk: the three newly added conditional-host `prepareForNTP` calls also rebuild legacy messages. MainVC and OmniBar can admit a focused suggestion tray using an after-idle-only card before the embedded NTP reloads with its default non-idle trigger and removes that card; the calls need coordinated-mode gating and focused regression coverage.
- The required manual matrix is explicitly unexecuted, and `local_pr_handoff.md` contains no External Phase 4 handoff despite the plan requiring rollout sequencing, hold criteria, owners, source/version guidance, rollback, and cleanup ownership.
- Phase 3 focused verification passed 18 tests with 0 failures across debug formatting/reset behavior, passive arbiter snapshots, cooldown policy, and the service gate. The `iOS Browser Alpha` Debug simulator build succeeded with no warnings or errors.
- Extended the existing internal coordination/What’s New/global prompt-reset surfaces to use the app-scoped diagnostics provider and cooldown resetter; no debug path constructs a second coordination policy/history or directly edits its keys.
- Phase 2 combined verification passed 111 focused unit tests with 0 failures, including the Phase 1 arbiter/cooldown/service/modal regressions, Phase 2 source/model/builder behavior, and feature-flag mapping/defaults. The expanded Phase 2 source/model suite additionally covers real appeared/never-appeared cooldown behavior, integrated one-notification/two-model convergence, modal denial, retained-before-publication state, replacement/onboarding/background teardown ordering, and suspended dismissal reconciliation.
- `iOS Browser Alpha` Debug simulator build succeeded for Phase 2 through XcodeBuildMCP on iPhone 17 Pro (iOS 26.4); `git diff --check` and discarded-vocabulary/live-subscription searches passed. Static review confirms exactly four production activation calls and one shared source owner. The manual feature-state matrix remains for human QA because it requires configured RMF content and launch-modal eligibility states.
- Implemented Phase 2 shared RMF source coordination across `HomePageConfiguration`, `NewTabPageMessagesModel`, the standard NTP, legacy/iPad suggestion tray, OmniBar editing sheet, unified input, and central app lifecycle composition.
- Applied the Phase 1 alignment: modal ownership now uses one `PromoQueueModalOwnershipIdentity`, transferred manager handling returns `Void`, and a fresh first-read-failure/no-cache RMF history test covers the final fallback gap.
- Phase 1 alignment verification passed 27 focused `iOS Unit Tests` and 11 `iOS Integration Tests` with 0 failures through XcodeBuildMCP on iPhone 17 Pro (iOS 26.4); the `iOS Browser Alpha` Debug simulator build succeeded, `git diff --check` passed, and the generated `iOS/Makefile` was removed.
- Revised `tech_design_final.md` and `implementation_plan.md` as standalone sources of truth for the accepted final architecture; added `promo-queue-docs/patch 1.md` for the narrow completed-Phase-1 alignment.
- User authorized local atomic commits and creation of `bartosz/promo-q-simp-3`, while explicitly pausing Phase 2 implementation.
- Phase 1 completion audit added RMF acquisition identity to the read-only arbiter snapshot; 16 focused arbiter/service/UIKit tests passed with 0 failures after the correction.
- Phase 1 focused verification passed 51 tests with 0 failures through XcodeBuildMCP, and the `iOS Browser Alpha` Debug simulator build succeeded on iPhone 17 Pro (iOS 26.4).
- Phase 1 added exact directional cooldown boundaries, failure-tolerant RMF history, the service-owned appearance-confirming lease, post-acquisition denial/release ordering, and a single composed policy/history graph.
- Independent Phase 0 validation passed 62 focused tests with 0 failures through XcodeBuildMCP on iPhone 17 Pro (iOS 26.4); static checks also found no obsolete live-transition, per-surface/retry, renderer-plumbing, or deleted project-reference symbols.
- Repository preflight corrected the implementation plan's historical checkpoint: `main...HEAD` is currently 8 commits behind and 5 ahead; HEAD is `402b6bc654`.
- No prior project log, decision/handoff log, or lesson store was found outside excluded generated/dependency directories.
- XcodeBuildMCP `iOS Unit Tests` focused run passed 45 tests with 0 failures on iPhone 17 Pro (iOS 26.4), covering Promo Queue primitives/service/modal behavior and NTP message-model regressions.
- XcodeBuildMCP `iOS Browser Alpha` Debug simulator build succeeded on iPhone 17 Pro (iOS 26.4).
- Final static audit found no remaining live-transition, per-surface retry/admission, NTP coordinator-plumbing, or deleted-project-reference symbols in affected iOS source and test paths.
