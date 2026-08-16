# Final independent review — iOS Promo Queue stack

- **Review date:** 2026-08-16
- **Verdict:** **Changes required**
- **Proposal fidelity:** **9/10**
- **Reviewed stack:** `main` `48a613b221` → `bartosz/promo-q-simp-2` `27962e9e52` → `bartosz/promo-q-simp-3` `afa4ace811` → `bartosz/promo-q-simp-4` `0978e46ee9`

The coordinated architecture is compact, internally coherent, and faithful to the simplified direction. One missed guard in PR 2, however, lets an activation-only coordination call rebuild the shared legacy RMF source while `.promoPresentationCoordination` is disabled. Because the flag defaults off and rollback parity is a stated invariant, this is a merge blocker. The stack should not merge until that call is gated, a focused regression is added, and the affected validation is rerun.

## 1. Actionable findings

### High — flag-off address-bar activation mutates legacy RMF state

**Affected layer:** PR 2, `bartosz/promo-q-simp-3`; still present in integrated `bartosz/promo-q-simp-4`

**Evidence:**

- PR 2: `iOS/DuckDuckGo/MainViewController.swift:5547`; integrated tip: `MainViewController.swift:5553`.
- `iOS/DuckDuckGo/HomePageConfiguration.swift:108-111`.
- Downstream visibility decision: `iOS/DuckDuckGo/SuggestionTrayViewController.swift:299-310,439-449`.

`MainViewController.onTextFieldWillBeginEditing` calls `homePageConfiguration.prepareForNTP(...)` unconditionally after confirming that no standard NTP is attached. In legacy mode, `prepareForNTP` is not a no-op: it rebuilds and publishes `homeMessages` with the supplied after-idle policy.

Concrete failure scenario:

1. `.promoPresentationCoordination` is disabled (the production default).
2. The user is on a restored website tab with `openedAfterIdle == true`, and no standard NTP is attached.
3. The user focuses the address bar.
4. The unconditional preparation fetches and publishes the after-idle legacy RMF before the suggestion tray resolves whether it can show.
5. The tray can become eligible or display a different message even though the coordination feature is off.

This adds a stateful provider read and shared-source mutation to the legacy activation path. Commit `afa4ace811` guarded the standard NTP, `OmniBarEditingStateViewController`, and unified-input seams, but missed this second `MainViewController` seam. The implementation plan and earlier project log wording that call the leak fixed are stale historical claims, not evidence.

**Required resolution:** guard this call with `homePageConfiguration.mode == .coordinated`; preferably also make concrete `prepareForNTP` a legacy no-op so future hosts are safe by construction. Add a host-level regression proving that flag-off address-bar activation performs no preparation fetch and does not mutate the shared legacy source.

### Low — the generic cooldown-reset action reports completion before the reset runs

**Affected layer:** PR 3, `bartosz/promo-q-simp-4`

**Evidence:** `iOS/DuckDuckGo/DebugScreensViewModel+Screens.swift:319-322`; `iOS/DuckDuckGo/DebugScreensViewModel.swift:131-135`.

The action enqueues `Task { @MainActor ... }` and returns. `executeAction` immediately presents “DONE,” before the task can run; optional chaining also means it reports success when the resetter is absent. This is internal tooling, not production admission, but it can mislead the manual QA workflow this PR exists to support.

**Recommended resolution:** make the debug action/model main-actor isolated and invoke the reset synchronously, or report completion only after the actor task confirms a resetter ran.

### Low — two asynchronous source tests can spin until the external test timeout

**Affected layer:** PR 2, `bartosz/promo-q-simp-3` and integrated tip

**Evidence:** `iOS/DuckDuckGoTests/HomePageConfigurationTests.swift:354-356,440-442`.

`appearedRemoteMessageIsCooldownBlockedAfterBackground` and `staleDismissalCompletionCannotReleaseReacquiredOwner` poll with unbounded `while ... { await Task.yield() }`. A broken callback or continuation produces a hung test rather than a local, useful failure.

