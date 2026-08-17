# Project Log

## Current handoff
- Goal: Correct coordinated Promo Queue so a valid source-owned RMF survives same-process background/foreground with its publication, lease, acquisition identity, presentation context, and appearance state intact; keep fresh inactive acquisition impossible; restack diagnostics; and record the amended decision.
- Status: The correction is complete locally. PR 1 is unchanged at `6234fda331f2d6eac29b7524eba1dab9f68f8f51`. Corrected PR 2 is `eb9ad4cf254c2615593354278b987d683be038ef`; diagnostics-only PR 3 is conflict-free restacked at `bb00c551eefc2e30cc186b79b94f4ece9beb89e1`. Live GitHub heads remain at their preflight hashes because nothing was pushed and no PR metadata was changed.
- Completed: PR 2 has a focused runtime/test commit; PR 3's three diagnostic commits are range-diff equivalent and in their original order; independent PR 2 and final-tip Debug simulator builds succeeded; selected suites passed 26, 28, and 32 tests with zero failures; layer and combined whitespace checks pass; and the normative design, implementation plan, and local handoff record the amendment. No private API was widened solely for tests.
- Next: Human review may push the two updated production branches, update the existing PR descriptions with the local handoff text, and execute the configured RMF/launch-modal manual matrix before merge or rollout.
- Blockers: No local code or test blocker remains. Manual flag-on/off RMF fixture validation, release-version confirmation, privacy-config review, cohort deployment, and rollout ownership remain human/external work.

## Decisions
### 2026-08-17 — Retain source-owned RMF across same-process background
- Decision: Background disables fresh RMF admission and clears the last preparation policy but retains a valid `RMFOwnership`, `homeMessages` publication, lease, acquisition identity, presentation context, and appearance history. Foreground synchronously revalidates the owner with no preparation policy before launch-modal evaluation. It does not reacquire the RMF or select a new one when ownerless.
- Why: Background release was an explicit earlier design decision but changed legacy visible-RMF behavior: it removed the card, released the queue slot, created a new identity, invoked RMF-to-RMF cooldown after an appearance, and could leave the NTP blank. Promo Queue's product scope is collision prevention between RMF and launch-modal promos, not a broader RMF lifecycle rewrite.
- Consequences: Same-message reconciliation while inactive retains or updates the aggregate; authoritative dismissal, expiry, unsupported content, onboarding suppression, replacement/removal, or other ineligibility still performs ordered unpublish/release, but no replacement can be acquired while inactive. A retained RMF continues blocking launch-modal admission and may over-hold the slot while the app is backgrounded or the user is off the NTP. This accepted tradeoff intentionally diverges from the historical New Direction proposal. True background launch remains inert, and process termination/relaunch is outside this correction.

### 2026-08-16 — Block merge on the remaining legacy activation leak
- Decision: Classify the stack as changes required until the unguarded legacy/iPad `MainViewController` preparation seam is gated and protected by a focused regression.
- Why: With the coordination flag disabled, address-bar focus can call `prepareForNTP(openedAfterIdle:)`; the concrete legacy path rebuilds `homeMessages`. This violates the plan's flag-off parity invariant and makes remote disable an incomplete rollback boundary. Three sibling host seams are guarded, so the missed call is a concrete defect rather than a rejected-design trade-off.
- Consequences: The earlier 2026-08-16 “legacy conditional-host regression fixed” progress entry is retained as historical context but is stale. Human merge/rollout must wait for the production fix and rerun evidence. The final severity-first review and executive appendix are the canonical review records.

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
### 2026-08-17
- Reverified all local/origin/live heads and PR bases before mutation. The checkpoint was exact and ancestry remained `6234fda331` → `479ebe6956` → `5037f6fbee`; PR 1's tree and aggregate patch identity were recorded and stayed unchanged.
- Added `eb9ad4cf25` (`iOS: Preserve NTP RMF across background`) on PR 2. Production changes remain localized to `HomePageConfiguration`: background retains a valid owner, inactive notifications reconcile it, and foreground revalidates it before modal evaluation without providing a fresh-selection policy.
- Reworked public-behavior tests to cover retained publication/context/lease/identity, one acquisition, confirmed and never-appeared history, ownerless lifecycle inertness, inactive update/invalidation/replacement, modal blocking, legacy behavior, true-background-launch protection, and stale dismissal after genuine removal/same-ID reacquisition.
- XcodeBuildMCP on iPhone 16 Pro (iOS 18.6) passed 26 `HomePageConfigurationTests`, 28 adjacent model/service tests, and 32 final-tip source/diagnostic/arbiter tests with zero failures or skips. Independent `iOS Browser Alpha` Debug builds succeeded for corrected PR 2 and the final PR 3 tip. Existing workspace warnings remained; there were no build errors.
- Restacked PR 3 onto corrected PR 2 without conflicts. New tip `bb00c551ee` preserves the three diagnostic commits in order; `git range-diff` marks each equivalent, so no diagnostic follow-up commit was needed.
- Updated the normative design, implementation plan, local PR handoff, and this project log. The existing local-only `03225bddf9` HTML-report commit was preserved unchanged and excluded from this amendment. No new lesson was added because the durable lifecycle choice is already captured in the normative documents rather than a reusable workflow rule.
- No branch was pushed, no GitHub PR title/description/base/state changed, and no documentation entered a production branch. Manual configured-fixture validation was not performed and remains explicitly pending.

### 2026-08-16
- Completed the final independent review with a **changes required** verdict and **9/10** proposal-fidelity score. The implementation preserves the simplified one-slot/source-owned architecture and does not recreate renderer visibility, handoff, retain-count, timer, fairness, or retry-queue state; one missed feature-off host guard is merge-blocking.
- XcodeBuildMCP independently built all three branch heads with `iOS Browser Alpha` Debug on iPhone 17 Pro (iOS 26.4). Focused results: PR 1 70 unit + 11 integration; PR 2 54 unit; PR 3 6 unit; integrated tip 112 unit + 7 SharedState/browser + 11 integration, all passing. A broader PR 1 SharedState batch produced 2 Dax-dialog failures; the same family failed on `main`, and both methods passed alone, so it is recorded as pre-existing/order-dependent harness behavior rather than a stack regression.
- Added `promo-queue-docs/final_code_review.md` and the self-contained `promo-queue-docs/final_feature_review.html`. Static HTML5, offline-resource, anchor/ARIA, narrow-layout containment, and print-style audits pass. The in-app browser could not directly render the local file because `file://` navigation is blocked, so pixel-level desktop/mobile inspection remains unverified.
- Reconfirmed read-only local/remote heads, linear ancestry, actual GitHub bases, exact production/test/wiring sizes, clean layer/combined `git diff --check`, and tree-level absence of project documentation on every production branch. No production branch, pull request, or remote state was mutated.
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
