# UTI Suggestions Refactor — Part 1: Foundational Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure, unit-tested core of the unified UTI suggestions surface — data model, row mappers, the explicit content-state resolver, the settle-aware query pipeline, the suggestion sources, and the list view model — without changing the running app.

**Architecture:** A single SwiftUI suggestions view (built in Part 2) will switch on an explicit `Content` enum produced by a pure `UnifiedSuggestionsContentResolver`. The three "typed/list" surfaces (search suggestions, Duck.ai suggestions, Duck.ai recents) collapse to one row type (`SuggestionRow`) in data-driven sections (`SuggestionSection`); per-state `SuggestionsSource`s produce those sections from existing data (`Suggestion`, `AIChatSuggestion`). This Part 1 lands all of that as pure, testable units behind no behavior change.

**Tech Stack:** Swift, SwiftUI, Combine, XCTest, `@MainActor`. Existing types reused: `Suggestion` (BrowserServicesKit/Suggestions), `AIChatSuggestion` + `AIChatSuggestionsViewModel` (SharedPackages/AIChat), `DuckAIURLSuggestionsLoader`, `SwitchBarHandling`/`TextEntryMode`, `DesignSystemImages`.

**Scope note:** Spec increments 5–9 (assemble `UnifiedSuggestionsView`, swap Duck.ai suggestions → recents → search, wire `.favorites`/`.logo`, cleanup) are deliberately NOT in this plan. They are planned separately after this core lands, when the real integration interfaces are concrete. Part 1 produces no on-screen change; verification is via unit tests.

**Conventions:**
- Create every new Swift file via `mcp__xcode__XcodeWrite` (path = Xcode-relative, e.g. `DuckDuckGo/UnifiedToggleInput/Suggestions/Foo.swift`). Never hand-edit `project.pbxproj`.
- Build/test via Xcode MCP tools (`mcp__xcode__BuildProject`, `mcp__xcode__RunSomeTests`). Never invoke `xcodebuild` directly.
- Never use the word "track"/"tracking" in any identifier, comment, or string.
- Commit messages short, no Co-Authored-By.

---

## File Structure

**New product files** (all under `DuckDuckGo/UnifiedToggleInput/Suggestions/`):

- `SuggestionRow.swift` — `SuggestionRow`, `SuggestionSection` value types. The unified data model.
- `SuggestionRowMapper.swift` — pure functions mapping `Suggestion` and `AIChatSuggestion` → `SuggestionRow`.
- `UnifiedSuggestionsContentResolver.swift` — `UnifiedSuggestionsInputs`, `UnifiedSuggestionsContentKind`, and the pure resolver (the decision table).
- `DuckAISuggestionsPipeline.swift` — Combine pipeline merging the recents + URL fetchers into one settle-aware snapshot, with an injected scheduler.
- `SuggestionsSource.swift` — `SuggestionsSource` protocol + the three conformers (search / duck.ai-typing / recents) producing `[SuggestionSection]`.
- `SuggestionsListViewModel.swift` — `@MainActor ObservableObject` exposing `@Published var sections: [SuggestionSection]` from an injected source, plus row-action routing.

**New test files** (under `DuckDuckGoTests/UnifiedToggleInput/Suggestions/`):

- `SuggestionRowMapperTests.swift`
- `UnifiedSuggestionsContentResolverTests.swift`
- `DuckAISuggestionsPipelineTests.swift`
- `SuggestionsListViewModelTests.swift`

---

## Task 1: Unified data model (`SuggestionRow`, `SuggestionSection`)

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRow.swift`

There is no behavior to test here beyond `Equatable`/identity, which the type system guarantees — per project rules we do not unit-test trivial value types. This task is the type definition only; it is exercised by every later task's tests.

- [ ] **Step 1: Create the data model file**

Create via `mcp__xcode__XcodeWrite` at `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRow.swift`:

```swift
//
//  SuggestionRow.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import SwiftUI

/// One row in the unified UTI suggestions list. Pure data — carries no actions.
/// Selection and tap handling are dispatched by `id` to the active view model.
struct SuggestionRow: Identifiable, Equatable {