**Recommended resolution:** use bounded confirmation/continuation synchronization or an explicit test time limit at the synchronization boundary.

No other correctness, concurrency, lifecycle, lease, cooldown, or telemetry finding met the bar for an actionable production finding.

## 2. Optional simplifications

- **Remove a test-only debug seam.** `ModalPromptCoordinationDebugViewModel` was widened from `private` to internal; its `snapshot` getter and `dateFormatting` initializer argument at `ModalPromptCoordinationDebugMenu.swift:92-114,169-177` are consumed only by `ModalPromptCoordinationDebugViewModelTests.swift:96-100,117,148-152,163`. Prefer assertions through the displayed description contract and a deterministic production formatter abstraction only if the UI genuinely needs one. This is a small testing-policy violation, not a user-facing defect.
- **Make modal reconciliation return `Void`.** `ModalPromptCoordinationManaging.reconcilePresentedModal() -> Bool` at `ModalPromptCoordinationManager.swift:31,194-204` has no production consumer; both service calls discard it at `PromoCoordinationService.swift:102,154`. Keep the exact-root release behavior and assert observable ownership/attachment effects in tests.
- **Remove unused snapshot conveniences if diagnostics do not need them.** Derived modal helpers on `PromoQueueLeaseSnapshot` have test-only callers; pattern-matching `owner` keeps one canonical diagnostic representation.

## 3. Proposal fidelity — 9/10

The implementation preserves the proposal’s defining ideas:

- one app-scoped, main-actor promo owner;
- modal admission before stateful provider evaluation and RMF admission before source publication;
- RMF ownership in the shared `HomePageConfiguration`, not physical renderers;
- no renderer visibility, coverage, handoff, retain count, removal acknowledgement, waiter, fairness, or retry-timer state;
- ordered background teardown and checkpoint-only progress;
- a single preparation/data-source seam for future conditional NTP containers; and
- once-per-ownership appearance confirmation before RMF history and accounting.

The one-point deduction reflects the correctness-threatening legacy boundary miss plus the modest iOS-specific identity, startup, scoped-signal, and modal-retention machinery. That machinery solves concrete UIKit/shared-source races and does not recreate the rejected broad state machine.

### Complete material divergence map

