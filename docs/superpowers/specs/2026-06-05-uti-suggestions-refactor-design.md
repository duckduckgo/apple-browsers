# UTI Suggestions Refactor — Design Spec

**Date:** 2026-06-05
**Branch:** `jacek/refactor-uti-suggestions`
**Scope:** iOS only. Applies **exclusively** to the code path where the Unified Toggle Input (UTI) feature flag (`.unifiedToggleInput`) is ON. The flag-OFF / legacy path is untouched.

---

## 1. Problem

When UTI is ON, the swappable content region beneath the input bar is implemented as several UIKit view controllers that are installed/removed as the user switches between Search and Duck.ai modes and between "has input" and "no input" states:

- **Search + no input** → `NewTabPageViewController` (favorites/NTP), with the Dax logo shown by `DaxLogoManager` as a separate overlay.
- **Search + typing** → `AutocompleteViewController` (already SwiftUI: `AutocompleteView`) inside `SuggestionTrayViewController`.
- **Duck.ai + no input** → `DuckAISuggestionsViewController` empty state and/or `AIChatHistoryListViewController` (recents).
- **Duck.ai + typing** → `DuckAISuggestionsViewController` (filtered).

Owners: `UnifiedToggleInputCoordinator` → `UnifiedInputContentContainerViewController` → `SwipeContainerManager` + `SuggestionTrayManager` + `DuckAISuggestionsCoordinator` + `DaxLogoManager`.

This produces three concrete pains:

1. **VC install/uninstall churn** — `addChild`/`removeFromParent` coordination across surfaces.
2. **Escape-hatch drift** — the escape hatch is re-hosted and re-laid-out inside each surface's table header (`DuckAISuggestionsViewController.swift:275-310`, `AIChatHistoryListViewController.swift:257-289`) with divergent per-surface padding constants, so keeping it in the same position requires manual syncing.
3. **Dax logo handling** — logo visibility is an emergent side-effect of an eight-condition boolean in `UnifiedInputContentContainerViewController.updateDaxVisibility()` (`:665`) feeding `DaxLogoManager.shouldShowHomeDax()` (`:161`), and its position is hand-tuned via a centering layout guide plus `escapeHatchBaseOffset` + `logoYOffset` + `toolbarCompensationOffset`.

### Key observation that shapes the design

The three "typed/list" surfaces are **one list with one row type; only the data underneath changes** (sections, item counts, content). Verified in code:

| Surface | Renderer | Row shape | Extra affordances |
|---|---|---|---|
| Search suggestions | `AutocompleteView` (SwiftUI) | icon + title (query-bolded) + subtitle | tap-ahead arrow, swipe/delete, keyboard-selection highlight |
| Duck.ai suggestions | `DuckAISuggestionsViewController` (UIKit) | icon + title + subtitle | none |
| Duck.ai recents | `AIChatHistoryListViewController` (UIKit) | icon + title | none |

`SuggestionListItem` (in `AutocompleteView.swift`) is already the richest version of this row and is the natural basis for the unified row. Favorites/NTP (search-empty) is the one genuinely different layout — a grid — so it stays embedded.

---

## 2. Goal

Replace the swappable content region (and only that region — the input bar and toggle stay as UIKit, unchanged) with **one SwiftUI view fed by per-state view models**, under the existing UTI flag. Content and behavior are preserved (purely structural refactor); the win is that chrome (escape hatch, logo) and transitions are defined once, and the state that drives everything is explicit and testable.

