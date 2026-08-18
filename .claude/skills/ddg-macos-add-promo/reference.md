# PromoService reference

All paths relative to `macOS/DuckDuckGo/Promotions/`. Before relying on any enum list, table, or signature below, re-check it against the source — these go stale silently:

```bash
grep -n 'case ' macOS/DuckDuckGo/Promotions/PromoTypes/PromoTrigger.swift
grep -n 'case ' macOS/DuckDuckGo/Promotions/PromoTypes/PromoContext.swift
sed -n '/^struct PromoType/,/^}/p' macOS/DuckDuckGo/Promotions/PromoTypes/PromoType.swift
```

The header comment of `PromoTypes/PromoType.swift` links the two canonical DDG docs — **Promo types** and **Attribute rules**. Read those links out of the file; they are the product-side source of truth for which treatment is appropriate, and this reference only covers what the code enforces.

## The whole queue is behind a feature flag

`PromoService` is only constructed inside `if featureFlagger.isFeatureOn(.promoQueue)` in `AppDelegate.applicationDidFinishLaunching`. With the flag off there is no queue and no promo shows at all — `PromoDebugMenu` even renders "Promo Queue unavailable (feature flag off)".

Consequences: a brand-new promo simply doesn't appear for users outside the rollout (usually fine). **But when migrating existing UI onto the queue, deleting the legacy presentation path removes the feature entirely for flag-off users.** See "Migrating existing UI" in SKILL.md.

## `Promo` protocol fields

| Field | Type | Meaning | Configurable on `ExternalPromo`? |
|---|---|---|---|
| `id` | `String` | Unique identifier. Must be globally unique — enforced by `PromoRegistryTests.testWhenPromoServiceCreated_ThenAllStringsAreUnique`. | yes |
| `triggers` | `Set<PromoTrigger>` | Events that cause re-evaluation. | **No — hardcoded to `[]`.** |
| `initiated` | `PromoInitiated` | `.app` (1-day global cooldown) or `.user` (1-hour). | yes |
| `promoType` | `PromoType` | Severity + timeout behavior. See table below. | yes |
| `context` | `PromoContext` | Where the promo renders. `.global` = persistent browser chrome (tab bar, address bar, toolbar) **and** anything that can appear over any page or the NTP; `.newTabPage` = inside the NTP body; `.webPage` = over web page content; `.fireWindow` = Fire Window surfaces. Extensible — DDG's own guidance allows adding a case for a genuinely new surface, but chrome is already `.global`, so that is not the reason to add one. Treat any addition the same as a new `PromoTrigger` case: a shared-enum edit needing explicit sign-off, not something to fold silently into one promo's factory file. | yes |
| `coexistingPromoIDs` | `Set<String>` | IDs allowed to be visible at the same time as this one. Must be mutual (both promos list each other) or it's a no-op. Default empty — use only with design/product sign-off (e.g. a PFR). External promos can always coexist with *each other* with no listing needed; an external promo can only coexist with an *internal* one by both listing each other here — same mutuality rule as internal-vs-internal. | yes |
| `respectsGlobalCooldown` | `Bool` | If false, can show even during another same-`initiated`-type promo's cooldown. Default `true`. | **No — hardcoded to `false`.** |
| `setsGlobalCooldown` | `Bool` | If false, dismissing this promo doesn't start the cooldown for others of the same `initiated` type. Default `true`. | yes |
| `delegate` | `(any PromoDelegate)?` | See delegate protocols below. | yes |

`InternalPromo.init` accepts `delegate: InternalPromoDelegate? = nil`; `ExternalPromo.init` accepts `delegate: ExternalPromoDelegate? = nil` — the compiler enforces the matching protocol at construction time. There is no `triggers`/`respectsGlobalCooldown` parameter on `ExternalPromo.init` at all.

## `PromoType` / `DefaultPromoType`

```swift
PromoType(_ type: DefaultPromoType,
          customTimeoutInterval: TimeInterval? = nil,
          customTimeoutResult: PromoResult? = nil)

var timeoutInterval: TimeInterval? { customTimeoutInterval ?? type.timeoutInterval }
var timeoutResult: PromoResult     { customTimeoutResult   ?? type.timeoutResult }
```

Both overrides are plain `??` fallbacks. Omit them to use the base type's defaults below.