| Proposal → final design → implementation | iOS problem solved | Maintenance/complexity cost | Assessment |
| --- | --- | --- | --- |
| Per-model RMF lease → one shared-source lease → `HomePageConfiguration` owns one aggregate (`HomePageConfiguration.swift:46-64,253-291`) | All current NTPs consume one mutable source; per-view ownership duplicates admission | One app-scoped aggregate and gate dependency | Intentional and justified |
| Same-ID physical views may join/retain-count → source simply reuses its one owner → arbiter admits only a free slot (`PromoQueueLeaseArbiter.swift:208-239`) | Avoids view-lifetime bookkeeping and renderer handoff | A future independent RMF source needs an adapter | Intentional and simpler |
| Selection on model rendering → inert coordinated construction plus explicit activation preparation (`HomePageConfiguration.swift:90-120`) | Construction must not invisibly beat launch modals | Four host seams must be reviewed | Intentional and justified; one seam is incorrectly ungated |
| Startup ordering unspecified → explicit normal/background launch state (`Launching.swift:56,286-314,343`; `MainCoordinator.swift:160-165`) | Initial NTP may attach before foreground; background launch must not claim RMF | One launch boolean and admission state | Intentional and justified |
| Models observe the global store → configuration is sole selector and emits an object-scoped signal (`HomePageConfiguration.swift:218-243,321-328`) | Prevents order-dependent mutation and recursive selection across models/direct consumers | Cancellable wiring for conditional hosts | Intentional and justified |
| Trigger precedence implicit → first admitted message and actual filter are pinned; fallback policy stays separate (`HomePageConfiguration.swift:253-307`) | A later after-idle request must not replace a valid no-trigger fallback and self-block on cooldown | Two related private concepts | Intentional and justified |
| Generic eligibility may include onboarding → onboarding remains in source selection (`HomePageConfiguration.swift:248-251`) | Avoids duplicating existing product policy in the gate | None beyond source check | Intentional and simpler |
| Unsupported content unspecified → pure builder-backed renderability check before acquisition (`HomeMessageViewModelBuilder.swift:27-32,111-149`) | Content that cannot mount would otherwise wedge the slot and never confirm appearance | One shared pure conversion check | Intentional and justified |
| Message ID as identity → opaque per-acquisition RMF identity and one typed modal ownership identity (`PromoQueueLeaseArbiter.swift:22-44,89-139,192-251`) | Same-ID reacquisition must invalidate stale SwiftUI and async callbacks | More types/context plumbing | Intentional and justified |
| Lease confirms and records → raw token confirms, service wrapper records history, source records existing events (`NewTabPagePromoCoordination.swift:25-55`; `HomePageConfiguration.swift:183-201,354-370`) | Keeps arbitration independent from persistence/analytics and guarantees first valid appearance | One small wrapper | Intentional and justified |
| Modal releases “on dismissal” → one lease spans evaluation, scheduling, exact-root attachment, and lazy reconciliation (`ModalPromptCoordinationManager.swift:60-95,163-204,244-264`) | Nested child controllers must not release the selected modal root; provider callbacks would broaden integration | Four bounded modal phases and weak root holder | Intentional and justified; not the rejected renderer state machine |
| Teardown ordering loose → unpublish, synchronously signal, then release; background disarms and clears policy (`HomePageConfiguration.swift:122-138,321-335`) | Prevents a modal acquiring while stale RMF content remains published and prevents background reacquisition | Admission boolean; possible intentional blank period | Intentional and justified |
| Cooldown generic → 10m modal→RMF, 10m RMF→RMF, 24h RMF→modal after confirmed appearance (`PromoQueueCooldownPolicy.swift:44-181`) | Implements directional product spacing and process-authoritative storage fallback | One policy/history component | Intentional and justified |
| Shared concurrency boundary unspecified → entire source/model/gate path is `@MainActor`; global notification hops before mutation (`HomePageConfiguration.swift:29,218-225`) | Mutual exclusion depends on serialized selection, retention, publication, and callbacks | Actor annotation propagation | Intentional and justified |
| Feature transitions unspecified → immutable startup-latched `.legacy`/`.coordinated` mode (`PromoCoordinationFactory.swift:38`) | Avoids live migration, invalidation, re-adoption, and transition barriers | Relaunch required | Intentional and justified |
| All sheets might be interpreted as coordinated → exactly seven launch-promo provider categories are routed (`PromoCoordinationService.swift:36-55`) | Avoids intercepting arbitrary UIKit presentation | New modal systems require explicit adoption | Intentional accepted scope |
| Retry timing vague → explicit preparation/store refresh/foreground modal checkpoints only | Keeps the coordinator an admission gate rather than a scheduler | Eligibility can be delayed beyond a cooldown boundary | Intentional accepted simplification |
| View disappearance could release → ordinary disappearance never releases; invalidation/background do | Safe last-view release would require renderer identities or counts | RMF may hold while off-NTP | Intentional accepted simplification |
| Physical exclusivity could imply frame-perfect removal → guarantee is source/admission ordering, not exit-animation proof | Exact visual completion would require removal acknowledgements/handoff | Brief duplicate mounts/transient pixels remain possible | Intentional accepted simplification |
| Legacy activation should remain untouched → three seams are guarded, but the conditional `MainViewController` seam is not (`MainViewController.swift:5553`; `HomePageConfiguration.swift:108-111`) | The activation seam is needed only for coordinated conditional content | Current implementation mutates legacy shared state | **Correctness-threatening defect** |
| Diagnostics absent → passive owner/cooldown snapshot plus explicit internal resets (`ModalPromptCoordinationDebugMenu.swift:37-77`) | Makes 10m/24h manual validation practical without force-owner controls | Internal UI/protocol plumbing and a small test-only hook | Intentional; hook is unnecessarily complex |