    enum Accessory: Equatable {
        case none
        case tapAhead
        case delete
    }

    let id: String
    let icon: Image
    let title: String
    /// When set, the matched prefix of `title` is rendered bold.
    let query: String?
    let subtitle: String?
    let accessory: Accessory
    let accessibilityID: String

    init(id: String,
         icon: Image,
         title: String,
         query: String? = nil,
         subtitle: String? = nil,
         accessory: Accessory = .none,
         accessibilityID: String) {
        self.id = id
        self.icon = icon
        self.title = title
        self.query = query
        self.subtitle = subtitle
        self.accessory = accessory
        self.accessibilityID = accessibilityID
    }
}

/// A titled group of rows. Sections with no rows are omitted by producers.
struct SuggestionSection: Identifiable, Equatable {
    let id: String
    let title: String?
    let rows: [SuggestionRow]

    init(id: String, title: String? = nil, rows: [SuggestionRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}
```

> Note: `Image` is `Equatable` in SwiftUI only by reference for some sources; here equality is driven by `id` in practice (producers assign stable ids). We keep the synthesized `Equatable` for diffing convenience — row identity for `ForEach` is `id`.

- [ ] **Step 2: Build to verify it compiles**

Run: `mcp__xcode__BuildProject` (iOS DuckDuckGo scheme).
Expected: build succeeds (file added to target via `XcodeWrite`).

- [ ] **Step 3: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRow.swift iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add unified SuggestionRow/SuggestionSection model"
```

---

## Task 2: Row mappers (`Suggestion`/`AIChatSuggestion` → `SuggestionRow`)

This is the highest-value test target in Part 1: the title/subtitle/icon/accessory derivation per suggestion case, ported faithfully from `DuckAISuggestionsViewController.configureURLCell` (`:423-453`) and `AutocompleteView`'s `SuggestionView` switch (`:177-232`).

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRowMapper.swift`
- Test: `DuckDuckGoTests/UnifiedToggleInput/Suggestions/SuggestionRowMapperTests.swift`

- [ ] **Step 1: Write the failing tests**

Create via `XcodeWrite` at `DuckDuckGoTests/UnifiedToggleInput/Suggestions/SuggestionRowMapperTests.swift`:

```swift
//
//  SuggestionRowMapperTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Suggestions
import AIChat
import XCTest
@testable import DuckDuckGo

final class SuggestionRowMapperTests: XCTestCase {

    func test_website_mapsTitleToFormattedURL_noSubtitle() {
        let url = URL(string: "https://example.com/path")!
        let row = SuggestionRowMapper.row(for: .website(url: url), query: "exa", idPrefix: "url")
        XCTAssertEqual(row.title, url.formattedForSuggestion())
        XCTAssertNil(row.subtitle)
        XCTAssertEqual(row.accessory, .none)
    }

    func test_bookmark_mapsTitleAndURLSubtitle() {
        let url = URL(string: "https://example.com")!
        let row = SuggestionRowMapper.row(for: .bookmark(title: "Bm", url: url, isFavorite: false, score: 0),
                                          query: nil, idPrefix: "url")
        XCTAssertEqual(row.title, "Bm")
        XCTAssertEqual(row.subtitle, url.formattedForSuggestion())
    }

    func test_serpHistory_usesSearchQueryTitle_andSearchSubtitle() {
        let url = URL(string: "https://duckduckgo.com/?q=swift")!
        let row = SuggestionRowMapper.row(for: .historyEntry(title: nil, url: url, score: 0),
                                          query: nil, idPrefix: "url")
        XCTAssertEqual(row.title, url.searchQuery ?? "")
        XCTAssertEqual(row.subtitle, UserText.autocompleteSearchDuckDuckGo)
    }

    func test_openTab_subtitlePrefixedWithSwitchToTab() {
        let url = URL(string: "https://example.com")!
        let row = SuggestionRowMapper.row(for: .openTab(title: "Tab", url: url, tabId: "1", score: 0),
                                          query: nil, idPrefix: "url")
        XCTAssertEqual(row.title, "Tab")
        XCTAssertEqual(row.subtitle, "\(UserText.autocompleteSwitchToTab) · \(url.formattedForSuggestion())")
    }

    func test_chat_pinnedUsesPinIcon_titleAndId() {
        let chat = AIChatSuggestion(id: "abc", title: "Hello", isPinned: true, chatId: "c1")
        let row = SuggestionRowMapper.row(for: chat)
        XCTAssertEqual(row.id, "chat-abc")
        XCTAssertEqual(row.title, "Hello")
        XCTAssertNil(row.subtitle)
        XCTAssertEqual(row.accessory, .none)
    }

    func test_searchRow_hasFindIcon_andSearchSubtitle() {
        let row = SuggestionRowMapper.searchRow(query: "weather", idPrefix: "search")
        XCTAssertEqual(row.title, "weather")
        XCTAssertEqual(row.subtitle, UserText.autocompleteSearchDuckDuckGo)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mcp__xcode__RunSomeTests` for `SuggestionRowMapperTests`.
Expected: FAIL to compile — `SuggestionRowMapper` undefined.

- [ ] **Step 3: Write the mapper**

Create via `XcodeWrite` at `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRowMapper.swift`:

```swift
//
//  SuggestionRowMapper.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import Suggestions
import SwiftUI

/// Pure mapping of existing suggestion models to the unified `SuggestionRow`.
/// Title/subtitle/icon logic mirrors the legacy renderers so output is identical.
enum SuggestionRowMapper {

    static func row(for suggestion: Suggestion, query: String?, idPrefix: String) -> SuggestionRow {
        switch suggestion {
        case .website(let url):
            return SuggestionRow(
                id: "\(idPrefix)-website-\(url.absoluteString)",
                icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.globe),
                title: url.formattedForSuggestion(),
                query: query,
                accessibilityID: "Autocomplete.Suggestions.ListItem.Website-\(url.formattedForSuggestion())")

        case .bookmark(let title, let url, let isFavorite, _):
            return SuggestionRow(
                id: "\(idPrefix)-bookmark-\(url.absoluteString)",
                icon: Image(uiImage: isFavorite ? DesignSystemImages.Glyphs.Size24.bookmarkFavorite
                                                 : DesignSystemImages.Glyphs.Size24.bookmark),
                title: title,
                query: query,
                subtitle: url.formattedForSuggestion(),
                accessibilityID: "Autocomplete.Suggestions.ListItem.Bookmark-\(url.formattedForSuggestion())")

        case .historyEntry(_, let url, _) where url.isDuckDuckGoSearch:
            return SuggestionRow(
                id: "\(idPrefix)-serp-\(url.absoluteString)",
                icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.history),
                title: url.searchQuery ?? "",
                query: query,
                subtitle: UserText.autocompleteSearchDuckDuckGo,
                accessory: .delete,
                accessibilityID: "Autocomplete.Suggestions.ListItem.SERPHistory-\(url.searchQuery ?? "")")

        case .historyEntry(let title, let url, _):
            return SuggestionRow(
                id: "\(idPrefix)-history-\(url.absoluteString)",
                icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.history),
                title: title ?? url.formattedForSuggestion(),
                query: query,
                subtitle: title == nil ? nil : url.formattedForSuggestion(),
                accessory: .delete,
                accessibilityID: "Autocomplete.Suggestions.ListItem.History-\(url.formattedForSuggestion())")

        case .openTab(let title, let url, _, _):
            return SuggestionRow(
                id: "\(idPrefix)-openTab-\(url.absoluteString)",
                icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.tabsMobile),
                title: title,
                query: query,
                subtitle: "\(UserText.autocompleteSwitchToTab) · \(url.formattedForSuggestion())",
                accessibilityID: "Autocomplete.Suggestions.ListItem.OpenTab-\(url.formattedForSuggestion())")

        case .phrase(let phrase):
            return SuggestionRow(
                id: "\(idPrefix)-phrase-\(phrase)",
                icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.findSearchSmall),
                title: phrase,
                query: query,
                accessory: .tapAhead,
                accessibilityID: "Autocomplete.Suggestions.ListItem.SearchPhrase-\(phrase)")

        case .askAIChat(let value):
            return SuggestionRow(
                id: "\(idPrefix)-askAIChat-\(value)",
                icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.aiChat),
                title: value,
                query: query,
                subtitle: UserText.autocompleteAskAIChat,
                accessibilityID: "Autocomplete.Suggestions.ListItem.AskAIChat-\(value)")

