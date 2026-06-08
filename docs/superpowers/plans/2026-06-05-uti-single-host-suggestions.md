# UTI Single-Host Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the UTI's two crossfading suggestion surfaces (Search host + Duck.ai host) into **one** resolver-driven `UnifiedSuggestionsHost`, so mode switches become a single SwiftUI content swap instead of an alpha crossfade between two stacked containers — eliminating the whole class of transition bugs (favorites reflow, hatch hitch, recents-over-grid overlap).

**Architecture:** One hosting controller renders `UnifiedSuggestionsView`. Its `content` comes from `UnifiedSuggestionsContentResolver` fed by ONE merged inputs publisher (mode + text + search facts + duck.ai facts). Both data surfaces keep their **own** `SuggestionsSource` + `AutocompleteRequestRunner` + `SuggestionsListViewModel` (preserving the Part 2b per-surface runner separation that fixed mutual DDG-request cancellation). The view picks the active list VM by content kind. Transition feel is controlled in SwiftUI per content-kind (instant to grid/logo, crossfade list↔list). The legacy `OmniBarEditingStateViewController` keeps `SwipeContainerManager` untouched — only the UTI stops using it.

**Tech Stack:** UIKit container + `UIHostingController<UnifiedSuggestionsView>`, Combine publishers, SwiftUI transitions/transactions, `os.Logger` ("UTITransition") for on-device verification.

---

## Why this works (facts established during scoping)

- `UnifiedSuggestionsContentResolver.resolve` is **already** a single decision table covering both `.search` and `.aiChat`. The two-host split is leftover transport, not a content-model requirement.
- The two hosts differ only in: source (`SearchSuggestionsSource` vs `DuckAISuggestionsSource`), per-surface `AutocompleteRequestRunner`/loaders, inputs publisher (mode hardcoded), favorites provider (search builds a heavy `NewTabPageViewController`; duck.ai passes `nil`). Everything else (`UnifiedSuggestionsHost`, `UnifiedSuggestionsView`, `SuggestionsListView`, escape hatch, inset) is already shared/generic.
- `DaxLogoManager` is an independent overlay in `contentContainerView` (brought to front), **not** embedded in either host → unaffected.
- `SwipeContainerManager`/`FadeOutContainerViewController`/`SwipeContainerViewController` live in `AIChat/InputBox/SwitchBar/` and are **also used by `OmniBarEditingStateViewController`** (legacy/iPad). They must remain; this plan only removes their use from `UnifiedInputContentContainerViewController`.

## Design decisions (confirm before execution)

1. **Two sources/runners/list-VMs, one host+view (RECOMMENDED).** Keep both `SuggestionsSource`s alive with their own runners; the single view renders `searchListVM` for `.list(.search)` and `duckAIListVM` for `.list(.duckAI|.recents)`. Preserves the mutual-cancellation fix and avoids row-ID prefix collisions. *(Alternative — one source router muxing by mode — risks reintroducing the runner-cancellation bug; rejected.)*
2. **Transition policy:** content-kind-aware. `→ .favorites` or `→ .logo`: the outgoing content is removed with **no fade** (`.transaction { $0.animation = nil }` on removal) so nothing draws over the grid; **list↔list** uses a content crossfade/opacity transition ("same list, different models"). Defined centrally in `UnifiedSuggestionsView`.
3. **Duck.ai lazy lifecycle preserved.** Today the duck.ai host is built on `viewWillAppear` and torn down on `viewDidDisappear`/rebuild. The merged host keeps the duck.ai **source** lazy: it may be `nil` until installed; resolver inputs treat absent duck.ai as `hasRecents=false`. Search source stays permanent. This preserves memory/perf behavior.
4. **Inset/escape-hatch** attach to the single hosting controller (one `setAdditionalTopInset`, one `additionalSafeAreaInsets`) instead of two.
5. **Out of scope:** any change to `OmniBarEditingStateViewController`, the paged `SwipeContainerViewController`, or the iPad/legacy transition. Those stay as-is.

## File structure