## 4. Implementation-plan compliance

### Phase and PR mapping

| Plan item | Status | Concrete evidence / qualification |
| --- | --- | --- |
| 0.1 Remove live feature-transition state | Complete | No live feature subscription, transition barrier, invalidation, or re-adoption symbols remain; factory selects one mode. |
| 0.2 Remove per-surface RMF APIs | Complete | Renderer identities, registrations, retry arrays/passes, and surface occupancy were deleted; rejected-symbol search is clean. |
| 0.3 Remove coordinator plumbing from renderers | Complete | Hosts retain only shared configuration/preparation/data-source dependencies. |
| 0.4 Prune discarded-architecture tests | Complete | Layer removes broad transition/surface matrices while retaining provider/root/token/cooldown behavior. |
| 1.1 Startup-latched mode | Complete | One flag read at `PromoCoordinationFactory.swift:38`; default remains disabled; debug UI says relaunch required. |
| 1.2 One-owner typed arbiter | Complete | One owner enum, typed identities, idempotent/stale-safe release, weak-token recovery, first-only appearance confirmation. PR 3 makes snapshots passive. |
| 1.3 Directional cooldown/history | Complete | Exact inclusive boundaries, future timestamps, stable storage key, injected clock, and failure-tolerant cache. |
| 1.4 Thin service / admission order | Complete | Modal acquisition and cross-kind cooldown precede provider evaluation; RMF wrapper records only a valid first appearance. |
| 1.5 Retained modal correctness | Complete | Exact-root lazy reconciliation and same-identity scheduled callback validation; legacy/session behavior remains owned by existing manager. |
| 1.6 Composition | Complete | One production arbiter/service/policy/history graph. |
| 1.7 Focused PR 1 tests | Complete with gaps | 70 unit tests and 11 integration tests passed; direct both-kind weak recovery, combined-history max boundary, and legacy RMF-denial side effects remain valuable gaps. |
| 1.8 Phase 1 alignment | Complete with optional cleanup | One modal identity and `Void` lease transfer are present; reconciliation’s returned `Bool` remains test-only reporting. |
| 2.1 Gate injection/startup/host seams | **Partial / blocker** | Shared injection and normal/background startup are correct; one of four conditional activation seams is not gated in legacy mode. |
| 2.2 Centralized RMF source ownership | Complete | Configuration alone observes coordinated store changes, owns the aggregate, publishes source data, and signals consumers. |
| 2.3 Same-ID/replacement semantics | Complete | Current owner is revalidated under its pinned actual filter; invalid replacement tears down before fresh acquisition. |
| 2.4 Renderability/identity | Complete | Pure `canBuild` precedes acquisition; callback and SwiftUI identity reuse the acquisition ID. |
| 2.5 Actual-appearance accounting | Complete | Coordinated eager map-time shown accounting is removed; `markShown` gates regular/unique effects once per ownership. |
| 2.6 Terminal/background teardown | Complete statically and in focused tests | Context checked around suspended dismissal; teardown order is source→signal→release; background disarms and preserves confirmed history. |
| 2.7 Checkpoint-only retry | Complete | No timers, waiters, fairness, release broadcasts, or retry queue. |
| 2.8 Protocols/targets/test doubles | Complete | Production seams have real callers; test gate wraps the real arbiter. Lifecycle defaults are slightly broader than necessary but harmless. |
| 2.9 Focused PR 2 tests | Partial | 54/54 layer tests and 112/112 integrated tests passed; the host-level flag-off regression is missing and two waits are unbounded. |
| Phase 2 manual matrix | External/pending | No configured RMF/modal feature-on or flag-off device walkthrough was performed in this review. |
| 3.1 Reuse debug wiring | Complete | Both debug construction paths receive the app-scoped service; no duplicate coordinator/store. |
| 3.2 Simplified snapshot | Complete | Mode, owner/IDs, RMF appearance, four cooldown fields, refresh, relaunch/no-timer text; no deleted concepts. |
| 3.3 Manual-test controls | Complete with low issue | Authoritative modal/RMF resets preserve ownership; generic reset completion feedback is premature. |
| 3.4 Debug tests | Partial to policy | 6/6 changed tests passed; formatter/state exposure is test-driven, and production modal-reset behavior lacks the symmetric owner-preservation test. |
| Final static verification | Complete | Clean rejected-vocabulary search, one graph/source, all ranges pass `git diff --check`, production trees exclude docs. |
| External phase 4 rollout | External/pending | No privacy-config mutation, cohort deployment, release-version confirmation, tracker update, or rollout-owner assignment was performed. |