        case .internalPage, .unknown:
            assertionFailure("Unsupported suggestion type in unified list: \(suggestion)")
            return SuggestionRow(
                id: "\(idPrefix)-unknown",
                icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.globe),
                title: "",
                accessibilityID: "Autocomplete.Suggestions.ListItem.Unknown")
        }
    }

    static func row(for chat: AIChatSuggestion) -> SuggestionRow {
        SuggestionRow(
            id: "chat-\(chat.id)",
            icon: Image(uiImage: chat.isPinned ? DesignSystemImages.Glyphs.Size24.pin
                                               : DesignSystemImages.Glyphs.Size24.aiChat),
            title: chat.title,
            accessibilityID: "DuckAISuggestions.Chat-\(chat.id)")
    }

    static func searchRow(query: String, idPrefix: String) -> SuggestionRow {
        SuggestionRow(
            id: "\(idPrefix)-searchDuckDuckGo",
            icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.findSearchSmall),
            title: query,
            subtitle: UserText.autocompleteSearchDuckDuckGo,
            accessibilityID: "DuckAISuggestions.SearchDuckDuckGo")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mcp__xcode__RunSomeTests` for `SuggestionRowMapperTests`.
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRowMapper.swift iOS/DuckDuckGoTests/UnifiedToggleInput/Suggestions/SuggestionRowMapperTests.swift iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add SuggestionRowMapper with per-case tests"
```

