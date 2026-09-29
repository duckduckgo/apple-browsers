# Implementing a promo

Read this only after the user has approved the plan (SKILL.md Step 4). Sections match the plan's tasks; a subagent reads the section for its task plus "Rules for every task". Field and runtime detail lives in [reference.md](reference.md).

## Rules for every task

- **Build what the plan says.** A decision the plan doesn't cover goes back to the user (or, as a subagent, back to the main session) — don't choose.
- **Comments explain WHY, not WHAT** (`.cursor/rules/code-style.mdc`), `//` and `///` only. Promo code attracts three violations:
  1. Restating the declaration (`/// Builds the Bookmark Toolbar Promo.` above `bookmarkToolbar(dependencies:)`). Existing factory files are full of this — don't copy it, don't churn it. Name what the reader can't see instead: the user-facing string, the legacy UI it replaces.
  2. Describing behavior the fields declare ("shown at most once ever") — it duplicates the `PromoResult`s and goes stale. Let the resolution paths say it; put the intent in a test name.
  3. Justifying a field by the rule it evades — that's the smell test in SKILL.md, a wrong field rather than a comment problem.

  Worth a comment: why a presentation is deferred a run loop, why a window close counts as a dismissal, why a user who already has the UI visible is retired.

## A. Shared enums and flags

**New `PromoTrigger` case** (`macOS/DuckDuckGo/Promotions/PromoTypes/PromoTrigger.swift`): the case, a `Notification.Name` merged into `triggerPublisher`, and the post at the call site named in the plan. Put the sign-off note **on the case**, where the next author sees it.

**New `PromoContext` case**: confirm nothing switches over it exhaustively (`grep -rn 'switch.*context' macOS/DuckDuckGo/Promotions/`); it's only compared with `==` in `checkRules`. Sign-off note on the case.

**Kill switch** — three edits (existing ones: `grep -n 'case promoQueue' macOS/LocalPackages/FeatureFlags-macOS/Sources/FeatureFlags/FeatureFlag.swift`):

| Edit | File |
|---|---|
| `case promoQueue<Name>Promo`, with a `///` line linking its Asana task | `macOS/LocalPackages/FeatureFlags-macOS/Sources/FeatureFlags/FeatureFlag.swift` |
| Its arm in the `FeatureFlagDescribing` switch: `Config(defaultValue: .enabled, source: .remoteReleasable(PromoQueueSubfeature.<name>Promo))` | same file |
| `case <name>Promo` on `PromoQueueSubfeature` | `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift` |

`.enabled` over `.remoteReleasable` makes it a kill switch, not a rollout gate; default `.disabled` only if product asked for a staged rollout. It's checked in the delegate (task B), never in the factory.

## B. Delegate and UI

**Location:** with the feature being promoted, next to the UI it presents — never under `Promotions/`. A `Promo/` subdirectory is the convention when the feature directory is busy. See where the others live:

```bash
grep -rlE ': .*(Internal|External)PromoDelegate' macOS/DuckDuckGo --include='*.swift' | grep -v '/Promotions/'
```

**Model it on the closest existing promo** — read its factory file, delegate, and test first:

| Shape | Model on |
|---|---|
| Migrated popover: kill switch, legacy flag → `.retired`, `KeyedStorage`, mutual Next Steps coexistence | `BookmarkToolbarPromoDelegate` + tests |
| UI owned by a view controller, reached through a presenter protocol that tests mock | `AutofillToolbarPinningPromoDelegate` (`AutofillToolbarPinningPromoPresenting`) |
| Eligibility computed from several feature states via `refreshEligibility()` | `CookiePopupsBlockedPromoDelegate`, `SyncFaviconsPromoDelegate` |
| Recurring promo whose CTA must not retire it | `UpdateAvailablePromoDelegate` (every path → `.ignored(cooldown: .days(7))`) |
| Popover keeping hover-to-keep-open under the queue's timeout | `UpdateAvailablePromoDelegate.hide()` → `dismissPopoverUnlessHovering()` |
| External, with its own limiter deciding recurrence | `BrokenSitePromptPresentationCoordinator` (`resultWhenHidden: .ignored(cooldown: 0)`) |
| External, visibility derived from observed state, with a kill switch | `DuckPlayerOverlayObserver` |
| External modal that waits for conflicting promos to be retracted | `QuitSurveyPromoObserver` (`promoServiceDidApplyVisibility`) |