### Invariants

| Invariant | Assessment |
| --- | --- |
| Full coordinated configuration/protocol/model/signal path is main-actor isolated | Complete; global notification enters via `Task { @MainActor }`. |
| Admission/lease mutation is synchronous and non-yielding | Complete. |
| Modal admission precedes provider evaluation | Complete. |
| RMF admission precedes `homeMessages` publication | Complete. |
| At most one modal or RMF owner | Complete. |
| Blocked/never-appeared RMF records no accounting/cooldown | Complete in code and focused tests. |
| Stale/duplicate contexts cannot affect replacements, including same ID | Complete in code; a combined already-stale same-ID callback regression remains desirable. |
| Existing modal provider order, onboarding, modal cooldown, accounting ownership | Complete. |
| Existing pending/active modal suppression and recent status remain observable | Complete. |
| Existing RMF event definitions/metrics; no new pixel; regular shown moves to first appearance | Complete; expected metric discontinuity documented. |
| Legacy behavior remains when flag is disabled | **Not complete** because of the missed activation guard. |
| Renderers/overlays report no visibility/coverage/lifecycle | Complete. |
| Conditional containers use only preparation plus source signal | Complete in coordinated design; missed legacy guard is the defect. |
| First owner/actual filter pinned; request policy separate | Complete. |
| Background unpublishes/releases; ordinary disappearance does not | Complete. |
| No timers/queues/registries/counts/handoff/removal state | Complete. |
| Project membership matches source/test/mock changes | Complete; all three heads build. |

### Accepted simplifications

All eleven plan simplifications are reflected in code and remain accepted: only seven launch-promo categories are coordinated; arbitrary sheets may cover RMF; source ownership can over-hold off-NTP; appeared and never-appeared background reacquisition differ; duplicate physical mounts can exist briefly; Fire suppression and landscape are not lease rules; retry has no fairness/timer/broadcast; a dismissed modal may over-hold to the next checkpoint; dismissal/unique-shown remain best effort; feature mode is startup-latched; and no new denial/fairness/retry telemetry exists. Coordinated regular-shown volume is intentionally lower because it records once per appeared ownership.

### Completion criteria and deferred work

- **PR 1:** responsibility, build, focused unit/integration evidence, cleanup, and docs hygiene are complete.
- **PR 2:** source architecture and automated behavior are largely complete, but the flag-off completion criterion fails and the manual matrix is pending. This layer is not ready to merge.
- **PR 3:** diagnostics are observational except explicit resets; build/tests pass. The generic reset feedback and test-only hook are non-blocking follow-ups. The GitHub PR remains a draft as of review time.
- **Integrated-stack definition of done:** branch topology, tree hygiene, static checks, builds, and focused automated validation are complete; exact plan compliance is not complete because of the flag-off blocker. Human manual QA remains pending.
- **Explicitly deferred/external:** manual feature-on/off scenario matrix; human PR review/integration; first containing iOS version; privacy-configuration review and 5%→25%→50%→100% rollout; release/support monitoring; owner assignment; and post-100%-rollout removal of legacy mode/source/accounting/observer branches after the agreed soak/rollback window.

## 5. Branch-by-branch review

