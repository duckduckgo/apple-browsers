# UTI Suggestions Refactor — Part 2b: Search Unification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Render the UTI Search surface (autocomplete suggestions **and** the favorites/NTP empty state) through the *same* `UnifiedSuggestionsView` used by Duck.ai — driven by the Part 1 `UnifiedSuggestionsContentResolver` — so toggling Search↔Duck.ai is genuinely one view with a different model. Generalize the Duck.ai host into one reusable host, and route keyboard arrow-nav into the unified list.

**Architecture (decided with the user):**
- **One view, different models.** `UnifiedSuggestionsView` becomes a thin **resolver-driven parent** that switches on `UnifiedSuggestionsContentKind`:
  - `.list(listVM)` → `SuggestionsListView` (today's rows view, renamed) — fed by `DuckAISuggestionsSource` *or* the new `SearchSuggestionsSource`
  - `.favorites` → `FavoritesView` (wraps the existing `NewTabPageViewController`)
  - `.logo` → `EmptyView` for now (the existing `DaxLogoManager` keeps drawing the logo; moving it into the view is **Part 2c**)
- **One adapter.** Generalize `UnifiedDuckAISuggestionsHost` → **`UnifiedSuggestionsHost`**, parameterized by a small config (source, supported content, delegate, favorites builder). Retrofit the Duck.ai path onto it.
- **Aggregator.** A `UnifiedSuggestionsViewModel` assembles `UnifiedSuggestionsInputs` (mode, isTyping, hasFavorites, hasMessages, hasRecents, resultsPending) and publishes the resolver's `content`, which drives the parent view.
- Search install mirrors Duck.ai: the host installs the one view into `swipeContainerManager.searchPageContainer`, **bypassing `SuggestionTrayManager` for the UTI path only** (the shared tray stays intact for non-UTI/iPad).

**Out of scope (Part 2c):** logo reposition into the unified layout + retiring `updateDaxVisibility()`/`toolbarCompensationOffset`; deleting `DuckAISuggestionsViewController`/`DuckAISuggestionsCoordinator`/dead `SwipeContainerManager` paths; top-gap parity; Duck.ai delete pixel. Out of scope entirely: declarative Lottie (#5).

**Tech Stack:** SwiftUI, Combine, `UIHostingController`/`UIViewControllerRepresentable`, XCTest. Reuses Part 1 (`SuggestionRow(Mapper)`, `UnifiedSuggestionsContentResolver`, `SuggestionsListViewModel`) and Part 2a (`UnifiedSuggestionsView`→`SuggestionsListView`, the host, `DuckAISuggestionsSource`).

**Conventions:** New files via `mcp__xcode__XcodeWrite`; build/test via `mcp__xcode__BuildProject`/`GetTestList`/`RunSomeTests`, tab `windowtab1`, target `UnitTests`; never `xcodebuild`; never hand-edit `project.pbxproj`; never the word "track"; ignore SourceKit live diagnostics (trust `BuildProject`); revert `Package.resolved` if auto-touched; short commits, no Co-Authored-By. **When the plan references a member it could not fully verify, the step says VERIFY — confirm against the real source and report `NEEDS_CONTEXT` rather than inventing.**

---

## File Structure

**Renamed:** `UnifiedSuggestionsView.swift` → `SuggestionsListView.swift` (struct `UnifiedSuggestionsView` → `SuggestionsListView`).

**New product files** (`DuckDuckGo/UnifiedToggleInput/Suggestions/`):
- `UnifiedSuggestionsView.swift` — the resolver-driven parent (switches list/favorites/logo).
- `UnifiedSuggestionsViewModel.swift` — the aggregator (Inputs → resolver → `content`; owns the active list VM).
- `SearchSuggestionsLoader.swift` — drives `SuggestionLoader` + `AutocompleteSuggestionsDataSource` for Search (mirrors `DuckAIURLSuggestionsLoader`, but full categorized results).
- `SearchSuggestionsSource.swift` — maps Search results → `[SuggestionSection]` (topHits/ddg/local/askAIChat + empty→phrase fallback).
- `FavoritesView.swift` — `UIViewControllerRepresentable` wrapping a `NewTabPageViewController`.
- `UnifiedSuggestionsHostConfig.swift` — the per-surface config struct.

**Modified:**
- `UnifiedDuckAISuggestionsHost.swift` → generalized to `UnifiedSuggestionsHost.swift` (config-driven); Duck.ai call site updated.
- `UnifiedInputContentContainerViewController.swift` — install Search via the host; assemble the aggregator; route keyboard nav.
- `MainViewController+KeyCommands.swift` (or the UTI key path) — route arrow keys to the unified list selection when UTI search is active.

**New test files:** `SearchSuggestionsSourceTests.swift`, `UnifiedSuggestionsViewModelTests.swift`.

---

## Task 1: Rename the rows view to `SuggestionsListView`

**Files:** rename `UnifiedSuggestionsView.swift` → `SuggestionsListView.swift`; update the one reference in the host.

- [ ] **Step 1:** `mcp__xcode__XcodeMV` (or XcodeRM old + XcodeWrite new) to rename the file to `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsListView.swift`, renaming `struct UnifiedSuggestionsView` → `struct SuggestionsListView` (body unchanged). Keep `isAddressBarAtBottom`, `header`, `viewModel`.
- [ ] **Step 2:** In `UnifiedDuckAISuggestionsHost.swift`, change `UIHostingController<UnifiedSuggestionsView>` and the `UnifiedSuggestionsView(...)` construction to `SuggestionsListView`. (This is temporary — Task 6 replaces the host's body with the parent view; for now keep it compiling.)
- [ ] **Step 3:** `BuildProject` → success. Run `SuggestionsListViewModelTests`, `DuckAISuggestionsSelectionTests` → still pass.
- [ ] **Step 4:** Commit: `Rename UnifiedSuggestionsView to SuggestionsListView`.

---

## Task 2: `SearchSuggestionsLoader`

Drives `SuggestionLoader` for Search (full results), debounced, with an injected scheduler for testable timing. Mirrors `DuckAIURLSuggestionsLoader` but keeps all categories (not URL-only).

**Files:** Create `DuckDuckGo/UnifiedToggleInput/Suggestions/SearchSuggestionsLoader.swift`.

- [ ] **Step 1: VERIFY the building blocks** before writing. Read `AutocompleteViewController.swift:225-260` (`requestSuggestions`) and `:68-79` (the `AutocompleteSuggestionsDataSource` build) and `DuckAIURLSuggestionsLoader.swift`. Confirm: `SuggestionLoader(shouldLoadSuggestionsForUserInput:isUrlIgnored:)` init, `getSuggestions(query:usingDataSource:completion:)` signature, and `SuggestionResult` shape (`topHits`, `duckduckgoSuggestions`, `localSuggestions`). If any differ, report `NEEDS_CONTEXT`.

- [ ] **Step 2: Write the loader** (publishes the latest `SuggestionResult` + last-completed query):

```swift
//
//  SearchSuggestionsLoader.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import Suggestions

/// Drives `SuggestionLoader` for the Search surface and publishes the latest result.
/// Mirrors `DuckAIURLSuggestionsLoader` but keeps all suggestion categories.
@MainActor
final class SearchSuggestionsLoader {

    @Published private(set) var result: SuggestionResult = .empty
    private(set) var lastCompletedFetchQuery: String?

    private let dataSource: SuggestionLoadingDataSource
    private var loader: SuggestionLoader?
    private var latestDispatchedQuery: String?
    private var cancellables = Set<AnyCancellable>()

    init(dataSource: SuggestionLoadingDataSource) {
        self.dataSource = dataSource
    }

    func subscribeToTextChanges<P: Publisher>(_ textPublisher: P)
        where P.Output == String, P.Failure == Never {
        textPublisher
            .debounce(for: .milliseconds(DuckAIURLSuggestionsLoader.debounceMilliseconds), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in self?.fetch(query: text) }
            .store(in: &cancellables)
    }

    func fetch(query: String) {
        latestDispatchedQuery = query
        guard !query.isEmpty else {
            if result != .empty { result = .empty }
            lastCompletedFetchQuery = query
            return
        }
        loader = SuggestionLoader(shouldLoadSuggestionsForUserInput: { _ in true }, isUrlIgnored: { _ in false })
        loader?.getSuggestions(query: query, usingDataSource: dataSource) { [weak self] result, _ in
            guard let self, self.latestDispatchedQuery == query else { return }
            self.lastCompletedFetchQuery = query
            self.result = result ?? .empty
        }
    }

    func tearDown() { cancellables.removeAll() }
}

extension SuggestionResult {
    static let empty = SuggestionResult(topHits: [], duckduckgoSuggestions: [], localSuggestions: [])
}
```

> VERIFY: `DuckAIURLSuggestionsLoader.debounceMilliseconds` is `private static` (seen in Part 1 spike). If not accessible, inline the literal `100` with a comment. `SuggestionResult.empty` may already exist (it's declared `fileprivate`/`private` in `AutocompleteViewController.swift`); if a public/internal one exists, drop this extension — if it collides, name ours differently. Report which.

- [ ] **Step 3:** `BuildProject`. Commit: `Add SearchSuggestionsLoader`.

---

## Task 3: `SearchSuggestionsSource` (+ tests)

Maps the loader's `SuggestionResult` → `[SuggestionSection]`, porting `AutocompleteViewModel.updateSuggestions` semantics (4 categories, empty→phrase fallback, askAIChat row). Delete accessory **on** for Search history rows. Resolves rowID→Suggestion for selection (like `DuckAISuggestionsSource`).

**Files:** Create `SearchSuggestionsSource.swift`; Test `SearchSuggestionsSourceTests.swift`.

- [ ] **Step 1: Write failing tests:**

```swift
//
//  SearchSuggestionsSourceTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class SearchSuggestionsSourceTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    override func tearDown() { cancellables.removeAll(); super.tearDown() }

    private func source(result: SuggestionResult, query: String, showAskAIChat: Bool = false) -> SearchSuggestionsSource {
        let subject = CurrentValueSubject<SuggestionResult, Never>(result)
        let src = SearchSuggestionsSource(resultPublisher: subject.eraseToAnyPublisher(),
                                          query: { query },
                                          showAskAIChat: showAskAIChat)
        src.sectionsPublisher.sink { _ in }.store(in: &cancellables)
        return src
    }

    func test_categoriesBecomeSectionsInOrder() {
        let r = SuggestionResult(topHits: [.website(url: URL(string: "https://a.com")!)],
                                 duckduckgoSuggestions: [.phrase(phrase: "cats")],
                                 localSuggestions: [.bookmark(title: "B", url: URL(string: "https://b.com")!, isFavorite: false, score: 0)])
        var sections: [SuggestionSection] = []
        source(result: r, query: "ca").sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)
        XCTAssertEqual(sections.map(\.id), ["topHits", "ddg", "local"])
    }

    func test_askAIChatSection_whenEnabled_withQuery() {
        var sections: [SuggestionSection] = []
        source(result: .empty, query: "weather", showAskAIChat: true).sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)
        XCTAssertTrue(sections.contains { $0.id == "askAIChat" })
    }

    func test_historyRow_hasDeleteAccessory() {
        let url = URL(string: "https://h.com")!
        let r = SuggestionResult(topHits: [.historyEntry(title: "H", url: url, score: 0)],
                                 duckduckgoSuggestions: [], localSuggestions: [])
        var sections: [SuggestionSection] = []
        source(result: r, query: "h").sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)
        XCTAssertEqual(sections.first?.rows.first?.accessory, .delete)
    }

    func test_resolvesRowIDToSuggestion() {
        let url = URL(string: "https://a.com")!
        let s = Suggestion.website(url: url)
        let src = source(result: SuggestionResult(topHits: [s], duckduckgoSuggestions: [], localSuggestions: []), query: "a")
        XCTAssertEqual(src.suggestion(forRowID: "topHits-website-\(url.absoluteString)"), s)
    }
}
```

> VERIFY: `SuggestionResult(topHits:duckduckgoSuggestions:localSuggestions:)` is the real initializer (seen in `AutocompleteViewController`'s `.empty`). Confirm and adjust the test inits if the labels differ.

- [ ] **Step 2: Run** → fails to compile.

- [ ] **Step 3: Write the source** (port `AutocompleteViewModel.updateSuggestions` mapping; section id = idPrefix):

```swift
//
//  SearchSuggestionsSource.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import Suggestions

/// Search-typing source: maps `SuggestionResult` categories to unified sections,
/// porting `AutocompleteViewModel.updateSuggestions` semantics. History rows expose delete.
@MainActor
final class SearchSuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    private let query: () -> String
    private let resultBox = ResultBox()

    init(resultPublisher: AnyPublisher<SuggestionResult, Never>,
         query: @escaping () -> String,
         showAskAIChat: Bool) {
        self.query = query
        let box = resultBox
        sectionsPublisher = resultPublisher
            .map { result in
                box.value = result
                let q = query()
                var sections: [SuggestionSection] = []

                func section(_ id: String, _ suggestions: [Suggestion]) {
                    guard !suggestions.isEmpty else { return }
                    sections.append(SuggestionSection(
                        id: id,
                        rows: suggestions.map { SuggestionRowMapper.row(for: $0, query: q, idPrefix: id, includesDeleteAccessory: true) }))
                }

                var topHits = result.topHits
                // Empty → single non-tap-ahead phrase fallback (mirrors AutocompleteViewModel).
                if topHits.isEmpty && result.duckduckgoSuggestions.isEmpty && result.localSuggestions.isEmpty && !q.isEmpty {
                    topHits = [.phrase(phrase: q)]
                }
                section("topHits", topHits)
                section("ddg", result.duckduckgoSuggestions)
                section("local", result.localSuggestions)
                if showAskAIChat, !q.isEmpty {
                    section("askAIChat", [.askAIChat(value: q)])
                }
                return sections
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Resolves a row id back to its `Suggestion` (across all categories).
    func suggestion(forRowID id: String) -> Suggestion? {
        let r = resultBox.value
        let all = r.topHits + r.duckduckgoSuggestions + r.localSuggestions
        let q = query()
        for prefix in ["topHits", "ddg", "local"] {
            if let match = all.first(where: { SuggestionRowMapper.row(for: $0, query: q, idPrefix: prefix, includesDeleteAccessory: true).id == id }) {
                return match
            }
        }
        if id == "askAIChat-askAIChat-\(q)" { return .askAIChat(value: q) }
        return nil
    }
}

private final class ResultBox {
    var value: SuggestionResult = .empty
}
```

> VERIFY: the empty→phrase fallback and askAIChat behavior match `AutocompleteViewModel.updateSuggestions` (spike quoted it). Keep parity. The `.phrase` fallback row uses the mapper's `.tapAhead` accessory by default — but the legacy fallback sets `canShowTapAhead: false`. If tap-ahead on the fallback row looks wrong on-device, add a mapper flag to suppress it (Task note, not now).

- [ ] **Step 4: Run** `SearchSuggestionsSourceTests` → pass. Commit: `Add SearchSuggestionsSource with category mapping + tests`.

---

## Task 4: `UnifiedSuggestionsViewModel` (aggregator) (+ tests)

Assembles `UnifiedSuggestionsInputs`, runs the Part 1 resolver, publishes `content`, and vends the active list VM. One per surface; `mode` is fixed per page (search page = `.search`, chat page = `.aiChat`).

**Files:** Create `UnifiedSuggestionsViewModel.swift`; Test `UnifiedSuggestionsViewModelTests.swift`.

- [ ] **Step 1: Write failing tests** (the resolver is already unit-tested; here we test the aggregator publishes the resolved content from injected input publishers):

```swift
//
//  UnifiedSuggestionsViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedSuggestionsViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    override func tearDown() { cancellables.removeAll(); super.tearDown() }

    func test_searchEmptyWithFavorites_publishesFavorites() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .favorites)
    }

    func test_searchTyping_publishesList() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .search, isTyping: true, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .list(.search))
    }
}

private final class EmptySuggestionsSource: SuggestionsSource {
    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never> = Just([]).eraseToAnyPublisher()
}
```

- [ ] **Step 2: Run** → fails.

- [ ] **Step 3: Write the aggregator:**

```swift
//
//  UnifiedSuggestionsViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import Foundation

/// Aggregates input facts, runs `UnifiedSuggestionsContentResolver`, and publishes the
/// presentation `content` for `UnifiedSuggestionsView`. Holds the active list view model.
@MainActor
final class UnifiedSuggestionsViewModel: ObservableObject {

    @Published private(set) var content: UnifiedSuggestionsContentKind = .logo
    let listViewModel: SuggestionsListViewModel

    private var cancellable: AnyCancellable?

    init(inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>,
         listViewModel: SuggestionsListViewModel) {
        self.listViewModel = listViewModel
        cancellable = inputsPublisher
            .sink { [weak self] inputs in
                guard let self else { return }
                self.content = UnifiedSuggestionsContentResolver.resolve(inputs, previous: self.content)
            }
    }
}
```

- [ ] **Step 4: Run** `UnifiedSuggestionsViewModelTests` → pass. Commit: `Add UnifiedSuggestionsViewModel aggregator + tests`.

---

## Task 5: `FavoritesView`

A `UIViewControllerRepresentable` wrapping a `NewTabPageViewController` the host builds (don't reconstruct NTP's internal models — pass the VC in).

**Files:** Create `FavoritesView.swift`.

- [ ] **Step 1: VERIFY** how `SuggestionTrayViewController.installNewTabPage()` builds `NewTabPageViewController` (spike quoted it, `:380-416`) and that `newTabPageDependencies` is reachable from the container/host. The host will build the VC; `FavoritesView` just hosts it.

- [ ] **Step 2: Write the representable:**

```swift
//
//  FavoritesView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import SwiftUI
import UIKit

/// Hosts an already-built `NewTabPageViewController` (favorites/NTP) inside the unified view's
/// `.favorites` state. The controller is constructed by the host with full NTP dependencies.
struct FavoritesView: UIViewControllerRepresentable {
    let controller: NewTabPageViewController

    func makeUIViewController(context: Context) -> NewTabPageViewController { controller }
    func updateUIViewController(_ uiViewController: NewTabPageViewController, context: Context) {}
}
```

> VERIFY: `NewTabPageViewController` is a `UIHostingController<NewTabPageView>` (confirmed in spike). Hosting a hosting-controller via a representable is fine. If child-VC containment warnings appear, the host may instead add it as a child VC directly in the `.favorites` branch — but try the representable first (simplest).

- [ ] **Step 3:** `BuildProject`. Commit: `Add FavoritesView wrapping NewTabPageViewController`.

---

## Task 6: New `UnifiedSuggestionsView` parent (resolver-driven switch)

**Files:** Create `UnifiedSuggestionsView.swift` (the parent).

- [ ] **Step 1: Write the parent view:**

```swift
//
//  UnifiedSuggestionsView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import SwiftUI

/// The single unified suggestions surface for both Search and Duck.ai. Switches on the
/// resolver's content state: list rows / favorites / logo. One view, model decides the rest.
struct UnifiedSuggestionsView: View {

    @ObservedObject var viewModel: UnifiedSuggestionsViewModel
    let isAddressBarAtBottom: Bool
    let header: AnyView?
    /// Built lazily by the host for the `.favorites` state; nil when favorites aren't supported (Duck.ai).
    let favoritesProvider: () -> NewTabPageViewController?

    var body: some View {
        switch viewModel.content {
        case .list:
            SuggestionsListView(viewModel: viewModel.listViewModel,
                                isAddressBarAtBottom: isAddressBarAtBottom,
                                header: header)
        case .favorites:
            if let controller = favoritesProvider() {
                FavoritesView(controller: controller)
            } else {
                Color.clear
            }
        case .logo:
            // Part 2c moves the logo into the view; for now DaxLogoManager keeps drawing it.
            Color.clear
        }
    }
}
```

- [ ] **Step 2:** `BuildProject`. Commit: `Add resolver-driven UnifiedSuggestionsView parent`.

---

## Task 7: Generalize the host → `UnifiedSuggestionsHost` + config; retrofit Duck.ai

**Files:** Create `UnifiedSuggestionsHostConfig.swift`; rename/rewrite `UnifiedDuckAISuggestionsHost.swift` → `UnifiedSuggestionsHost.swift`; update the Duck.ai install site.

- [ ] **Step 1: Config struct:**

```swift
//
//  UnifiedSuggestionsHostConfig.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import UIKit

/// Per-surface configuration for `UnifiedSuggestionsHost`.
@MainActor
struct UnifiedSuggestionsHostConfig {
    let source: SuggestionsSource
    let inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>
    let isAddressBarAtBottom: Bool
    /// Builds the favorites controller on demand; nil for surfaces without a favorites state (Duck.ai).
    let favoritesProvider: () -> NewTabPageViewController?
    let onSelectRow: (String) -> Void
    let onDeleteRow: (String) -> Void
    let onTapAheadRow: (String) -> Void
    /// Imperative facts the container reads for Dax visibility.
    let hasContent: () -> Bool
    let hasSettled: (String) -> Bool
    let onStart: () -> Void
    let onTearDown: () -> Void
}
```

> Note: `import Combine` needed for `AnyPublisher`. Add it.

- [ ] **Step 2: Rewrite the host** generically. It builds `SuggestionsListViewModel(source:)`, `UnifiedSuggestionsViewModel(inputsPublisher:listViewModel:)`, hosts `UnifiedSuggestionsView`, wires list-VM callbacks to the config closures, and exposes `hasContent`/`hasSettled`/`setEscapeHatch`/`setAdditionalTopInset`/`tearDown` (delegating to config). Keep the **definite-height `keyboardLayoutGuide` bottom constraint** from 2a. Header (escape hatch) handling stays. Provide `start(in:parentViewController:textPublisher:)` calling `config.onStart()` (which wires the source's loaders to the text publisher).

  Because the host body is substantial and mirrors 2a's host structure, the implementer writes it modeled on the current `UnifiedDuckAISuggestionsHost`, replacing the Duck.ai-specific bits with `config` calls. **VERIFY**: every container-facing method the container currently calls on the host (`hasContent`, `hasSettled(forQuery:)`, `setEscapeHatch`, `setAdditionalTopInset`, `setIsVisibleContent`, `tearDown`, `delegate`) is preserved with identical signatures.

- [ ] **Step 3: Build a Duck.ai config** at the Duck.ai install site (`UnifiedInputContentContainerViewController.installDuckAISuggestions`) that reproduces today's behavior: source = `DuckAISuggestionsSource` over the pipeline; `inputsPublisher` = a Duck.ai inputs stream (mode `.aiChat`, isTyping from text, hasRecents from `chatViewModel.$filteredSuggestions`, resultsPending from `hasSettled`); `favoritesProvider` = `{ nil }`; selection/delete/tap-ahead = the current `handleSelect`/`handleDelete` routing; `hasContent`/`hasSettled` = current closures. Duck.ai content will only ever resolve to `.list` or `.logo` (no favorites), so behavior is unchanged.

- [ ] **Step 4:** `BuildProject`; run all suggestions unit suites + `UnifiedToggleInputCoordinatorTests`. **On-device checkpoint A:** install/launch, verify Duck.ai still behaves exactly as end-of-2a (regression guard for the generalization). Commit: `Generalize UnifiedSuggestionsHost (config-driven) and retrofit Duck.ai`.

---

## Task 8: Install Search via the host (bypass `SuggestionTrayManager` for UTI)

**Files:** `UnifiedInputContentContainerViewController.swift`.

- [ ] **Step 1: VERIFY** `installSuggestionsTray()` (`:442-458`) and the `suggestionTrayDependencies` shape (`historyManager`, `bookmarksDatabase`, `featureFlagger`, `tabsModelProvider`, `appSettings`, `aiChatSettings`, `newTabPageDependencies`, etc.). Confirm `searchPageContainer`/`containerViewController` accessibility.

- [ ] **Step 2: Add `installUnifiedSearch()`** that builds, for the search page:
  - `dataSource = AutocompleteSuggestionsDataSource(historyManager:bookmarksDatabase:featureFlagger:tabsModel:) { ... }` (same as Duck.ai's URL fetcher build).
  - `loader = SearchSuggestionsLoader(dataSource: dataSource)`.
  - `source = SearchSuggestionsSource(resultPublisher: loader.$result.eraseToAnyPublisher(), query: { [weak self] in self?.switchBarHandler.currentText ?? "" }, showAskAIChat: aiChatSettings.isAIChatEnabled)`.
  - `inputsPublisher` = search inputs stream: mode `.search`; isTyping from `currentTextPublisher`; hasFavorites/hasMessages from a small publisher backed by `newTabPageDependencies`/favorites model (VERIFY the cleanest source — the spike notes `SuggestionTrayViewController.hasFavorites`/`hasRemoteMessages`; since we bypass the tray, read favorites count from `newTabPageDependencies.favoritesModel` and remote messages from `homePageMessagesConfiguration`). resultsPending = false for search (the list shows immediately; no anti-flash needed on search side) **unless** parity testing shows otherwise.
  - `favoritesProvider` = `{ [weak self] in self?.makeSearchFavoritesController() }` building a `NewTabPageViewController` exactly as `SuggestionTrayViewController.installNewTabPage()` does.
  - selection/delete/tap-ahead → route to the same actions the autocomplete delegate used: `autocomplete(selectedSuggestion:)`, history delete via `historyManager.deleteHistoryForURL`, tap-ahead via `autocomplete(pressedPlusButtonForSuggestion:)`/`onTapAhead`. **VERIFY** the exact MainViewController delegate methods the UTI search path should call (the container already routes Duck.ai selections to its delegate; find the analogous search-submit path).
  - Install the host into `swipeContainerManager.searchPageContainer`; **do not** also install `SuggestionTrayManager` for the UTI path (gate `installSuggestionsTray()` off when UTI is on, or replace its call with `installUnifiedSearch()`).

- [ ] **Step 3:** `BuildProject`; unit suites green. Commit: `Install UTI Search via unified host`.

- [ ] **Step 4: On-device checkpoint B (controller-driven, with user):** Search mode — empty shows favorites/NTP; typing shows topHits/ddg/local(/askAIChat) sections with correct rows, icons, query-bolding; tapping a row searches/navigates; history delete works; tap-ahead fills the field. Toggle Search↔Duck.ai repeatedly — one view, correct content each side, smooth. Compare against a second sim on the pre-2b build; scan logs for constraint warnings.

---

## Task 9: Keyboard arrow-nav into the unified list

**Files:** the UTI key-command path (VERIFY: `MainViewController+KeyCommands.swift` + how it reaches the UTI surface vs the legacy `suggestionTrayController`).

- [ ] **Step 1: VERIFY** the chain (spike quoted it): arrow keys → `keyboardMoveSelectionUp/Down` → `suggestionTrayController?.keyboardMove…` → `AutocompleteViewController.model.nextSelection()/previousSelection()`. For UTI, the unified host must receive these instead.

- [ ] **Step 2:** Add `moveSelectionUp()/moveSelectionDown()/commitSelection()` to `SuggestionsListViewModel` (drives `selectedRowID` across the current flattened `sections`), and expose them on the host. Route the UTI key commands to the active host's list VM when UTI is active.

```swift
// SuggestionsListViewModel additions
func moveSelectionDown() { moveSelection(by: +1) }
func moveSelectionUp() { moveSelection(by: -1) }

private func moveSelection(by delta: Int) {
    let ids = sections.flatMap { $0.rows.map(\.id) }
    guard !ids.isEmpty else { selectedRowID = nil; return }
    guard let current = selectedRowID, let idx = ids.firstIndex(of: current) else {
        selectedRowID = delta > 0 ? ids.first : ids.last
        return
    }
    let next = idx + delta
    if ids.indices.contains(next) { selectedRowID = ids[next] }
}

func commitSelection() { if let id = selectedRowID { onSelect?(id) } }
```

`SuggestionsListView` already (Task 1) should highlight `selectedRowID` via `.listRowBackground` — VERIFY/add: `.listRowBackground(row.id == viewModel.selectedRowID ? Color(designSystemColor: .accent) : Color(designSystemColor: .surface))`.

- [ ] **Step 3:** `BuildProject`; add a small unit test for `moveSelection` wrap/bounds; run. **On-device checkpoint C:** with a hardware keyboard (or sim Cmd-K toggle), arrow keys move the highlight and Return commits, on both Search and Duck.ai. Commit: `Route keyboard arrow-nav into unified suggestions list`.

---

## Part 2b completion

- [ ] All unit suites green; on-device: Search + Duck.ai both render through the one `UnifiedSuggestionsView`, favorites/list/logo correct per state, keyboard nav works, no constraint warnings.
- [ ] Update `.pr-followups.md`: confirm logo still drawn by `DaxLogoManager` (2c will move it); note any residual top-gap.
- [ ] Hand off to **Part 2c**: move the logo into the unified view's layout (retire `updateDaxVisibility()` logo derivation + `toolbarCompensationOffset`), delete `DuckAISuggestionsViewController`/`DuckAISuggestionsCoordinator`/dead `SwipeContainerManager` paths, top-gap parity, Duck.ai delete pixel. Then the deferred Lottie (#5).