- **Modify** `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputContentContainerViewController.swift` — replace `installSwipeContainer` + two `install*Suggestions` host installs with one `installUnifiedSuggestionsHost`; route inset/escape-hatch/dax-visibility/teardown to the single host; drop `SwipeContainerManager`, the `SwipeContainerViewControllerDelegate`/`FadeOutContainerViewControllerDelegate` conformances, and `didSwipeToMode`/`didTransitionToMode` dead code.
- **Modify** `iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsHostConfig.swift` — support two sources/list-VMs + a single merged inputs publisher + optional duck.ai facts.
- **Modify** `iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsHost.swift` — hold two `SuggestionsListViewModel`s; expose which is active by content kind; one hosting controller; teardown handles optional duck.ai.
- **Modify** `iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsView.swift` — pick list VM by `content`; apply content-kind-aware transition policy.
- **Create** `iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsInputsMerger.swift` — pure function merging (mode, text, searchFacts, duckAIFacts) → `UnifiedSuggestionsInputs`. Unit-tested.
- **Create** `iOSTests/.../UnifiedSuggestionsInputsMergerTests.swift` — unit tests for the merge logic.
- **No deletion** of `SwipeContainerManager`/`FadeOut*`/`Swipe*` (still used by legacy).

---

## Task 0: Safety net — capture current verified behavior

**Files:** none (manual).

- [ ] **Step 1:** Confirm on Build ≥09 that the three already-fixed behaviors still hold (hatch lockstep, favorites no-reflow, recents instant-hide to grid). Record a short note of expected transition feel for each mode pair (search↔duckai × blank/typing) to compare against after refactor.
- [ ] **Step 2:** Keep the `UTITransition` logger and existing log points in place throughout this refactor (per project rule: no stripping debug logs until the user confirms green).

## Task 1: Pure inputs merger (unit-tested)

**Files:**
- Create: `iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsInputsMerger.swift`
- Test: `iOSTests/UnifiedToggleInput/UnifiedSuggestionsInputsMergerTests.swift`

- [ ] **Step 1: Write the failing test** — covers: search+blank+favorites→inputs(mode:.search,isTyping:false,hasFavorites:true); search+typing→isTyping:true; aichat+blank+recents→(mode:.aiChat,hasRecents:true); aichat+typing+pending→(resultsPending:true); aichat with duck.ai source absent→hasRecents:false,resultsPending:false.

```swift
func test_search_blank_with_favorites_resolves_favorites_inputs() {
    let i = UnifiedSuggestionsInputsMerger.merge(
        mode: .search, text: "",
        search: .init(hasFavorites: true, hasMessages: false),
        duckAI: nil)
    XCTAssertEqual(i, UnifiedSuggestionsInputs(mode: .search, isTyping: false,
        hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
}

func test_aichat_typing_pending_sets_resultsPending() {
    let i = UnifiedSuggestionsInputsMerger.merge(
        mode: .aiChat, text: "foo",
        search: .init(hasFavorites: false, hasMessages: false),
        duckAI: .init(hasRecents: false, settled: false))
    XCTAssertEqual(i.resultsPending, true)
    XCTAssertEqual(i.isTyping, true)
}

func test_aichat_without_duckAI_source_has_no_recents() {
    let i = UnifiedSuggestionsInputsMerger.merge(
        mode: .aiChat, text: "",
        search: .init(hasFavorites: true, hasMessages: false),
        duckAI: nil)
    XCTAssertEqual(i.hasRecents, false)
    XCTAssertEqual(i.resultsPending, false)
}
```

- [ ] **Step 2: Run (RunSomeTests) → FAIL** (merger undefined).
- [ ] **Step 3: Implement** the merger:

```swift
enum UnifiedSuggestionsInputsMerger {
    struct SearchFacts { let hasFavorites: Bool; let hasMessages: Bool }
    struct DuckAIFacts { let hasRecents: Bool; let settled: Bool }

    static func merge(mode: TextEntryMode, text: String,
                      search: SearchFacts, duckAI: DuckAIFacts?) -> UnifiedSuggestionsInputs {
        let isTyping = !text.isEmpty
        switch mode {
        case .search:
            return UnifiedSuggestionsInputs(mode: .search, isTyping: isTyping,
                hasFavorites: search.hasFavorites, hasMessages: search.hasMessages,
                hasRecents: false, resultsPending: false)
        case .aiChat:
            return UnifiedSuggestionsInputs(mode: .aiChat, isTyping: isTyping,
                hasFavorites: false, hasMessages: false,
                hasRecents: duckAI?.hasRecents ?? false,
                resultsPending: isTyping && (duckAI.map { !$0.settled } ?? false))
        }
    }
}
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(uti): pure inputs merger for unified suggestions host`.

## Task 2: Host config + host hold two list VMs

**Files:**
- Modify: `.../Suggestions/UnifiedSuggestionsHostConfig.swift`
- Modify: `.../Suggestions/UnifiedSuggestionsHost.swift`

- [ ] **Step 1:** Extend `UnifiedSuggestionsHostConfig` to carry `searchSource`, an optional `duckAISourceProvider: () -> SuggestionsSource?`, a single `inputsPublisher` (merged), `favoritesProvider`, and per-source row handlers (select/delete/tapAhead) keyed by which source produced the row.
- [ ] **Step 2:** In `UnifiedSuggestionsHost`, build `searchListViewModel` (always) and a lazily-attached `duckAIListViewModel` (when the duck.ai source exists). The `UnifiedSuggestionsViewModel.content` stays driven by the merged `inputsPublisher` + resolver.
- [ ] **Step 3:** `tearDownDuckAI()` releases the duck.ai source/VM only (search persists), mirroring today's lazy lifecycle; full `tearDown()` releases both.
- [ ] **Step 4: BuildProject → success.**
- [ ] **Step 5: Commit** `refactor(uti): host carries search + optional duck.ai list view models`.

## Task 3: View renders by content kind + transition policy

**Files:** Modify `.../Suggestions/UnifiedSuggestionsView.swift`

- [ ] **Step 1:** Pass both list VMs (duck.ai optional) into the view. Render `searchListVM` for `.list(.search)`; `duckAIListVM` for `.list(.duckAI)`/`.list(.recents)`; favorites/logo unchanged.
- [ ] **Step 2:** Apply transition policy: wrap the content switch so that transitions **into** `.favorites` or `.logo` disable the outgoing fade (`.transaction { $0.animation = nil }`), while list↔list animates with an opacity transition. Centralize as a small `contentTransition(for:)` helper.
- [ ] **Step 3: BuildProject → success.**
- [ ] **Step 4: Commit** `refactor(uti): single view renders both surfaces with content-aware transition`.

## Task 4: Build the single host in the content VC (parallel install, not yet wired to display)

**Files:** Modify `UnifiedInputContentContainerViewController.swift`

- [ ] **Step 1:** Add `installUnifiedSuggestionsHost()` that constructs both sources with their **own** `AutocompleteRequestRunner`s (lift the existing runner/loader construction from `installUnifiedSearch`/`installDuckAISuggestions`), the merged `inputsPublisher` (CombineLatest of `toggleStatePublisher`, `currentTextPublisher`, search favorites/messages signals, duck.ai recents/settle signals via the merger), favorites provider, escape hatch, and starts ONE `UIHostingController` in a single container view pinned in `contentContainerView`.
- [ ] **Step 2:** Keep the old two-host install path compiled but unused behind a private feature switch `useSingleSuggestionsHost` (default false) so we can A/B on-device without deleting the fallback yet.
- [ ] **Step 3: BuildProject → success.**
- [ ] **Step 4: Commit** `feat(uti): single suggestions host install (behind switch)`.

## Task 5: Route inset / escape-hatch / dax-visibility / teardown to the single host

**Files:** Modify `UnifiedInputContentContainerViewController.swift`