| Layer | Parent / reviewed range | Production-only size | Assessment |
| --- | --- | --- | --- |
| PR 1 `bartosz/promo-q-simp-2` `27962e9e52` | `main...bartosz/promo-q-simp-2` | 16 production files `+457/-616`; 14 tests/mocks `+441/-1406`; 1 wiring file `+8/-14`; total 31 files `+906/-2036` | Independently buildable and reviewable. Correct minimal foundation; no P0–P2 finding. |
| PR 2 `bartosz/promo-q-simp-3` `afa4ace811` | `bartosz/promo-q-simp-2...bartosz/promo-q-simp-3` | 14 production files `+515/-83`; 4 test files `+761/-2`; total 18 files `+1276/-85` | Scope matches shared-source integration, but the missed legacy guard is a merge blocker. |
| PR 3 `bartosz/promo-q-simp-4` `0978e46ee9` | `bartosz/promo-q-simp-3...bartosz/promo-q-simp-4` | 11 production files `+266/-73`; 3 tests/mocks `+207/-1`; 1 wiring file `+4/-0`; total 15 files `+477/-74` | Diagnostics are operationally isolated; two low test/tooling issues. GitHub PR #6369 is still draft. |
| Integrated stack | `main...bartosz/promo-q-simp-4` | 31 production files `+1228/-762`; 18 tests/mocks `+1408/-1408`; 1 wiring file `+12/-14`; total 50 files `+2648/-2184` | Architecture is coherent; changes required solely because rollback/flag-off parity is violated. |

The local and remote heads matched exactly; ancestry is linear. GitHub bases were verified read-only: PR #6367 targets `main`, #6368 targets PR 1’s branch, and #6369 targets PR 2’s branch. No PR metadata was changed.

## 6. Integrated architecture and feature gating

The production graph has one `PromoQueueLeaseArbiter`, one `PromoQueueCooldownPolicy`/RMF history, one `PromoCoordinationService`, and one shared `HomePageConfiguration`. `PromoCoordinationFactory` reads the flag once. `Launching` distinguishes normal from background launch; `MainCoordinator` initializes RMF admission accordingly and owns the single foreground/background route.

With coordination enabled, a modal acquisition occurs before any provider is evaluated, while RMF acquisition/renderability/cooldown occur before publication. The shared source retains the lease before emitting content, and modal/RMF cannot both be admitted. Background clears publication and preparation state before releasing. Foreground alone does not replay work.

Current host audit:

| Host | Preparation seam | Feature-off result |
| --- | --- | --- |
| Standard NTP attach (`MainViewController.swift:2068-2070`) | Guarded by `.coordinated` | No activation leakage |
| Legacy/iPad suggestion tray (`MainViewController.swift:5553`) | **Unguarded** | **Rebuilds legacy messages; blocker** |
| OmniBar editing / `SuggestionTrayManager` (`OmniBarEditingStateViewController.swift:620-627`) | Guarded | No activation leakage |
| Unified input (`UnifiedInputContentContainerViewController.swift:257-271`) | Guarded before eligibility | No activation leakage |

PR 3 diagnostics read the same app-scoped service and do not acquire, release, retry, publish, dismiss, or emit telemetry. Only explicit cooldown resets mutate history; ownership remains unchanged. The generic reset-action completion message is the low tooling issue described above.

A future conditional RMF surface needs one activation-time `prepareForNTP(openedAfterIdle:)` call before eligibility and consumption of the shared source/signal. A leaf renderer consuming an already-prepared source needs no queue call. It does not report visibility, coverage, mount count, handoff, disappearance, or lifecycle.

## 7. Test assessment and independent validation

All Apple validation used XcodeBuildMCP on the booted **iPhone 17 Pro, iOS 26.4** (`2DBE9D9D-B0E5-4B7D-B3C8-8975E2E5C9F1`). No raw `xcodebuild`, `xcrun`, or `simctl` was used.