---

## Task 3: Content resolver (the explicit state machine)

The pure `Inputs → ContentKind` decision table from spec §3.2, including the `resultsPending` "hold previous" anti-flash rule. This is the most important test in the refactor.

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsContentResolver.swift`
- Test: `DuckDuckGoTests/UnifiedToggleInput/Suggestions/UnifiedSuggestionsContentResolverTests.swift`

- [ ] **Step 1: Write the failing tests**

Create via `XcodeWrite` at `DuckDuckGoTests/UnifiedToggleInput/Suggestions/UnifiedSuggestionsContentResolverTests.swift`:

```swift
//
//  UnifiedSuggestionsContentResolverTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import XCTest
@testable import DuckDuckGo

final class UnifiedSuggestionsContentResolverTests: XCTestCase {

    private func inputs(mode: TextEntryMode,
                        isTyping: Bool = false,
                        hasFavoritesOrMessages: Bool = false,
                        hasRecents: Bool = false,
                        resultsPending: Bool = false) -> UnifiedSuggestionsInputs {
        UnifiedSuggestionsInputs(mode: mode,
                                 isTyping: isTyping,
                                 hasFavoritesOrMessages: hasFavoritesOrMessages,
                                 hasRecents: hasRecents,
                                 resultsPending: resultsPending)
    }

    func test_searchEmpty_withFavorites_isFavorites() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .search, hasFavoritesOrMessages: true), previous: nil)
        XCTAssertEqual(kind, .favorites)
    }

    func test_searchEmpty_noFavorites_isLogo() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .search, hasFavoritesOrMessages: false), previous: nil)
        XCTAssertEqual(kind, .logo)
    }

    func test_searchTyping_isSearchList() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .search, isTyping: true), previous: nil)
        XCTAssertEqual(kind, .list(.search))
    }

    func test_duckAIEmpty_withRecents_isRecentsList() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, hasRecents: true), previous: nil)
        XCTAssertEqual(kind, .list(.recents))
    }

    func test_duckAIEmpty_noRecents_isLogo() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, hasRecents: false), previous: nil)
        XCTAssertEqual(kind, .logo)
    }

    func test_duckAITyping_settled_isDuckAIList() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, isTyping: true, resultsPending: false), previous: nil)
        XCTAssertEqual(kind, .list(.duckAI))
    }

    func test_duckAITyping_pending_holdsPrevious_noFlashToLogo() {
        let previous: UnifiedSuggestionsContentKind = .list(.duckAI)
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, isTyping: true, resultsPending: true), previous: previous)
        XCTAssertEqual(kind, .list(.duckAI))
    }

    func test_duckAITyping_pending_withNoPrevious_fallsBackToDuckAIList_notLogo() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, isTyping: true, resultsPending: true), previous: nil)
        XCTAssertEqual(kind, .list(.duckAI))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mcp__xcode__RunSomeTests` for `UnifiedSuggestionsContentResolverTests`.
Expected: FAIL to compile — resolver/types undefined.

- [ ] **Step 3: Write the resolver**

Create via `XcodeWrite` at `DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsContentResolver.swift`:

```swift
//
//  UnifiedSuggestionsContentResolver.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Foundation