| `DefaultPromoType` | severity | default `timeoutInterval` | default `timeoutResult` |
|---|---|---|---|
| `appModal` | high | — | `.noChange` |
| `enhancedFeatureTip` | high | 10s | `.ignored(cooldown: .day)` |
| `specialPage` | high | — | `.noChange` |
| `nextSteps` | medium | — | `.noChange` |
| `remoteMessage` | medium | — | `.noChange` |
| `banner` | medium | — | `.noChange` |
| `featureTip` | medium | 5s | `.ignored(cooldown: .day)` |
| `infoBar` | medium | — | `.noChange` |
| `semiModal` | medium | — | `.noChange` |
| `contentCoverSheet` | medium | — | `.noChange` |
| `progressiveEmphasisButton` | medium | 30s | `.ignored(cooldown: .day)` |
| `inlineMessage` | low | — | `.noChange` |
| `nudgeButton` | low | 7 days | `.ignored()` (permanent) |
| `emptyStateMessage` | low | — | `.noChange` |
| `inlineTip` | low | 5 days | `.ignored()` (permanent) |
| `textBadge` | low | 5 days | `.ignored()` (permanent) |
| `dotBadge` | low | 3 days | `.ignored()` (permanent) |
| `menuItemHighlight` | low | 5 days | `.ignored()` (permanent) |
| `settingsRecommendedAction` | low | — | `.noChange` |

**"Never auto-dismiss" is not expressible as an override.** Because `timeoutInterval` is `customTimeoutInterval ?? type.timeoutInterval`, `nil` means *inherit the base type's default*, not *no timeout*. There is no value you can pass that clears a base type's timeout. Consequences:

- A promo that must stay up until the user acts has to use a base type whose own `timeoutInterval` is already `nil` — which ties "no timeout" to the severity/treatment of that type. `.featureTip` with no override auto-dismisses after 5s, whatever the spec says.
- If the severity the promo needs and the "no timeout" it needs don't come in the same `DefaultPromoType`, the options are a different type or a change to `DefaultPromoType` itself. Both are decisions to flag, not to pick.
- `customTimeoutResult` is only ever reached when there *is* a timeout, so setting it on a type with a `nil` interval is dead configuration.

`PromoSeverity` (`low < medium < high`, `Comparable`):
- **low** — doesn't get in the way of another action; minimal distraction. Example: highlighting a button via animation.
- **medium** — may get in the way of another action; some distraction. Example: an arrow tip highlighting a feature.
- **high** — does get in the way; distracts or blocks the current task. Example: a Set-as-Default dialog.

## `checkRules(for:)` — what gates showing an internal promo **via a trigger** (`PromoService.swift`)

Runs top to bottom; any `false` skips the promo for this evaluation. **This gates the trigger path only — the restore path below skips all of it.**

Before `checkRules` is even reached, `evaluateTriggers` opens with `guard isOnboardingCompletedProvider() else { return }` — **no promo can be shown by any trigger until onboarding is complete**, and because it's a bare `return` the triggers are discarded rather than deferred. `restoreVisiblePromos` has no equivalent check, so restore can present during onboarding when the trigger path cannot.

1. **`if promo.promoType.severity == .low { return true }`** — a low-severity promo always passes, immediately, before any of the checks below run. Low severity is **symmetric**: a low-severity promo is never blocked, and (since the loop in step 3 skips low-severity others) never blocks anything either. Low-severity promos sit outside the global rules entirely, in both directions.
2. If the app was just externally activated (deep link), fail — short suppression window.
3. **Context/coexistence conflict**: for every other currently-visible promo **of medium+ severity** (low-severity others are skipped, per step 1), conflict = `context == .global || other.context == .global || context == other.context`, **unless** both promos mutually list each other in `coexistingPromoIDs` (mutual coexistence overrides even a `.global`-vs-anything conflict). Any conflict → fail.

   The rule is **one medium+ promo per context** — so two medium promos in *different* non-global contexts (e.g. `.newTabPage` and `.webPage`) coexist for free, with no `coexistingPromoIDs` listing. Only `.global` is exclusive with everything. In particular a visible `.newTabPage` promo such as Next Steps does **not** block a `.webPage` promo.