**Out of scope:** iPad (UTI is iPhone-only — `UnifiedToggleInputFeature.isAvailable` requires `devicePlatform.isIphone`); the flag-OFF legacy path; rebuilding the favorites/NTP grid; rebuilding the legacy autocomplete (we *share* its row component, we don't replace it).

---

## 3. Architecture (Approach A — enum-driven content state + per-state view models)

### 3.1 Data model (the constant)

Pure value types, `Equatable`, no UIKit:

```swift
struct SuggestionRow: Identifiable, Equatable {
    let id: String                  // stable identity for ForEach + diffing
    let icon: Image
    let title: String
    let query: String?              // when set, prefix-bolds the matched portion
    let subtitle: String?
    let accessory: Accessory        // .none | .tapAhead | .delete
    let accessibilityID: String
    enum Accessory: Equatable { case none, tapAhead, delete }
}

struct SuggestionSection: Identifiable, Equatable {
    let id: String
    let title: String?              // section header / scrollable title; nil = none
    let rows: [SuggestionRow]
}
```

- **Pure data, no actions in the model.** Tap / tap-ahead / delete are dispatched by id (section id + row id) to the active view model. The view holds the action closures; the model holds none. Keeps the model `Equatable` and trivially testable.
- **Identity is explicit (`id`), never `.indices`.** Required for stable SwiftUI diffing and smooth row-level transitions. Removes the per-keystroke reflow workarounds in the current UIKit code.
- **Selection highlight (keyboard arrow-nav) lives in view state**, not the row — a transient UI concern kept as a separate published index so re-deriving rows doesn't churn selection.

### 3.2 State machine (the explicit logic)

```swift
enum Content: Equatable {
    case list(SuggestionsListViewModel)   // search-typing | duck.ai-typing | duck.ai-recents
    case favorites                        // search-empty WITH favorites/messages → embed NewTabPageView
    case logo                             // search-empty no favorites | duck.ai-empty no recents
}
```

Derived from one explicit input struct — no UIKit, no managers, no offsets:

```swift
struct Inputs: Equatable {
    let mode: TextEntryMode            // .search | .aiChat
    let isTyping: Bool                 // query non-empty
    let hasFavoritesOrMessages: Bool   // search empty-state content exists
    let hasRecents: Bool               // duck.ai empty-state content exists
    let resultsPending: Bool           // fetchers not settled for current query
}
```

Decision table:

| mode | typing | pending | empty-content | → content |
|---|---|---|---|---|
| search | no | — | favorites/msgs | `.favorites` |
| search | no | — | none | `.logo` |
| search | yes | — | — | `.list(search)` |
| duck.ai | no | — | has recents | `.list(recents)` |
| duck.ai | no | — | none | `.logo` |
| duck.ai | yes | yes | — | *hold previous* (no flash to `.logo`) |
| duck.ai | yes | no | — | `.list(duckAI)` |

This makes the logo a **first-class content state** (`content == .logo`), replacing `updateDaxVisibility()`'s eight-condition derivation. The `resultsPending` "hold previous" row is the anti-flash rule made explicit and unit-testable.

### 3.3 View composition

```
UnifiedSuggestionsView
└─ ZStack
   ├─ contentLayer        // switch on viewModel.content
   │    .list(vm)      → SuggestionsList(vm)          // §3.1 rows in a SwiftUI List
   │    .favorites     → NewTabPageView (embedded)
   │    .logo          → Color.clear                   // logo lives in chrome
   └─ chromeLayer
        ├─ EscapeHatchView   // single instance + single layout definition
        └─ DaxLogoView       // single instance, centered in available area, morph = mode
```

- **Escape hatch:** one reusable `EscapeHatchView` with one layout definition (insets, height, max-width, top padding). What varies by state is only its *container*: scroll-header in `.list` (scrolls away — **current behavior preserved**), fixed top element in `.logo`/`.favorites`. Deletes the three divergent `updateTableHeader()`/re-hosting implementations.
- **Transitions:** one `.animation(_:value: content.caseID)` plus per-state `.transition(...)`. Honors the documented asymmetric show/dismiss rule — content fades/slides while chrome stays put and only morphs, so we never reproduce the double-vision crossfade. Mode change animates the logo morph and the content swap independently.

### 3.4 Logo vertical centering (explicit requirement)

The logo's Y is a **derived layout result, never an offset constant.** It centers within the *available area* = the region bounded by:

- **top edge** = bottom of the UTI input bar (reactive: changes with multi-line text / attachments), and
- **bottom edge** = top of the keyboard (reactive: changes when the keyboard shows/hides/resizes).

The logo is laid out to fill that region and center within it (region with `maxHeight: .infinity`, logo centered), so it re-centers automatically when either edge moves. This retires `escapeHatchBaseOffset`, `logoYOffset`, and `toolbarCompensationOffset`.

**Positioning ownership moves into the unified view's layout now** (this refactor). Only the Lottie morph *internals* remain in `DaxLogoManager` until deferred follow-up #5 (see §6). The unified view consumes the input bar's height as a published reactive input (the coordinator already knows it) and applies it as the region's top inset; it no longer relies on `DaxLogoManager`'s centering guide.

---

## 4. Structural improvements adopted

1. **One async query pipeline (replaces the timing hacks).** Today Duck.ai suggestions run two independent Combine debounces (chats 150ms, urls 100ms) merged by an 80ms coalesce window plus `removeDuplicates` plus a `hasSettled(forQuery:)` guess (`DuckAISuggestionsViewController.swift:94-97`). Replace with one pipeline per query: debounce the query once → fetch both sources concurrently (`async let`) → emit a single settled snapshot. "Pending vs settled" becomes a real returned state (= the `resultsPending` input), not a timing guess. Inject the clock/scheduler so debounce is deterministic in tests (no `sleep`).
2. **SwiftUI `List` over identified data.** Removes the stale-index-path defensive scaffolding (`liveSections` "MUST stay computed", `resolvedSection(at:)` returning nil, `guard indexPath.row < count`) that exists only because `UITableViewDataSource` is queried with stale paths mid-animation. With `ForEach` over `Identifiable`, index paths don't exist; row-level insert/remove animate for free.
3. **Split pure decision from VM lifecycle.** `ContentResolver`: `(Inputs) -> ContentKind`, pure, no references, no UIKit — exhaustively unit-tested with zero mocks. A small VM factory/cache vends-or-reuses the list VM for a kind.
4. **One upstream input source.** The aggregator subscribes to one `@Published var inputs: Inputs` published by the coordinator (the single authority), instead of fanning into `suggestionTrayManager`, `duckAISuggestionsCoordinator`, `switchBarHandler`, escape-hatch state, and layout size.
6. **Share the single recents view model.** `AIChatSuggestionsViewModel.filteredSuggestions` feeds both the recents list and the Duck.ai-typing "chats" section. Both `SuggestionsSource`s read one shared instance — no duplicate fetches/subscriptions.

(Improvement #5 — declarative Lottie morph — is **deferred**; see §6.)

### Concurrency notes (for improvement #1)
- Prefer structured concurrency: `async let chats / async let urls` then await both, over two unstructured Combine streams.
- Inject the scheduler/clock; tests assert on settled snapshots, never on wall-clock timing.
- `@MainActor` for the view models that publish to SwiftUI; the fetch work hops off and results are delivered back on the main actor.

---

## 5. Migration increments (bottom-up; each builds, runs, stays under the existing UTI flag)

The user verifies each increment on-device against a second simulator running the prior build to pinpoint any visual differences.

1. **Data model + row component** — `SuggestionRow`/`SuggestionSection` + the unified SwiftUI row (extracted from / shared with `SuggestionListItem`). Pure, unwired. *Tests:* row renders each variant.
2. **`ContentResolver`** — pure `Inputs → ContentKind` decision table. *Tests:* exhaustive incl. `resultsPending` "hold previous".
3. **Async query pipeline** with injected clock. *Tests:* deterministic debounce + concurrent fetch + settled snapshot.
4. **`SuggestionsListViewModel` + the three `SuggestionsSource`s** producing `[SuggestionSection]` (sharing one recents VM). *Tests:* each source's mapping.
5. **`UnifiedSuggestionsView`** assembling content + chrome. **First visible swap:** replace Duck.ai suggestions (`DuckAISuggestionsViewController`) — UTI-only, lowest risk. User tests Duck.ai typing end-to-end.
6. **Swap Duck.ai recents** → unified `.list`. User tests recents incl. empty→`.logo`.
7. **Swap search-typing** → unified `.list` (reusing the shared row; legacy autocomplete untouched for iPad/non-UTI). User tests search suggestions.
8. **Wire `.favorites` + `.logo`** explicitly via the resolver; retire `updateDaxVisibility()`'s logo derivation on the UTI path; move logo positioning into the unified view's layout (§3.4). User tests empty states + logo centering across keyboard / input-height changes.
9. **Cleanup** — remove dead UTI-only swapping code (`SwipeContainerManager` content paths, retired VCs) once unreferenced.

### Testing philosophy
Heavy unit coverage on the pure units (resolver table, source mappings, pipeline settling) where ordering/timing bugs hide. No trivial-getter tests. UI/transition correctness verified on-device per increment.

---

## 6. Deferred follow-up (recorded in `.pr-followups.md`)

**Declarative Lottie dax/duck.ai logo morph.** Replace `DaxLogoManager.updateState()`'s 7-branch if/else ladder (scrubbing Lottie progress against swipe progress + `isAnimatingLogoTransition` + UUID `pendingTransitionToken`, `DaxLogoManager.swift:322-363, 131-156`) with a `UIViewRepresentable` wrapping `AnimatedDaxLogoView` whose only inputs are `targetProgress` (= mode) and `isInteractive` (swipe). Deferred because interactive-swipe + morph timing is high-risk; do it only after the unified view is stable. The initial refactor keeps `DaxLogoManager` driving the logo's morph internals unchanged (but its *positioning* moves into the unified view per §3.4).

---

## 7. Risks

- **Search-suggestion parity:** the unified `.list` for search-typing must match legacy autocomplete behavior (query bolding, tap-ahead, swipe-delete, keyboard selection). Mitigated by sharing the `SuggestionListItem` row component rather than reimplementing it.
- **Anti-flash regression:** the `resultsPending` rule must be exact; this is the area that previously broke the dax logo when fixing a text-entry flash. Covered by the resolver decision-table tests.
- **Embedded NTP:** `NewTabPageView` is shared with the non-UTI/iPad path; embedding it must not mutate its shared configuration.