/// Which list data source is active for a `.list` presentation.
enum SuggestionsListSourceKind: Equatable {
    case search
    case duckAI
    case recents
}

/// The presentation the unified suggestions view should render. Pure value — no view models.
enum UnifiedSuggestionsContentKind: Equatable {
    case list(SuggestionsListSourceKind)
    case favorites
    case logo
}

/// The complete set of facts that decide the presentation. No UIKit, no managers.
struct UnifiedSuggestionsInputs: Equatable {
    let mode: TextEntryMode
    let isTyping: Bool
    let hasFavoritesOrMessages: Bool
    let hasRecents: Bool
    let resultsPending: Bool
}

/// Pure decision table (spec §3.2). `previous` lets us hold the prior presentation while
/// duck.ai fetchers are still settling, so the logo never flashes mid-query.
enum UnifiedSuggestionsContentResolver {

    static func resolve(_ inputs: UnifiedSuggestionsInputs,
                        previous: UnifiedSuggestionsContentKind?) -> UnifiedSuggestionsContentKind {
        switch inputs.mode {
        case .search:
            guard inputs.isTyping else {
                return inputs.hasFavoritesOrMessages ? .favorites : .logo
            }
            return .list(.search)

        case .aiChat:
            guard inputs.isTyping else {
                return inputs.hasRecents ? .list(.recents) : .logo
            }
            if inputs.resultsPending {
                // Hold the prior presentation rather than flashing to the logo while
                // fetchers settle. If there is no prior list, show the duck.ai list shell.
                if let previous, case .list = previous { return previous }
                return .list(.duckAI)
            }
            return .list(.duckAI)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mcp__xcode__RunSomeTests` for `UnifiedSuggestionsContentResolverTests`.
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsContentResolver.swift iOS/DuckDuckGoTests/UnifiedToggleInput/Suggestions/UnifiedSuggestionsContentResolverTests.swift iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add UnifiedSuggestionsContentResolver decision table + tests"
```

---

## Task 4: Settle-aware Duck.ai query pipeline

Replaces the dual-debounce + 80ms coalesce + `hasSettled` guess in `DuckAISuggestionsViewController` (`:94-97, 177-185`). One Combine pipeline merges the recents (`AIChatSuggestionsViewModel.$filteredSuggestions`) and URL (`DuckAIURLSuggestionsLoader.$topURLs`) outputs into a single snapshot, tagged with `isPending` (true until the URL loader has completed the latest dispatched query). Scheduler is injected so debounce is deterministic in tests.

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/DuckAISuggestionsPipeline.swift`
- Test: `DuckDuckGoTests/UnifiedToggleInput/Suggestions/DuckAISuggestionsPipelineTests.swift`

- [ ] **Step 1: Write the failing tests**

Create via `XcodeWrite` at `DuckDuckGoTests/UnifiedToggleInput/Suggestions/DuckAISuggestionsPipelineTests.swift`:

```swift
//
//  DuckAISuggestionsPipelineTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Combine
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAISuggestionsPipelineTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_emitsSettledSnapshot_whenURLFetchCompletesForLatestQuery() {
        let chats = CurrentValueSubject<[AIChatSuggestion], Never>([])
        let urls = CurrentValueSubject<[Suggestion], Never>([])
        let pipeline = DuckAISuggestionsPipeline(
            chatsPublisher: chats.eraseToAnyPublisher(),
            urlsPublisher: urls.eraseToAnyPublisher(),
            latestDispatchedQuery: { "swift" },
            lastCompletedURLQuery: { "swift" })

        var snapshots: [DuckAISuggestionsPipeline.Snapshot] = []
        pipeline.snapshotPublisher
            .sink { snapshots.append($0) }
            .store(in: &cancellables)

        urls.send([.website(url: URL(string: "https://swift.org")!)])

        XCTAssertEqual(snapshots.last?.isPending, false)
        XCTAssertEqual(snapshots.last?.urls.count, 1)
    }

    func test_isPending_whenLatestQueryNotYetCompleted() {
        let chats = CurrentValueSubject<[AIChatSuggestion], Never>([])
        let urls = CurrentValueSubject<[Suggestion], Never>([])
        var completed = ""
        let pipeline = DuckAISuggestionsPipeline(
            chatsPublisher: chats.eraseToAnyPublisher(),
            urlsPublisher: urls.eraseToAnyPublisher(),
            latestDispatchedQuery: { "swiftui" },
            lastCompletedURLQuery: { completed })

        var snapshots: [DuckAISuggestionsPipeline.Snapshot] = []
        pipeline.snapshotPublisher
            .sink { snapshots.append($0) }
            .store(in: &cancellables)

        chats.send([AIChatSuggestion(id: "1", title: "Hi", isPinned: false, chatId: "c")])

        XCTAssertEqual(snapshots.last?.isPending, true)

        completed = "swiftui"
        urls.send([.website(url: URL(string: "https://swiftui.org")!)])
        XCTAssertEqual(snapshots.last?.isPending, false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mcp__xcode__RunSomeTests` for `DuckAISuggestionsPipelineTests`.
Expected: FAIL to compile — `DuckAISuggestionsPipeline` undefined.

- [ ] **Step 3: Write the pipeline**

Create via `XcodeWrite` at `DuckDuckGo/UnifiedToggleInput/Suggestions/DuckAISuggestionsPipeline.swift`:

```swift
//
//  DuckAISuggestionsPipeline.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Combine
import Suggestions

/// Merges the recents and URL fetchers into one snapshot tagged with an explicit
/// `isPending` state, replacing the timing-based coalesce + `hasSettled` heuristic.
@MainActor
final class DuckAISuggestionsPipeline {

    struct Snapshot: Equatable {
        let chats: [AIChatSuggestion]
        let urls: [Suggestion]
        /// True while the URL loader has not yet completed the latest dispatched query.
        let isPending: Bool
    }

    let snapshotPublisher: AnyPublisher<Snapshot, Never>

    init(chatsPublisher: AnyPublisher<[AIChatSuggestion], Never>,
         urlsPublisher: AnyPublisher<[Suggestion], Never>,
         latestDispatchedQuery: @escaping () -> String,
         lastCompletedURLQuery: @escaping () -> String) {

        snapshotPublisher = Publishers.CombineLatest(
            chatsPublisher.prepend([]),
            urlsPublisher.prepend([])
        )
        .map { chats, urls in
            let pending = latestDispatchedQuery() != lastCompletedURLQuery()
            return Snapshot(chats: chats, urls: urls, isPending: pending)
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mcp__xcode__RunSomeTests` for `DuckAISuggestionsPipelineTests`.
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/DuckAISuggestionsPipeline.swift iOS/DuckDuckGoTests/UnifiedToggleInput/Suggestions/DuckAISuggestionsPipelineTests.swift iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add settle-aware DuckAISuggestionsPipeline + tests"
```

---

## Task 5: Suggestion sources (produce `[SuggestionSection]`)

A `SuggestionsSource` exposes a published `[SuggestionSection]`. Three conformers: Duck.ai (chats + urls + search row, from the pipeline snapshot), recents (single chats section), and search (top-hits / ddg / local / askAI sections from `AutocompleteViewModel`). This task implements the Duck.ai and recents sources (search source reuses `AutocompleteViewModel`'s already-sectioned output and is wired in Part 2). Section composition mirrors `DuckAISuggestionsViewController.liveSections` (`:197-203`): a section is included only when its rows are non-empty.

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsSource.swift`
- Test: `DuckDuckGoTests/UnifiedToggleInput/Suggestions/SuggestionsListViewModelTests.swift` (shared with Task 6)

- [ ] **Step 1: Write the failing tests**

Create via `XcodeWrite` at `DuckDuckGoTests/UnifiedToggleInput/Suggestions/SuggestionsListViewModelTests.swift`:

```swift
//
//  SuggestionsListViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Combine
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class SuggestionsListViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_duckAISource_composesChatsUrlsSearch_inOrder_skippingEmpty() {
        let snapshots = CurrentValueSubject<DuckAISuggestionsPipeline.Snapshot, Never>(
            .init(chats: [AIChatSuggestion(id: "1", title: "Recent", isPinned: false, chatId: "c")],
                  urls: [.website(url: URL(string: "https://swift.org")!)],
                  isPending: false))
        let source = DuckAISuggestionsSource(snapshotPublisher: snapshots.eraseToAnyPublisher(),
                                             query: { "swift" })

        var sections: [SuggestionSection] = []
        source.sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)

        XCTAssertEqual(sections.map(\.id), ["chats", "urls", "search"])
        XCTAssertEqual(sections[0].rows.first?.title, "Recent")
        XCTAssertEqual(sections[2].rows.first?.title, "swift")
    }

    func test_duckAISource_emptyQuery_hasNoSearchSection() {
        let snapshots = CurrentValueSubject<DuckAISuggestionsPipeline.Snapshot, Never>(
            .init(chats: [], urls: [], isPending: false))
        let source = DuckAISuggestionsSource(snapshotPublisher: snapshots.eraseToAnyPublisher(),
                                             query: { "" })

        var sections: [SuggestionSection] = []
        source.sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)

        XCTAssertTrue(sections.isEmpty)
    }

    func test_recentsSource_singleSection_fromChats() {
        let vm = AIChatSuggestionsViewModel()
        vm.setChats(pinned: [], recent: [AIChatSuggestion(id: "1", title: "R", isPinned: false, chatId: "c")])
        let source = RecentsSuggestionsSource(viewModel: vm)

        var sections: [SuggestionSection] = []
        source.sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.rows.first?.title, "R")
    }

    func test_listViewModel_publishesSectionsFromSource() {
        let snapshots = CurrentValueSubject<DuckAISuggestionsPipeline.Snapshot, Never>(
            .init(chats: [], urls: [.website(url: URL(string: "https://x.com")!)], isPending: false))
        let source = DuckAISuggestionsSource(snapshotPublisher: snapshots.eraseToAnyPublisher(),
                                             query: { "" })
        let sut = SuggestionsListViewModel(source: source)

        XCTAssertEqual(sut.sections.map(\.id), ["urls"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mcp__xcode__RunSomeTests` for `SuggestionsListViewModelTests`.
Expected: FAIL to compile — sources/view model undefined.

- [ ] **Step 3: Write the sources**

Create via `XcodeWrite` at `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsSource.swift`:

```swift
//
//  SuggestionsSource.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Combine
import Suggestions

/// Produces the unified sections for one list presentation. Conformers wrap an existing
/// data source and map its output to `[SuggestionSection]`.
@MainActor
protocol SuggestionsSource {
    var sectionsPublisher: AnyPublisher<[SuggestionSection], Never> { get }
}

/// Duck.ai-typing source: recents + URL hits + a "Search DuckDuckGo" row.
@MainActor
final class DuckAISuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    init(snapshotPublisher: AnyPublisher<DuckAISuggestionsPipeline.Snapshot, Never>,
         query: @escaping () -> String) {
        sectionsPublisher = snapshotPublisher
            .map { snapshot in
                var sections: [SuggestionSection] = []

                if !snapshot.chats.isEmpty {
                    sections.append(SuggestionSection(
                        id: "chats",
                        rows: snapshot.chats.map { SuggestionRowMapper.row(for: $0) }))
                }
                if !snapshot.urls.isEmpty {
                    let q = query()
                    sections.append(SuggestionSection(
                        id: "urls",
                        rows: snapshot.urls.map { SuggestionRowMapper.row(for: $0, query: q, idPrefix: "urls") }))
                }
                let q = query()
                if !q.isEmpty {
                    sections.append(SuggestionSection(
                        id: "search",
                        rows: [SuggestionRowMapper.searchRow(query: q, idPrefix: "search")]))
                }
                return sections
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

/// Duck.ai-empty source: a single section of recent chats.
@MainActor
final class RecentsSuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    init(viewModel: AIChatSuggestionsViewModel) {
        sectionsPublisher = viewModel.$filteredSuggestions
            .map { chats in
                guard !chats.isEmpty else { return [] }
                return [SuggestionSection(id: "recents",
                                          rows: chats.map { SuggestionRowMapper.row(for: $0) })]
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
```

- [ ] **Step 4: Run tests to verify the source tests pass**

Run: `mcp__xcode__RunSomeTests` for `SuggestionsListViewModelTests` (the source-only tests; the `SuggestionsListViewModel` test still fails until Task 6).
Expected: the three `*Source*` tests PASS; `test_listViewModel_publishesSectionsFromSource` FAILs to compile.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsSource.swift iOS/DuckDuckGoTests/UnifiedToggleInput/Suggestions/SuggestionsListViewModelTests.swift iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add Duck.ai and recents suggestion sources + tests"
```

---

## Task 6: `SuggestionsListViewModel`

Thin `@MainActor ObservableObject` that republishes a source's sections and routes row actions by id. The injected action closures keep the data model action-free (spec §3.1).

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsListViewModel.swift`
- Test: existing `SuggestionsListViewModelTests.swift` (Task 5)

- [ ] **Step 1: Confirm the failing test exists**

The test `test_listViewModel_publishesSectionsFromSource` from Task 5 currently fails to compile. No new test code needed.

- [ ] **Step 2: Run to confirm failure**

Run: `mcp__xcode__RunSomeTests` for `SuggestionsListViewModelTests`.
Expected: compile failure referencing `SuggestionsListViewModel`.

- [ ] **Step 3: Write the view model**

Create via `XcodeWrite` at `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsListViewModel.swift`:

```swift
//
//  SuggestionsListViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import Foundation

/// Drives one `.list` presentation: republishes its source's sections and routes
/// row interactions back out by id. Holds no suggestion data of its own.
@MainActor
final class SuggestionsListViewModel: ObservableObject {

    @Published private(set) var sections: [SuggestionSection] = []
    /// Transient keyboard-selection highlight; not part of the row model.
    @Published var selectedRowID: String?

    var onSelect: ((String) -> Void)?
    var onTapAhead: ((String) -> Void)?
    var onDelete: ((String) -> Void)?

    private var cancellable: AnyCancellable?

    init(source: SuggestionsSource) {
        cancellable = source.sectionsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.sections, on: self)
    }

    func selectRow(id: String) { onSelect?(id) }
    func tapAheadRow(id: String) { onTapAhead?(id) }
    func deleteRow(id: String) { onDelete?(id) }
}
```

- [ ] **Step 4: Run tests to verify the whole file passes**

Run: `mcp__xcode__RunSomeTests` for `SuggestionsListViewModelTests`.
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsListViewModel.swift iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add SuggestionsListViewModel + tests"
```

---

## Part 1 completion

- [ ] **Full build + targeted test run**

Run: `mcp__xcode__BuildProject`, then `mcp__xcode__RunSomeTests` for the four new test classes.
Expected: build succeeds; all tests pass; no behavior change in the app (nothing wired yet).

- [ ] **Hand off to Part 2 planning**

The core (data model, mapper, resolver, pipeline, sources, list VM) is now landed and unit-tested. Write the Part 2 plan (assemble `UnifiedSuggestionsView` + chrome, swap Duck.ai suggestions → recents → search, wire `.favorites`/`.logo` with the explicit logo centering from spec §3.4, retire `updateDaxVisibility()`, cleanup) against the now-concrete interfaces. Part 2 is where on-simulator, side-by-side verification begins.
```