| Branch | Scheme / selection | Result |
| --- | --- | --- |
| PR 1 | `iOS Browser Alpha`, Debug build | Passed |
| PR 1 | `iOS Unit Tests`: eight changed coordinator/modal/NTP suites | 70 passed |
| PR 1 | `iOS Integration Tests`: `ModalPromptCoordinationManagerIntegrationTests` | 11 passed |
| PR 1 | `iOS Browser`: two changed SharedState suites | 12 passed, 2 Dax-dialog failures |
| `main` baseline | Same two SharedState suites | 13 passed, same Dax-dialog family failed |
| PR 1 isolation reruns | Each failed Dax-dialog method separately | 1/1 and 1/1 passed; evidence of pre-existing/order-dependent harness behavior |
| PR 2 | `iOS Browser Alpha`, Debug build | Passed |
| PR 2 | `iOS Unit Tests`: all four changed RMF/source suites | 54 passed |
| PR 3 | `iOS Browser Alpha`, Debug build | Passed |
| PR 3 | `iOS Unit Tests`: changed debug-view-model and arbiter suites | 6 passed |
| PR 3 integrated | `iOS Unit Tests`: 13 combined Promo Queue/RMF/flag/debug suites | 112 passed |
| PR 3 integrated | `iOS Browser`: focused after-idle/onboarding SharedState selection | 7 passed |
| PR 3 integrated | `iOS Integration Tests`: modal manager integration | 11 passed |

Exact suite selections:

- **PR 1 unit:** `PromoCoordinationServicePromoQueueTests`, `PromoCoordinationServiceTests`, `PromoQueueCooldownPolicyTests`, `ModalPromptCoordinationManagerPromoQueueTests`, `ModalPromptCoordinationManagerTests`, `ModalPromptCoordinationRealUIKitTests`, `PromoQueueLeaseArbiterTests`, and `NewTabPageMessagesModelTests`.
- **PR 1 integration:** `IntegrationTests/ModalPromptCoordinationManagerIntegrationTests`.
- **PR 1 and `main` SharedState comparison:** `SharedStateTests/NewTabPageControllerDaxDialogTests` and `SharedStateTests/OnboardingDaxFavouritesTests`; isolated reruns were `testWhenViewDidAppear_CorrectTypePassedToDialogFactory` and `testWhenOnboardingComplete_CorrectTypePassedToDialogFactory`.
- **PR 2 unit:** `HomePageConfigurationTests`, `NewTabPageMessagesModelTests`, `HomeMessageViewModelBuilderTests`, and `HomeMessageViewModelTests`.
- **PR 3 changed unit:** `ModalPromptCoordinationDebugViewModelTests` and `PromoQueueLeaseArbiterTests`.
- **Integrated unit:** the eight PR 1 unit suites, PR 2's three additional unique suites, `ModalPromptCoordinationDebugViewModelTests`, and `PromoPresentationCoordinationFeatureFlagTests` (13 suites total).
- **Integrated SharedState:** the three `NewTabPageControllerDaxDialogTests` after-idle methods plus all `OnboardingDaxFavouritesTests`; **integrated integration:** `ModalPromptCoordinationManagerIntegrationTests`.

One initial PR 1 invocation was invalid because `SharedStateTests` is not a member of the `iOS Unit Tests` plan; it was rerun through `iOS Browser` and is not counted as a product failure. Broad workspace warnings were present, but all three app builds succeeded and no warning was traced to a Promo Queue compile failure.

### Missing high-value coverage

1. **Required with the blocker fix:** host-level flag-off `MainViewController` suggestion-tray activation performs no preparation fetch/source mutation.
2. Same-ID reacquisition where an already-stale old context attempts appearance, dismissal persistence, and release against the new owner.
3. Weak-token recovery by acquiring directly after dropping both modal and RMF tokens; current test observes the passive snapshot first and covers only an RMF drop.
4. Directional cooldown with both modal and RMF history present, proving the later incoming-RMF boundary wins.
5. Legacy `tryAcquireRemoteMessageLease` denial is side-effect free across reconciliation, arbiter, cooldown, and history.
6. Production modal cooldown reset clears eligibility/persistence while preserving an active owner, symmetric with RMF reset coverage.
7. Startup composition/normal-versus-background launch remains static-review evidence; no focused production composition test or manual cold/background walkthrough was run.

### Redundant, brittle, or low-value candidates