**`InternalPromoDelegate`** — protocol and canonical skeleton in [reference.md](reference.md) ("Delegate protocols"):
- `isEligible` / `isEligiblePublisher` reflect **current** state only. Don't record "shown before" yourself — `PromoService`'s history does that from the `PromoResult` you return. The publisher replays its current value on subscribe (`CurrentValueSubject` or `.prepend`) and uses `.removeDuplicates()`. Eligibility turning `true` never shows the promo by itself — only a trigger (or restore) does; turning `false` retracts it.
- The kill switch is the first check in eligibility: `featureFlagger.isFeatureOn(.promoQueue<Name>Promo)`, with `featureFlagger.updatesPublisher` merged into the publisher (see `BookmarkToolbarPromoDelegate`), or the first `guard` of an existing `refreshEligibility()` computation.
- `show(history:force:)` presents the UI and returns only when the promo resolves. Return the plan's result on each path — check the CTA path against one-shot vs. recurring.
- `hide()` is idempotent and **resumes any pending continuation itself** (cancelling the task doesn't), or the awaiting task leaks. It's called after every result, even when the UI is already gone.
- **Resolve on presentation failure** (no key window, missing anchor) with `.noChange`, or `show()` never returns.
- Annotate **only `show`/`hide`** `@MainActor`, never the class: eligibility is read on `PromoService`'s background queue. Class-level `@MainActor` compiles today and is wrong.
- Popovers: pass `autoDismissDuration: nil` to `PopoverMessageViewController` — the queue owns the timeout.

**`ExternalPromoDelegate`**: `isVisible` / `isVisiblePublisher` (seeded synchronously so it's correct at registration, replaying on subscribe), a fixed `resultWhenHidden`, and optionally `promoServiceDidApplyVisibility`. You get no callback saying *why* visibility went false. The kill switch gates `isVisible`, which turns off coordination, not the UI.

## C. Wiring

1. **Factory file** `macOS/DuckDuckGo/Promotions/Promos/PromoServiceFactory+<Name>.swift`, containing only the definition:

   ```swift
   extension PromoServiceFactory {

       static let bookmarkToolbarPromoID = "bookmark-toolbar"

       /// Builds the Bookmark Toolbar Promo ("Show Bookmarks Bar?" popover).
       @MainActor
       static func bookmarkToolbar(dependencies: PromoDependencies) -> Promo {
           InternalPromo(
               id: bookmarkToolbarPromoID,
               triggers: [.bookmarkAdded, .bookmarksImported],
               initiated: .user,
               promoType: PromoType(.semiModal),
               context: .global,
               coexistingPromoIDs: [PromoServiceFactory.nextSteps.id],
               delegate: BookmarkToolbarPromoDelegate(
                   featureFlagger: dependencies.featureFlagger,
                   windowControllersManager: dependencies.windowControllersManager
               )
           )
       }
   }
   ```

   If the plan includes coexistence, add your ID to the other promo's `coexistingPromoIDs` too (here, `nextSteps` lists `bookmarkToolbarPromoID`) — one-sided listings are inert.
2. **`PromoDependencies`**: any new field the delegate needs.
3. **`makeAllPromos`**: insert at the position in the plan. Keep it a flat list: if a dependency may be absent, register the promo anyway and return `false` from `isEligible`. Don't return `Promo?` and conditionally add it — that hides the promo from the priority list and from the id-uniqueness test. (`browserUpdated` does this; don't copy it.)
4. **Delegate timing.** Pass the delegate into the initializer whenever its dependencies exist when `makeAllPromos` runs. Otherwise declare `delegate: nil` and call `promoService.setDelegate(for:delegate:)` when it's built (as `NewTabPageActionsManagerExtension.swift` does for Freemium DBP). Two risks: registration waits only **1 second** after `start()`, so a late delegate can miss its first trigger; and `setDelegate` takes `any PromoDelegate`, so a delegate conforming to the wrong protocol compiles and is silently never evaluated. Check the conformance by hand.
5. **The trigger's post**, at the call site the plan names.

## D. Legacy removal (migrations)

Follow [migrating.md](migrating.md) items 3–6: delete the old presentation path, move the "already shown" flag onto `KeyedStorage` for the `.retired` check, and clean up dead code.

## E. Tests

Delegate tests go in `macOS/UnitTests/Promotions/` (not under the feature), next to the shared mocks in `Mocks/`. Model on the closest `<Name>PromoDelegateTests.swift` (`BookmarkToolbarPromoDelegateTests` for a migration). Test behavior, not just configuration:

- the `PromoResult` of **each** resolution path — the CTA path is where a recurring promo gets retired by mistake
- eligibility flipping false while showing
- `hide()` before any resolution, and twice
- a new trigger: posting the notification yields your `PromoTrigger` case
- the kill switch off → not eligible
- migrations: `show()` returns `.retired` when the legacy key is set, and doesn't when `force: true`

Use `MockFeatureFlagger` and `KeyedStorage(storage: InMemoryKeyValueStore())`, so no test touches `UserDefaults.standard`. For any new `PromoDependencies` field, update `PromoRegistryTests` and `PromoServiceFactoryTests.makeDependencies()`, and make sure your promo is present in the service the registry test builds — it's the only id-uniqueness check.

## F. Project and verification

1. **pbxproj**: each new file needs a `PBXFileReference`, a group entry, and a `PBXBuildFile` + Sources entry in **both** "DuckDuckGo Privacy Browser" and "DuckDuckGo Privacy Browser App Store" (mirror `AutoplayDiscoverabilityPromoDelegate.swift`). A missing file causes "cannot find type" errors elsewhere. `grep -c "<File>.swift" macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj` should be at least 4; the pbxproj diff should contain only your additions.
2. **Build and test**: `xcodebuild -project macOS/DuckDuckGo-macOS.xcodeproj -scheme "macOS Browser" build 2>&1 | tail -20`, then the promo tests.
3. **See it on screen** via the debug menu (`PromoDebugMenu`): per-promo **Force Show**, **Undismiss**, **Undismiss + Clear History**; **Fire Test Trigger**; **Advance Simulated Date** (which also expires active timeouts); **Reset All Promo State**. Force Show runs a real session — timeout, retraction and `hide()` behave as in production — but writes no history and passes `force: true`, so it bypasses `.retired`. If nothing shows, check the kill switch first.
4. **Self-review**: walk your diff through [reviewing.md](reviewing.md) as if it were someone else's PR. Every decision in the diff must trace to an answer in the decision sheet — one you noted yourself and proceeded past doesn't count.
5. **PR description**: the decision sheet, the priority reasoning, and any call the user made in the moment.