4. *(No separate severity gate — severity is folded into step 3 as the medium+ filter.)*
5. **Global cooldown**: if `respectsGlobalCooldown` and severity ≥ medium, fail if **any** promo with the same `initiated` type, `setsGlobalCooldown == true`, **and severity ≥ medium** was last dismissed less than `initiated.cooldown` ago. Two easily-missed details:
   - **The filter does not exclude the promo itself** (`$0.initiated == promo.initiated && $0.setsGlobalCooldown && $0.promoType.severity >= .medium` — no `$0.id != promo.id`). A promo's own last dismissal therefore gates its own re-show.
   - **This silently overrides a shorter `customTimeoutResult` cooldown.** If your promo is medium+ severity with both `respectsGlobalCooldown` and `setsGlobalCooldown` true, a `customTimeoutResult: .ignored(cooldown: .hours(2))` has no practical effect: `record.isEligible` passes after 2h, then this check fails until `initiated.cooldown` elapses (1 day for `.app`, 1 hour for `.user`). To actually get a sub-cooldown re-show you must also set `setsGlobalCooldown: false` — which needs design/product sign-off.
   - Low-severity promos neither respect *nor* contribute to this cooldown (they return at step 1, and they're filtered out of the set).

### The restore path bypasses every rule above

`restoreVisiblePromos()` runs once at registration and calls `performShow` **without** `checkRules`, **without** `record.isEligible(asOf:)`, and **without** any permanent-dismissal check. Its only gates are: no external-activation suppression, the delegate is an `InternalPromoDelegate`, `record.lastShown != nil`, `lastDismissed == nil || lastDismissed < lastShown` ("was visible at shutdown"), and `delegate.isEligible` after a `refreshEligibility()`.

So: two restored promos can be visible together in conflicting contexts, and a permanently-dismissed promo *can* reappear this way. If the app is killed while your promo is on screen, it comes back at next launch regardless of severity, context, or cooldown.

If your promo must not survive a restart, make sure it resolves with a result that clears `lastShown` — `.noChange` does (`applyResult` sets `record.lastShown = nil`). Promos with short timeouts are the most likely to hit this, since the odds of being killed mid-display are highest.

External-promo visibility changes are **not** gated by `checkRules` at all — an external promo becoming visible can never be blocked. But when it becomes visible, `PromoService` retracts (`hide`s) any currently-visible *internal* promo that would now fail `checkRules` given the external promo's presence (`hideInternalPromosConflictingWithCurrentVisibility`). That retraction check is a normal `checkRules(for: internalPromo)` call, so it **does** consult `coexistingPromoIDs` mutuality against the external promo just like it would against another internal one — a mutual listing is the correct (and only) way to stop a medium/high-severity internal promo from being evicted when an external promo appears in a conflicting context. (A low-severity internal promo never needs this — it already can't be evicted, per the severity bypass above.)

## Delegate protocols (`PromoDelegate.swift`)

```swift
protocol PromoDelegate: AnyObject { }   // type-erased base; stored on Promo.delegate

protocol InternalPromoDelegate: PromoDelegate {
    var isEligible: Bool { get }
    var isEligiblePublisher: AnyPublisher<Bool, Never> { get }   // must replay current value on subscribe
    func refreshEligibility()                                    // default no-op; override to recompute just before evaluation
    @MainActor func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult
    @MainActor func hide()                                        // must be idempotent
}

protocol ExternalPromoDelegate: PromoDelegate {
    var isVisible: Bool { get }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { get }     // must replay current value on subscribe
    var resultWhenHidden: PromoResult { get }
}
```

### Isolation: only `show`/`hide` are `@MainActor` — do not annotate the class

Read the protocol above carefully. `show()` and `hide()` are `@MainActor`; `isEligible`, `isEligiblePublisher`, and `refreshEligibility()` deliberately are **not**, because `PromoService` reads them on its private background `stateQueue` under `dispatchPrecondition(condition: .onQueue(stateQueue))`.

**Marking the whole delegate class `@MainActor` is wrong**, even though it compiles today (`SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`). It makes `refreshEligibility()` and `isEligible` main-actor members that the service then reads off the main thread, and it becomes a hard error under Swift 6. All four existing `InternalPromoDelegate` implementations annotate only `show`/`hide`; follow them. (`ExternalPromoDelegate` has no `@MainActor` members at all.)

Keep eligibility state in a `CurrentValueSubject` so it's safe to read off-main, and apply `.removeDuplicates()` to `isEligiblePublisher` (every existing delegate does).

### The `show()`/`hide()` continuation contract

`show()` is `async` and must not return until the promo resolves, so delegates suspend in `withCheckedContinuation`. The part that isn't obvious: **`hide()` must itself resume any still-pending continuation.**

`recordResultAndCleanup` cancels the `showTask` and *then* calls `hide()`. Cancelling a task suspended in `withCheckedContinuation` does **not** resume it — so if `hide()` doesn't resume, the awaiting task leaks and the promo never cleans up. Conversely `hide()` resuming can't corrupt the real result: `isResultRecorded` is first-write-wins and is set before `hide()` runs.

Canonical shape (matches all four existing internal delegates):