- Remove `HomeMessageViewModelBuilderTests.renderabilityHasNoImageSideEffects` (`:60-79`): loader/reporter fakes are never passed to `canBuild`. `renderabilityMatchesBuilderSupport`, `unsupportedContentDoesNotAcquire`, and real builder image tests retain the useful coverage.
- Collapse the duplicate `arbiter.snapshot.owner == nil` read in `PromoQueueLeaseArbiterTests.swift:85-87`; one passive read plus successful acquisition proves the behavior.
- Reduce the five-value cooldown matrices in `ModalPromptCoordinationManagerIntegrationTests.swift:79-133` to the 23h/24h boundary pair; `PromptCooldownManagerTests` already owns within/outside/exact-boundary policy coverage.
- Remove the second-provider-only priority test in `ModalPromptCoordinationManagerTests.swift:122-147`; first-provider success (`:95-120`) plus later success/short-circuit (`:149-184`) protect order and fallback.
- In `ModalPromptCoordinationDebugViewModelTests`, assert cooldown formatting once rather than in all four owner scenarios; remove direct `snapshot` assertions and the exact provider-read count when derived descriptions and service ownership already prove behavior.

### Production API exposure made for tests

No Swift `public` API was added solely for tests. The one identified smell is internal: PR 3 widened the private debug view model and added its formatter/snapshot seams for tests. The acquisition identity, configuration mode/publisher/preparation, renderability API, and diagnostic snapshot all have concrete production callers.

## 8. Documentation and branch hygiene

- Tree-level checks—not working-copy diffs—show that all three production branches exclude `project_log.md`, `project_lessons/`, and `promo-queue-docs/`.
- `git diff --check` passes for every layer and the combined production range.
- Review work used detached temporary worktrees; all remained clean. XcodeBuildMCP did not leave a tracked root/iOS `Makefile` or other generated build artifact.
- The HTML appendix passes an HTML5 parse, unique-ID/anchor/ARIA checks, an offline-resource audit, and static responsive/print containment checks. The in-app browser rejected local `file://` navigation under its security policy, so pixel-level desktop/mobile rendering could not be inspected; no network or alternate browser workaround was used.
- The pre-existing local edit to `promo-queue-docs/final_review_prompt.md` was preserved and is excluded from the review commit.
- Only review documentation/project memory is changed on `bartosz/promo-q-simp-master`.

## 9. Remaining manual validation, rollout, and unverified risks

Not manually verified in this review: flag-off end-to-end legacy behavior; RMF-first/modal-first visual scenarios; seven provider eligibility combinations; all four host families on device; duplicate physical mounts/animation overlap; Fire/landscape presentation; background store updates; post-cooldown checkpoint behavior; relaunch persistence; and internal debug-screen interaction. Automated and static evidence do not substitute for this matrix.

Before merge: fix the flag-off blocker and rerun the affected host/source test plus integrated selection. Before rollout: complete the plan’s manual matrix with a fresh process after each flag change. Rollback is remote disable of `iOSPromoPresentationCoordination`, but startup latching means a new process graph is required. Treat lower regular `remoteMessageShown` volume as expected once-per-ownership accounting unless other evidence indicates a regression. External owners still need to record merged PRs, first containing iOS version, rollout responsibility, cohort progression/hold criteria, and the post-rollout cleanup trigger.

## 10. Evidence classification

- **Verified facts:** branch/PR topology, tree hygiene, diff sizes, source behavior visible in reviewed heads, static searches, build/test results, and clean detached worktrees.
- **Reasonable inference:** the missed guard can make the suggestion tray eligible for an after-idle legacy message; this follows from the call order and source mutation but was not manually reproduced in the UI.
- **Accepted trade-offs:** off-NTP over-hold, duplicate physical mounts, lazy modal release, checkpoint delay, startup latch, no new telemetry, and best-effort dismissal/unique accounting.
- **Pending manual/external work:** the scenario matrix, human merge, release/version capture, configuration rollout, monitoring, and post-rollout cleanup.