- [ ] **Step 1:** When `useSingleSuggestionsHost`, `updateEscapeHatchTopInset` and `setEscapeHatch` target the single host; `applyRequestedContentInset` sets `additionalSafeAreaInsets` on the single hosting controller's view (not the swipe container).
- [ ] **Step 2:** `updateDaxVisibility` reads `hasContent`/`hasSettled` from the single host (mode-aware) instead of the two hosts.
- [ ] **Step 3:** Lazy duck.ai: `viewWillAppear`/`viewDidDisappear` attach/detach the duck.ai source on the single host (`tearDownDuckAI`) instead of installing/destroying a separate host.
- [ ] **Step 4: BuildProject → success.** Flip `useSingleSuggestionsHost = true`.
- [ ] **Step 5: On-device verify** (Build via Xcode MCP + sim from `.sim-udid`, stream `UTITransition`): all four mode pairs (search↔duckai × blank/typing), favorites grid, recents, logo, escape hatch alignment, no recents-over-grid, hatch in lockstep, no constraint warnings in log sweep. **Checkpoint with user.**
- [ ] **Step 6: Commit** `feat(uti): drive inset/hatch/dax/lifecycle from single host`.

## Task 6: Remove the crossfade transport from the UTI path

**Files:** Modify `UnifiedInputContentContainerViewController.swift`

- [ ] **Step 1:** After user confirms Task 5 green, delete `installSwipeContainer`, the `swipeContainerManager` property, the `SwipeContainerViewControllerDelegate` + `FadeOutContainerViewControllerDelegate` conformances and their methods (`didSwipeToMode`, `didTransitionToMode`, `didUpdateScrollProgress`, `isShowingSuggestions`, `shouldKeepSearchVisible`), and the old two-host install methods + the `useSingleSuggestionsHost` switch.
- [ ] **Step 2:** Confirm `SwipeContainerManager`/`FadeOutContainerViewController`/`SwipeContainerViewController` are still referenced only by `OmniBarEditingStateViewController` (grep) — leave them intact.
- [ ] **Step 3: BuildProject → success.**
- [ ] **Step 4: On-device re-verify** the full matrix again (regression pass) + dismiss/collapse + rotation + landscape cap.
- [ ] **Step 5: Commit** `refactor(uti): remove crossfade container machinery from UTI path`.

## Task 7: Cleanup + log strip (after user confirms green)

- [ ] **Step 1:** Remove the temporary `UTITransition` debug logs added during this and the prior investigation (the `pageState`, `paged.updateScrollViewPosition`, `host.content`, verbose `applyContentInset`/`pushContentInsets` lines). Keep any that earn their place as permanent `.info`.
- [ ] **Step 2: BuildProject → success; final on-device smoke.**
- [ ] **Step 3: Commit** `chore(uti): strip transition debug logs`.

---

## Risks & mitigations

- **Mutual DDG-request cancellation (Part 2b regression):** mitigated by keeping two separate `AutocompleteRequestRunner`s/loaders — Task 4 lifts them verbatim, never shares one.
- **Duck.ai heavy/lazy lifecycle & NTP favorites init:** preserved via lazy duck.ai source attach + memoized favorites provider (Task 2/5).
- **`resultsPending`/`previous` logo-flash suppression:** preserved — merger carries `resultsPending`; resolver's `previous` handling is unchanged.
- **Escape-hatch visibility rules (only recents/favorites/logo, not while typing):** unchanged — lives in resolver/view.
- **Landscape editing-height cap + dismiss collapse:** re-verified in Task 6 Step 4 (the `editingHeight()` inset source must still collapse correctly).
- **Fallback safety:** Tasks 4–5 keep the old path behind `useSingleSuggestionsHost` so we never lose a working build mid-refactor; removal only after green.

## Verification matrix (run at Task 5 Step 5 and Task 6 Step 4)

| From → To | blank | typing |
|---|---|---|
| Search → Duck.ai | favorites→recents/logo, no overlap | search-list→duckai-list crossfade |
| Duck.ai → Search | recents/logo→favorites, recents instant-gone | duckai-list→search-list crossfade |

Plus: escape-hatch alignment in every state, hatch slides in lockstep, Dax logo morph unaffected, dismiss/collapse, rotation, landscape cap, `grep -iE 'constraint|unsupported|layout cycle'` clean.
