# Promo Queue iteration 1 — Q3 implementation plan

## Outcome

Q3 completes iteration one on top of the consolidated `bartosz/promo-q-2` endpoint. It adds the directional cooldown policy, restores the coordinated RMF removal animation, exposes current diagnostic state, and proves the new behavior at the existing lifecycle checkpoints.

The intended endpoint is:

> One immutable process mode, one singular global owner, two confirmed-appearance histories, one pure cooldown policy, one weak checkpoint registry, and one self-owned RMF admission that confirms once and releases once.

## Baseline and branch strategy

- Authoritative base: consolidated `bartosz/promo-q-2` at `d7246ea824`, open to `main` as [#6194](https://github.com/duckduckgo/apple-browsers/pull/6194).
- The accepted simplification and hardening changes formerly reviewed on `bartosz/promo-q-2-fixes` are folded into that branch; the separate fixes PR is closed and is not an active stack layer.
- Q3 is implemented on `bartosz/promo-q-3` at `6b11771549`, based directly on `bartosz/promo-q-2` and open as draft [#6291](https://github.com/duckduckgo/apple-browsers/pull/6291).
- After Q2 lands, perform one controlled rebase of Q3 onto the resulting `main` and retarget Q3 to `main`.
- Keep `promo-queue-docs/` and `project_log.md` out of app PRs.

## Recommended review shape

Use one final pull request rather than adding another branch stack. Keep it reviewable through dependency-ordered commits:

1. restore and prove the coordinated scale/opacity removal transition;
2. add the pure cooldown policy, persisted RMF history, and focused tests;
3. integrate modal/RMF admission, appearance confirmation, checkpoints, and integration tests; and
4. add the read-only debug projection.

The feature remains disabled by default, so these commits can safely land together while reviewers inspect them independently. Split into additional stacked PRs only if the resulting diff is demonstrably too large after this commit separation; otherwise the extra branch management and review-feedback rebases are unnecessary.

## Scope ledger

| Item | Q3 disposition |
| --- | --- |
| Modal→RMF 10m | Required |
| RMF→RMF 10m | Required |
| RMF→modal 24h | Required |
| Existing modal→modal cooldown | Preserve unchanged |
| Persisted confirmed RMF timestamp | Required |
| Exactly-once RMF appearance confirmation | Required |
| Checkpoint-only cooldown reconsideration | Required |
| Coordinated RMF scale/opacity removal animation | Required |
| Promo Queue debug projection | Required |
| Cooldown/animation integration coverage | Required |
| Atomic `remoteMessageShownUnique` reservation | Optional separate correctness change; decision needed |
| Collision/cooldown/fairness telemetry | Out of scope; separate project |
| Privacy-config enablement/rollout | Out of scope; separate repository/change |
| Live feature-flag transitions | Rejected by Q2 simplification |
| Per-surface concurrent RMF owners | Rejected by Q2 simplification |
| Provisional cooldown reservation | Unnecessary with singular owner |
| Exact-boundary retry timer | Rejected; use checkpoints only |

## Why cooldown history and appearance confirmation are required

These are the minimum state needed to implement the approved cooldown rows; they do not undo the Q2 simplifications.

- The pure policy answers whether a requested target is eligible from the last confirmed modal and RMF appearances. It does not select promos, own UI, or schedule work.
- The existing persisted modal timestamp already supplies modal history. One persisted RMF timestamp is required for RMF→RMF and RMF→modal to survive app relaunch; without it, relaunching could immediately bypass a 10-minute or 24-hour wait.
- Appearance confirmation prevents starting an RMF cooldown merely because a card was selected or admitted. The timestamp is recorded only when the matching admitted card actually appears. Build failure or withdrawal before appearance records nothing.

This extends the release-only Q2 admission with one exactly-once confirmation capability, but preserves the rest of the simplified shape:

- immutable startup mode;
- one singular owner;
- no live flag transitions;
- no per-surface concurrent owners;
- no provisional reservation;
- no boundary timer;
- the same narrow public `acquired`/`deferred` facade; and
- the same physical-removal release contract.

The policy remains service-owned and separate from both the arbiter and RMF.

## What checkpoint-only cooldown integration means

The cooldown policy decides whether enough time has elapsed. Checkpoint integration decides when retained work asks that question again.

Reaching 10 minutes or 24 hours does not itself execute code. The next existing configuration, refresh, gate, host-readiness, foreground, or successful-release checkpoint re-evaluates the candidate. Therefore the effective delay may be longer than the configured minimum, but no new scheduler or timer complexity is introduced.

## Diagnostics are local, not telemetry

The diagnostics phase extends the existing internal debug screen with a read-only snapshot. It does not add pixels, analytics events, uploads, or a new telemetry pipeline. The screen exposes current process mode, owner, modal state, confirmed timestamps, and derived boundaries so developers and QA can inspect behavior locally. Ordinary debug logging may remain, but logs are not the deliverable.

## Non-negotiable invariants

1. All owner, policy, confirmation, lifecycle, and retry transitions run synchronously on `@MainActor`.
2. Acquire the singular owner before evaluating directional cooldowns.
3. Cooldown policy and persisted history never enter `PromoQueueLeaseArbiter`.
4. RMF selection and targeting remain in RMF/Home Page configuration.
5. Modal provider priority, eligibility, and modal→modal cooldown remain in `ModalPromptCoordinationManager`.
6. A denied request writes no timestamp and consumes no provider or RMF accounting.
7. RMF history is confirmed only by the first matching physical card appearance.
8. Confirmation does not release ownership; final matching physical removal still does.
9. Cooldown passage alone does not retry work.
10. Feature-off behavior remains the established legacy path and performs no new RMF history read/write.
11. The coordinated card keeps the existing scale/opacity visual behavior without releasing ownership before physical removal.
12. No new Promo Queue telemetry is introduced.

## Phase 0 — Lock and verify the Q2 foundation

Use one small baseline commit only if review fixes are still needed; otherwise make no code change.

Verify statically that the base has:

- one production flag read in `PromoCoordinationFactory`;
- no `PromoQueueFeatureState`, flag-update subscription, transition barrier, or invalidation callback;
- one `ActiveOwner?` in the arbiter;
- release-only `PromoQueueRemoteMessageAdmission`;
- physical outgoing-session ownership through the next main turn;
- readiness-gated, stable-order, reentrancy-safe weak retry handoff; and
- the three known NTP host exposure paths.

Do not introduce provisional reservations, timers, plural lease snapshots, transition callbacks, or public detailed denial cases.

## Phase 1 — Restore the coordinated RMF removal animation

Primary files:

- `iOS/DuckDuckGo/NewTabPageView.swift`
- `iOS/DuckDuckGo/NewTabPageMessagesModel.swift` only if lifecycle handling needs adjustment
- focused NTP model/real-SwiftUI/integration tests

Work:

1. Characterize when the production scale/opacity transition emits card and gate disappearance relative to visual removal.
2. Restore `.scale.combined(with: .opacity)` on the coordinated card.
3. Prove that the singular owner remains held throughout the rendered removal and the following settling turn.
4. Keep current/outgoing render-session and mount identities stale-safe across changed IDs, remounts, teardown, and overlapping callbacks.
5. If plain `onDisappear` is early, add the smallest truthful completion seam supported by the real host. Do not guess with a fixed animation-duration delay.

Required tests:

- the transition is scale plus opacity on both legacy and coordinated paths;
- logical withdrawal does not immediately free the owner;
- another NTP and a modal stay blocked during animated removal;
- handoff occurs once after truthful removal;
- late callbacks from the old session cannot release its replacement; and
- reduced-motion or non-animated execution still releases once.

Stop for explicit product/design approval if truthful lifetime cannot be preserved with the existing visual transition.

## Phase 2 — Add the pure cooldown policy and RMF store

Suggested production location:

`iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/PromoQueueCooldownPolicy.swift`

Keep policy, persistence adaptation, and focused tests independent of service/view integration.

### Policy API

The exact names may follow local conventions, but the policy needs these responsibilities:

```swift
evaluateRemoteMessageAdmission(now: Date) -> Decision
evaluateModalAdmission(now: Date) -> Decision
recordConfirmedRemoteMessageAppearance(at date: Date)
snapshot(now: Date) -> Snapshot
```

`Decision` should distinguish eligible from cooldown-denied and carry the derived next-eligible date internally for tests/debugging. It must not cross the narrow NTP facade.

Rules:

- remote-message target boundary = `max(lastModal + 600s, lastRMF + 600s)`;
- modal target boundary = `lastRMF + 86_400s`;
- no relevant history means eligible;
- `now == boundary` is eligible; and
- future timestamps conservatively extend the wait.

### Store contract

Reuse the exact `PromptCooldownStore` instance constructed for the modal manager. Add one production persisted RMF timestamp store; do not duplicate modal history and do not use an in-memory production fallback.

Required RMF-store behavior:

- initial read failure: no known history, retry on a later read;
- successful read, including `nil`: cache it;
- later read failure: return the last successful cached value;
- successful write: update memory and persistence;
- failed write: attempted value remains authoritative in this process; and
- reconstructed policy/store: observes only the value that actually persisted.

Required tests:

- every row at just-before, exact, and just-after boundaries;
- max-of-two RMF target boundary;
- absent history;
- future timestamp/backward-clock behavior;
- persistence across reconstruction;
- initial-read, later-read, and write failures; and
- snapshot derivation without side effects.

## Phase 3 — Integrate cooldown admission and appearance confirmation

Primary files:

- `PromoCoordinationService.swift`
- `NewTabPagePromoCoordination.swift`
- `NewTabPageMessagesModel.swift`
- `PromoCoordinationServicePromoQueueTests.swift`
- `NewTabPageMessagesModelTests.swift`
- manager/integration tests as needed
- `project.pbxproj` for new files

The service convenience initializer currently constructs the shared `PromptCooldownKeyValueFilesStore`. Prefer constructing the new RMF store and policy there, then inject the same modal store into both the manager and policy. Touch `PromoCoordinationFactory` only if the service initializer contract actually requires it.

### Extend the admission

Change `PromoQueueRemoteMessageAdmission` from:

```text
active -> released
```

to:

```text
pending -> consumed -> released
```

- `confirmAppearance()` moves pending to consumed and invokes the history callback once.
- `release()` works from pending or consumed, releases the raw owner once, then performs the existing successful-release handoff.
- confirmation after release and duplicate confirmation are no-ops.
- the model calls `confirmAppearance()` in `recordAppearance`, before ordinary RMF shown accounting.

### RMF admission order

1. Require existing app/UI and surface readiness.
2. Reconcile a stale modal root.
3. Acquire the singular RMF owner.
4. Evaluate modal→RMF and RMF→RMF cooldowns.
5. On denial, release the raw owner immediately, retain the candidate, and do not drain the registry.
6. On success, return the self-owned admission with confirmation and release callbacks.

No provisional reservation is needed: the singular owner serializes competing requests before policy evaluation.

### Modal admission order

1. Preserve existing launch-source and unrelated-modal gates.
2. Acquire the singular modal owner.
3. Evaluate the fixed RMF→modal cooldown before entering the manager.
4. On denial, release the raw owner with no provider call, manager state, timestamp, or retry-registry drain.
5. On success, pass the same lease into the unchanged manager flow; its existing `PromptCooldownManager` still owns modal→modal.

Required tests:

- owner acquisition occurs before policy evaluation for both targets;
- a lease conflict never invokes the policy;
- cooldown denial rolls back ownership without nested handoff;
- modal denial never reaches providers;
- RMF denial keeps the candidate unbuilt/unpublished/unaccounted;
- builder failure and withdrawal before appearance write no RMF timestamp;
- first matching appearance confirms before normal shown accounting;
- duplicate/remounted/stale appearances cannot reconfirm;
- confirmation does not release the owner; and
- legacy mode bypasses new checks and RMF writes.

## Phase 4 — Prove checkpoint-only liveness

Add no scheduler or deadline timer. Extend existing service/model/integration coverage for these checkpoints:

- initial configuration load;
- RMF configuration notification;
- explicit refresh;
- gate mount/remount;
- window attachment and known-host exposure changes;
- full foreground interaction readiness after background;
- temporary resign-active return when readiness was retained;
- successful modal-owner release;
- successful RMF-owner release and cross-surface handoff; and
- same-surface retry after final physical removal.

Required scenarios:

1. Advance the clock past 10 minutes without a checkpoint: no RMF appears.
2. Trigger the next real checkpoint: the retained RMF is reconsidered and may appear.
3. Advance the clock past 24 hours without a foreground/modal checkpoint: no modal evaluation occurs.
4. Trigger an eligible standard-foreground pass: modal admission is reconsidered.
5. A visible RMF remains the owner after 24 hours and still blocks modals until physical removal.
6. A second RMF remains blocked while the first is mounted, even after 10 minutes; after removal, cooldown and checkpoint rules decide admission.
7. Background invalidates stale foreground-readiness callbacks; a fresh full-readiness callback can retry.
8. Cooldown-denied raw rollback does not cause recursive registry churn.

Consolidated Q2 already contains broad modal/RMF lifecycle integration tests. Add only the cooldown/checkpoint and animation-specific scenarios; do not duplicate the existing suite.

## Phase 5 — Add read-only Promo Queue diagnostics

Extend the existing Modal Prompt Coordination debug screen rather than adding a parallel screen.

Expose one read-only snapshot containing:

- `PromoCoordinationMode` and a note that changes require force-quit/relaunch;
- singular owner kind and identity;
- modal attempt phase including attempt identity;
- whether recoverable pending modal work exists;
- `shouldSuppressOtherSessionPromos`;
- app/UI readiness and weak retry-registration count where useful;
- last confirmed modal and RMF timestamps;
- derived next-RMF and next-modal boundaries; and
- a note that boundaries do not schedule a retry.

The concrete manager already exposes associated identities in `ModalPromptAttemptPhase`, but its protocol does not expose all debug fields. Add the smallest read-only protocol seam, preserve the associated identities, and update mocks.

Likely wiring files:

- `ModalPromptCoordinationDebugMenu.swift`
- `PromoCoordinationService.swift`
- `ModalPromptCoordinationManager.swift` and protocol/mocks
- `DebugScreen.swift`
- `DebugScreensViewModel+Screens.swift`
- `MainViewController` debug segue/builders
- `SettingsLegacyViewProvider.swift`
- `MainCoordinator.swift`
- focused snapshot/view-model tests

Do not include rows for live transition state, plural leases, provisional ownership, or a scheduled cooldown retry. Add no new history/lease mutation controls. The existing modal cooldown reset control may remain.

## Phase 6 — Final validation and documentation

Run only the repository-approved validation after explicit test permission. At minimum the eventual implementation should cover:

- cooldown policy/store tests;
- service and manager Promo Queue tests;
- NTP model and real-SwiftUI lifecycle tests;
- modal/RMF integration tests;
- feature-flag contract tests;
- project-file validation and SwiftLint; and
- focused manual QA across the standard NTP, suggestion tray, and unified input.

Manual QA should inspect:

- all four directional rows around their boundaries;
- removal animation and ownership during dismissal;
- background/foreground readiness;
- host coverage/handoffs;
- process-latched local flag override behavior; and
- debug values before and after confirmed appearances.

Update `TECH_DESIGN_FINAL.md`, `ADDING_PROMOS.md`, the visual appendix, and `project_log.md` with the final implementation evidence. Keep temporary documentation out of the app PR.

## Optional independent correctness change

`HomePageConfiguration.didAppear` still performs an asynchronous check-then-write for `remoteMessageShownUnique`. Q2's singular owner prevents simultaneous coordinated cards but does not make the persisted first-shown transition atomic across configurations or a rapid sequential handoff.

Both agreed simplification plans classify this as independent from cooldown correctness. Do not include it silently. If separately approved, implement it as its own reviewable commit with deterministic delayed-store tests and preserve legacy behavior.

## Static exit checks

Before review, confirm:

```text
no PromoQueueFeatureState or live transition callbacks
one production read of .promoPresentationCoordination
one singular arbiter ActiveOwner
no provisional cooldown reservation/token
no cooldown scheduler/timer/boundary map
no detailed cooldown denial exposed through the public NTP facade
no production in-memory history fallback
no new Promo Queue pixel definitions or reporter
coordinated RMF uses scale + opacity, not .identity
```

## Risks to call out in the PR

- Kill-switch changes take effect only after process restart.
- One hidden or incorrectly exposed NTP can starve every coordinated promo.
- A second RMF cannot coexist with the first after 10 minutes; physical ownership is stricter than cooldown eligibility.
- Checkpoint-only liveness can delay an otherwise eligible promo indefinitely.
- Future NTP-covering hosts must integrate the exposure seam manually.
- Default Browser retained validity can be stale because Q2 intentionally reuses cached status.
- Atomic unique-shown accounting remains optional unless separately approved.

## Definition of done

Q3 is complete when:

1. all four cooldown rows use confirmed source appearances and exact inclusive boundaries;
2. modal history is reused and one RMF timestamp is persisted with the defined failure semantics;
3. competing requests acquire the singular owner before policy evaluation;
4. RMF confirmation happens once at matching card appearance and never on denial/withdrawal/build failure;
5. cooldown denials retain work and consume no accounting;
6. no time-boundary timer exists and checkpoint behavior is covered;
7. ownership survives elapsed cooldowns until truthful physical removal;
8. coordinated RMF removal retains the existing scale/opacity animation;
9. the debug screen reflects process mode, singular ownership, modal state, and cooldown history/boundaries;
10. feature-off behavior remains legacy and no live-transition machinery returns;
11. focused cooldown, lifecycle, animation, and integration coverage passes; and
12. no telemetry or privacy-config rollout change is bundled.