```swift
final class MyPromoDelegate: InternalPromoDelegate {   // NOT @MainActor at class level
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        await withCheckedContinuation { continuation in
            resultContinuation = continuation
            presentUI()
        }
    }

    @MainActor
    func hide() {
        tearDownUI()                       // guard every teardown — hide() is called even post-teardown
        resolve(with: .noChange)           // resumes if still pending; no-op if already resolved
    }

    /// Single funnel for every resolution path. Nil the continuation *before* resuming.
    @MainActor
    private func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        tearDownUI()
        continuation.resume(returning: result)
    }
}
```

Also resolve on presentation *failure* — if your `show` path can fail to present (e.g. no key window), call `resolve(with: .noChange)` rather than returning while still suspended.

`force: true` on `show()` is passed only by the debug menu's "Force Show" action (bypasses all eligibility/rules, no history change) — it has no effect for external promos, which don't have a `forceShow` path at all (`PromoService.forceShow` no-ops if the delegate isn't `InternalPromoDelegate`).

**`isEligiblePublisher`/`isVisiblePublisher` emitting `true` does not, by itself, cause a new show.** There are exactly two paths into `performShow`: `evaluateTriggers` (needs a matching `PromoTrigger` to have just fired, and is gated by `checkRules`) and `restoreVisiblePromos` (runs once at registration for promos whose history says they were visible at last shutdown, and is gated by **nothing** except `delegate.isEligible` — see the restore-path section above). The publisher going `true` while the promo isn't already showing does nothing on its own — it's only actively watched, via `.dropFirst()`, to *retract* an already-showing promo when it flips to `false` (`handleEligibilityLost`). A promo meant to appear reactively the instant some condition becomes true needs that condition paired with an actual `PromoTrigger` firing, not eligibility alone.

## `PromoResult`

| Value | Meaning | History effect |
|---|---|---|
| `.actioned` | User engaged the CTA | **Permanent. Never eligible again, ever.** Sets `actioned = true` + `nextEligibleDate = .distantFuture` |
| `.ignored()` (cooldown `nil`, default) | Dismissed without engaging | **Permanent.** Sets `nextEligibleDate = .distantFuture` |
| `.ignored(cooldown: interval)` | Dismissed without engaging | Temporarily dismissed — eligible again after `interval` |
| `.noChange` | Retracted or errored | Clears `lastShown` (so it won't be restored after a restart); otherwise no change — eligible again on next trigger |

### "Permanent" means permanent — and history is keyed by `id` alone

`PromoHistoryRecord.isEligible(asOf:)` opens with `guard !actioned else { return false }`. There is **no** per-version, per-occurrence, or per-session scoping on a promo's history — just the `id` string, persisted for the life of the profile. Nothing resets it outside the debug menu's Undismiss.

**So a recurring promo must never resolve `.actioned` or bare `.ignored()`.** This is the single easiest way to ship a promo that works once and then silently disappears forever.

Decide explicitly which kind you have:

| Intent | Resolve the CTA tap with |
|---|---|
| One-shot: "once they've done this, never ask again" (set-as-default, onboarding) | `.actioned` |
| Recurring: should return on the next version / next occurrence / after N days | `.ignored(cooldown: <the recurrence interval>)`, or `.noChange` to re-show on the next trigger |

Note the trap this creates: engaging with the CTA is the path that permanently retires the promo, while *dismissing* it (`.ignored(cooldown:)`) brings it back. For anything recurring, that's backwards from what a spec usually means — a user who taps "update now" is the one you most want to reach next release. Read your resolution paths and check that the more enthusiastic user doesn't get the more permanent silence.

## `PromoTrigger`

Fixed enum, each case mapped in `PromoTrigger.triggerPublisher` to a `NotificationCenter` name (carries no payload — only "something happened, re-check eligibility"). External promos always have `triggers = []` — adding a case here never affects them.

Do not trust a list of cases written down here; read them:

```bash
grep -n 'case ' macOS/DuckDuckGo/Promotions/PromoTypes/PromoTrigger.swift
```

To add a new trigger: add the case, then merge the corresponding notification/publisher into `triggerPublisher`. This is a shared-file edit, not something you can express purely inside a new `PromoServiceFactory+*.swift` file — flag it as a required change up front, and see "Step 2.1" in SKILL.md for the full process.

**Triggers fire once; a missed trigger is not retried.** `evaluateTriggers` reacts to the event as it arrives. If `checkRules` fails at that instant (another promo visible, global cooldown active, external-activation suppression window), the promo is simply skipped — nothing re-queues it, and nothing is logged. A one-shot trigger paired with a medium+ `.global` promo is therefore easy to lose entirely for a session. Pair such triggers with a recurring one (`.windowBecameKey` is what all three `defaultBrowserAndDock` promos use precisely to get retries), or have the posting code re-post while the condition holds.

**A trigger cannot deliver state that was already true.** Triggers arriving before `PromoService` finishes registering are buffered, but a notification posted before the service is *constructed* is lost outright. If your condition can already hold at launch, a dedicated trigger is not enough: pair it with `.appLaunched` and make `isEligible`/`refreshEligibility()` re-derive the condition from current state rather than from having observed the event.

## Setting the delegate — the two patterns

**Pattern A — at construction** (`PromoServiceFactory+AutoplayDiscoverability.swift`): build the delegate and pass it straight into the `Promo` initializer. Use when the delegate's dependencies already exist in `PromoDependencies` when `makeAllPromos` runs.

**Pattern B — deferred** (`PromoServiceFactory+FreemiumDBP.swift` declares `delegate: nil`; `NewTabPageActionsManagerExtension.swift` later calls `promoService.setDelegate(for: id, delegate:)`): use when the delegate can only be built once some other module (e.g. the New Tab Page) finishes constructing. Registration has a **1-second fallback timeout** after `PromoService.start()` — if not every promo's delegate has registered by then, evaluation proceeds anyway with whichever have. A promo whose delegate arrives late can silently miss its first eligible trigger.

`setDelegate(for:delegate:)` takes the type-erased `any PromoDelegate` — unlike the initializers, it does **not** enforce the protocol matching the `Promo` subtype at compile time. `PromoService` downcasts (`as? InternalPromoDelegate` / `as? ExternalPromoDelegate`) everywhere it acts on a delegate; a mismatched delegate set this way compiles, runs, and is silently never evaluated (no log). No test covers the protocol-mismatch case; the closest is `PromoServiceTests.testWhenPromoWithoutDelegate_ThenSkippedDuringEvaluation`, which covers a **nil** delegate and demonstrates the same silent-skip behavior.

## Priority order — how the array position actually acts

`PromoServiceFactory.makeAllPromos(dependencies:)` returns a flat `[Promo]` and the comment on `PromoService.promos` states it plainly: *"Fixed list of promos (array order = priority order)"*. There is no numeric priority field and nothing sorts the array at runtime.

`evaluateTriggers` filters to the promos matching the fired trigger, **preserving array order**, then loops:

```swift
let matchingPromos = promos.filter { $0.triggers.contains(where: triggers.contains) }
for promo in matchingPromos { (promo.delegate as? InternalPromoDelegate)?.refreshEligibility() }

for promo in matchingPromos {
    guard activeSessions[promo.id] == nil,
          let delegate = promo.delegate as? InternalPromoDelegate,
          checkRules(for: promo) else { continue }
    ...
    performShow(promo: promo, delegate: delegate, record: record, isRestore: false)
}
```

So position has three effects, all of them silent:

1. **On a shared trigger, the earlier promo shows first** — and once it's in `activeSessions`, every later medium+ promo in a conflicting context fails `checkRules` step 3 for that evaluation.
2. **The loser is not re-queued.** Nothing retries it, nothing is logged (see "Triggers fire once" below).
3. **A medium+ `.global` promo near the end of the array is the most suppressible thing in the app** — `.global` conflicts with every context, so any earlier promo that shows first blocks it.

Position is therefore a product decision about which promo yields to which, not a code-organization detail. Read the current order from the source rather than any list written down here:

```bash
sed -n '/var promos: \[Promo\] = \[/,/^        \]/p' macOS/DuckDuckGo/Promotions/PromoServiceFactory.swift
```

## Test fixtures and the id-uniqueness guard

Existing helpers in `macOS/UnitTests/Promotions/`: `PromoTestHelpers.makePromo(...)`, `Mocks/MockPromoDelegate.swift`, `MockExternalPromoDelegate.swift`, `MockPromoHistoryStore.swift`, and a `PassthroughSubject`-backed trigger publisher. `AutoplayDiscoverabilityPromoDelegateTests.swift` is the model for a delegate test.

`PromoRegistryTests.testWhenPromoServiceCreated_ThenAllStringsAreUnique` is the repo's only global id-collision guard. **It only covers promos actually present in the constructed service** — so if your factory function returns `nil` when a dependency is missing and the test passes `nil` for that dependency, your promo's id is silently excluded from the check. Pass a mock so it's included.

Any new field on `PromoDependencies` requires updating `PromoRegistryTests` and `PromoServiceFactoryTests.makeDependencies()`.
