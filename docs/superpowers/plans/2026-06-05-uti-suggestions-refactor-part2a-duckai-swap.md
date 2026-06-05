# UTI Suggestions Refactor — Part 2a: Duck.ai Surface Swap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the Duck.ai-mode suggestions surface (recents + URL hits + "Search DuckDuckGo" row, plus the escape hatch and sync promo) with the new SwiftUI `UnifiedSuggestionsView`, replacing `DuckAISuggestionsViewController` on the UTI-flag-ON path — the first on-device-visible step of the refactor.

**Architecture:** A SwiftUI `UnifiedSuggestionsView` (List of `SuggestionSection`/`SuggestionRow` from Part 1, plus an optional escape-hatch + sync-promo header) is driven by `SuggestionsListViewModel` (Part 1) whose source is `DuckAISuggestionsSource` over the existing `AIChatSuggestionsViewModel` + `DuckAIURLSuggestionsLoader`. A new `UnifiedDuckAISuggestionsHost` hosts that view in `swipeContainerManager.chatPageContainer` and exposes the exact surface the container already calls (`hasContent`, `hasSettled(forQuery:)`, `setEscapeHatch`, `setAdditionalTopInset`, `onContentChanged`, `tearDown`), so it is a drop-in for `DuckAISuggestionsCoordinator`. The Dax logo continues to be driven by `DaxLogoManager` (unchanged).

**Tech Stack:** SwiftUI, Combine, UIKit hosting (`UIHostingController`), XCTest, `InlineSnapshotTesting` (available). Reuses Part 1: `SuggestionRow`, `SuggestionSection`, `SuggestionRowIcon`, `SuggestionRowMapper`, `DuckAISuggestionsPipeline`, `DuckAISuggestionsSource`, `SuggestionsListViewModel`.

**Scope — IN:** Duck.ai-mode list rendering (typing results + empty-state recents), escape hatch + sync promo in the unified view, row selection / tap-ahead / delete routing to the existing delegate actions, drop-in host, flipping `installDuckAISuggestions()` to the host.

**Scope — OUT (Part 2b):** search-typing (`AutocompleteView` reuse), favorites/NTP embed, moving logo positioning off `DaxLogoManager`, wiring the Part 1 `UnifiedSuggestionsContentResolver` aggregator at container level, retiring `updateDaxVisibility()`, deleting `DuckAISuggestionsViewController`/`DuckAISuggestionsCoordinator`, keyboard arrow-nav. (Logo stays on `DaxLogoManager`; the resolver is not needed until search/favorites join.) The deferred Lottie refactor (#5) and the Part 2 scope items in `.pr-followups.md` remain tracked there.

**Conventions:** New files via `mcp__xcode__XcodeWrite` (project-org paths). Build/test via `mcp__xcode__BuildProject` / `GetTestList` / `RunSomeTests`, tab `windowtab1`, test target `UnitTests`. Never `xcodebuild`; never hand-edit `project.pbxproj`; never use "track". Ignore SourceKit live diagnostics — trust `BuildProject`. Revert `DuckDuckGo.xcworkspace/xcshareddata/swiftpm/Package.resolved` if auto-touched. Short commit messages, no Co-Authored-By.

**Row parity reference (ported verbatim from existing renderers — match these exactly):**
- Icon: 24pt, tint `designSystemColor: .icons`, text spacing 10pt, leading inset 16pt.
- Title: `UIFont.daxBodyRegular()`, `designSystemColor: .textPrimary`, 1 line, truncating tail. When `query` is a prefix of `title`, the matched prefix is `daxBodyRegular` and the remainder is `daxBodyBold` (mirrors `SuggestionListItem`).
- Subtitle: `UIFont.daxFootnoteRegular()`, `designSystemColor: .textSecondary`, 1 line.
- Row background `designSystemColor: .surface`; separators leading-inset = 16 + 24 + 10.
- Accessory `.tapAhead`: `DesignSystemImages.Glyphs.Size16.arrowCircleUpLeft` (top address bar) / `.arrowCircleDownLeft` (bottom), tint `.iconsSecondary`. Accessory `.delete`: `DesignSystemImages.Glyphs.Size16.clear`, tint `.iconsSecondary`, a11y label `UserText.actionDelete`, a11y id `Autocomplete.Suggestions.ListItem.DeleteButton`.

---

## File Structure

**New product files** (`DuckDuckGo/UnifiedToggleInput/Suggestions/`):
- `SuggestionRowIcon+Glyph.swift` — resolves `SuggestionRowIcon` → `UIImage` glyph (the one place that re-couples icons to the design system, in the view layer).
- `SuggestionRowView.swift` — the SwiftUI row (icon, query-bolded title, subtitle, accessory). One responsibility: render one `SuggestionRow`.
- `UnifiedSuggestionsView.swift` — the List of sections + optional escape-hatch/sync-promo header; dispatches row actions to the view model.
- `DuckAISuggestionsSelection.swift` — typed resolution of a `rowID` back to an action (`.chat` / `.url` / `.searchDuckDuckGo`), owned by the source.
- `UnifiedDuckAISuggestionsHost.swift` — installs `UnifiedSuggestionsView` into a container view; drop-in for `DuckAISuggestionsCoordinator`'s container-facing surface.

**Modified:**
- `SuggestionsSource.swift` (Part 1) — `DuckAISuggestionsSource` gains `selection(forRowID:)` + holds the latest snapshot for resolution.
- `UnifiedInputContentContainerViewController.swift` — `installDuckAISuggestions()` builds the host instead of the coordinator (behind a small internal switch so the change is isolated).

**New test files** (`DuckDuckGoTests/UnifiedToggleInput/Suggestions/`):
- `DuckAISuggestionsSelectionTests.swift`

---

## Task 1: Icon → glyph resolution

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRowIcon+Glyph.swift`

No test (a pure mechanical mapping verified by the build + on-device parity). This is the one place the view layer re-couples icons to `DesignSystemImages`.

- [ ] **Step 1: Create the glyph resolver**

`XcodeWrite` → `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRowIcon+Glyph.swift`:

```swift
//
//  SuggestionRowIcon+Glyph.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import DesignResourcesKitIcons
import UIKit

extension SuggestionRowIcon {
    /// The 24pt design-system glyph for this semantic icon.
    var glyph: UIImage {
        switch self {
        case .globe: return DesignSystemImages.Glyphs.Size24.globe
        case .bookmark: return DesignSystemImages.Glyphs.Size24.bookmark
        case .favorite: return DesignSystemImages.Glyphs.Size24.bookmarkFavorite
        case .history: return DesignSystemImages.Glyphs.Size24.history
        case .openTab: return DesignSystemImages.Glyphs.Size24.tabsMobile
        case .search: return DesignSystemImages.Glyphs.Size24.findSearchSmall
        case .aiChat: return DesignSystemImages.Glyphs.Size24.aiChat
        case .pin: return DesignSystemImages.Glyphs.Size24.pin
        }
    }
}
```

- [ ] **Step 2: Build**

`mcp__xcode__BuildProject` (tab `windowtab1`). Expected: success.

- [ ] **Step 3: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRowIcon+Glyph.swift iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Add SuggestionRowIcon glyph resolution"
```

---

## Task 2: `SuggestionRowView`

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRowView.swift`

SwiftUI render of one `SuggestionRow`. No unit test (pure UI; parity verified on-device + optional snapshot in Task 6). Modeled on `AutocompleteView.SuggestionListItem` for parity.

- [ ] **Step 1: Create the row view**

`XcodeWrite` → `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRowView.swift`:

```swift
//
//  SuggestionRowView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

/// Renders one unified suggestion row. Layout/typography mirror the legacy
/// `SuggestionListItem` so output matches the shipped autocomplete row.
struct SuggestionRowView: View {

    let row: SuggestionRow
    let isAddressBarAtBottom: Bool
    let onTapAhead: () -> Void
    let onDelete: () -> Void

    private enum Metrics {
        static let iconSize: CGFloat = 24
        static let iconTextSpacing: CGFloat = 10
        static let trailingPadding: CGFloat = 20
        static let accessoryLeadingPadding: CGFloat = 4
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(uiImage: row.icon.glyph)
                .resizable()
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                .tintIfAvailable(Color(designSystemColor: .icons))

            VStack(alignment: .leading, spacing: 0) {
                titleText
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .lineLimit(1)
                }
            }
            .padding(.leading, Metrics.iconTextSpacing)

            if row.accessory == .none {
                Spacer(minLength: Metrics.trailingPadding)
            } else {
                Spacer()
                accessory
                    .padding(.leading, Metrics.accessoryLeadingPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var titleText: Text {
        if let query = row.query, row.title.hasPrefix(query) {
            Text(query)
                .font(Font(uiFont: UIFont.daxBodyRegular()))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            + Text(row.title.dropping(prefix: query))
                .font(Font(uiFont: UIFont.daxBodyBold()))
                .foregroundColor(Color(designSystemColor: .textPrimary))
        } else {
            Text(row.title)
                .font(Font(uiFont: UIFont.daxBodyRegular()))
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch row.accessory {
        case .tapAhead:
            Image(uiImage: isAddressBarAtBottom
                  ? DesignSystemImages.Glyphs.Size16.arrowCircleDownLeft
                  : DesignSystemImages.Glyphs.Size16.arrowCircleUpLeft)
                .tintIfAvailable(Color(designSystemColor: .iconsSecondary))
                .highPriorityGesture(TapGesture().onEnded { onTapAhead() })
        case .delete:
            Image(uiImage: DesignSystemImages.Glyphs.Size16.clear)
                .tintIfAvailable(Color(designSystemColor: .iconsSecondary))
                .highPriorityGesture(TapGesture().onEnded { onDelete() })
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.DeleteButton")
                .accessibilityLabel(UserText.actionDelete)
        case .none:
            EmptyView()
        }
    }
}
```

- [ ] **Step 2: Build**

`mcp__xcode__BuildProject`. Expected: success. (If `tintIfAvailable` / `dropping(prefix:)` / `daxFootnoteRegular()` are not resolvable from this file's imports, STOP and report — they are used by `AutocompleteView.swift`, so confirm its imports: `DesignResourcesKit`, `DesignResourcesKitIcons`. Do not invent replacements.)

- [ ] **Step 3: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionRowView.swift iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Add SuggestionRowView (parity with legacy suggestion row)"
```

---

## Task 3: Typed selection resolution on `DuckAISuggestionsSource`

The list view dispatches actions by `rowID` (string). To route back to typed actions without stringly-typed parsing in the host, `DuckAISuggestionsSource` retains the latest snapshot + query and resolves a `rowID` to a `DuckAISuggestionsSelection`.

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/DuckAISuggestionsSelection.swift`
- Modify: `DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsSource.swift`
- Test: `DuckDuckGoTests/UnifiedToggleInput/Suggestions/DuckAISuggestionsSelectionTests.swift`

- [ ] **Step 1: Write the failing test**

`XcodeWrite` → `DuckDuckGoTests/UnifiedToggleInput/Suggestions/DuckAISuggestionsSelectionTests.swift`:

```swift
//
//  DuckAISuggestionsSelectionTests.swift
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
final class DuckAISuggestionsSelectionTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() { cancellables.removeAll(); super.tearDown() }

    private func makeSource(chats: [AIChatSuggestion], urls: [Suggestion], query: String)
        -> DuckAISuggestionsSource {
        let subject = CurrentValueSubject<DuckAISuggestionsPipeline.Snapshot, Never>(
            .init(chats: chats, urls: urls, isPending: false))
        let source = DuckAISuggestionsSource(snapshotPublisher: subject.eraseToAnyPublisher(),
                                             query: { query })
        // Drain one emission so the source captures the snapshot.
        source.sectionsPublisher.sink { _ in }.store(in: &cancellables)
        return source
    }

    func test_resolvesChatRowToChatSelection() {
        let chat = AIChatSuggestion(id: "abc", title: "Hi", isPinned: false, chatId: "c1")
        let source = makeSource(chats: [chat], urls: [], query: "")
        XCTAssertEqual(source.selection(forRowID: "chat-abc"), .chat(chat))
    }

    func test_resolvesURLRowToURLSelection() {
        let url = URL(string: "https://swift.org")!
        let suggestion = Suggestion.website(url: url)
        let source = makeSource(chats: [], urls: [suggestion], query: "sw")
        XCTAssertEqual(source.selection(forRowID: "urls-website-\(url.absoluteString)"), .url(suggestion))
    }

    func test_resolvesSearchRowToSearchSelection() {
        let source = makeSource(chats: [], urls: [], query: "weather")
        XCTAssertEqual(source.selection(forRowID: "search-searchDuckDuckGo"), .searchDuckDuckGo("weather"))
    }

    func test_unknownRowIDResolvesToNil() {
        let source = makeSource(chats: [], urls: [], query: "")
        XCTAssertNil(source.selection(forRowID: "does-not-exist"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

`GetTestList` then `RunSomeTests` (`UnitTests` / `DuckAISuggestionsSelectionTests`). Expected: compile failure (`DuckAISuggestionsSelection` / `selection(forRowID:)` undefined).

- [ ] **Step 3: Create the selection type**

`XcodeWrite` → `DuckDuckGo/UnifiedToggleInput/Suggestions/DuckAISuggestionsSelection.swift`:

```swift
//
//  DuckAISuggestionsSelection.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Suggestions

/// A typed Duck.ai row selection, resolved from a `SuggestionRow.id`.
enum DuckAISuggestionsSelection: Equatable {
    case chat(AIChatSuggestion)
    case url(Suggestion)
    case searchDuckDuckGo(String)
}
```

- [ ] **Step 4: Add snapshot capture + `selection(forRowID:)` to `DuckAISuggestionsSource`**

In `SuggestionsSource.swift`, replace the `DuckAISuggestionsSource` class with this version (adds `latestSnapshot`/`latestQuery` capture in the map, plus the resolver). The `sectionsPublisher` mapping is unchanged in behavior:

```swift
/// Duck.ai-typing source: recents + URL hits + a "Search DuckDuckGo" row.
@MainActor
final class DuckAISuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    private let query: () -> String
    /// Reference holder recording the latest snapshot for `selection(forRowID:)`. A class lets the
    /// `map` closure (built in `init` before `self` is fully initialized) record without capturing `self`.
    private let captureBox = SnapshotBox()

    init(snapshotPublisher: AnyPublisher<DuckAISuggestionsPipeline.Snapshot, Never>,
         query: @escaping () -> String) {
        self.query = query
        let box = captureBox
        sectionsPublisher = snapshotPublisher
            .map { snapshot in
                box.value = snapshot
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

    /// Resolves a row id (as minted by `SuggestionRowMapper`) back to a typed selection.
    func selection(forRowID id: String) -> DuckAISuggestionsSelection? {
        let snapshot = captureBox.value
        if id.hasPrefix("chat-") {
            let chatID = String(id.dropFirst("chat-".count))
            return snapshot.chats.first { $0.id == chatID }.map { .chat($0) }
        }
        if id == "search-searchDuckDuckGo" {
            return .searchDuckDuckGo(query())
        }
        if id.hasPrefix("urls-") {
            return snapshot.urls.first { SuggestionRowMapper.row(for: $0, query: query(), idPrefix: "urls").id == id }
                .map { .url($0) }
        }
        return nil
    }
}

/// Reference holder so the section-mapping closure can record the latest snapshot
/// without capturing `self` (which isn't fully initialized when the publisher is built).
private final class SnapshotBox {
    var value = DuckAISuggestionsPipeline.Snapshot(chats: [], urls: [], isPending: false)
}
```

> Implementer note: the `SnapshotBox` indirection exists only because the `map` closure is built inside `init` before `self` is fully initialized. If you find a cleaner construction (e.g. building the publisher lazily), that's acceptable as long as `selection(forRowID:)` reads the most recent snapshot and all tests pass. Do not change the section-composition behavior.

- [ ] **Step 5: Run tests**

`RunSomeTests` (`UnitTests` / `DuckAISuggestionsSelectionTests` + `SuggestionsListViewModelTests`). Expected: all pass (4 new + 4 existing source/VM tests still green).

- [ ] **Step 6: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/DuckAISuggestionsSelection.swift iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsSource.swift iOS/DuckDuckGoTests/UnifiedToggleInput/Suggestions/DuckAISuggestionsSelectionTests.swift iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Add typed Duck.ai row selection resolution"
```

---

## Task 4: `UnifiedSuggestionsView`

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsView.swift`

The List of sections + optional escape-hatch / sync-promo header. No unit test (UI). Behavior verified on-device (Task 6).

- [ ] **Step 1: Create the view**

`XcodeWrite` → `DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsView.swift`:

```swift
//
//  UnifiedSuggestionsView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import DesignResourcesKit
import SwiftUI

/// The unified Duck.ai suggestions surface: an optional escape-hatch + sync-promo header
/// followed by the data-driven sections. Replaces `DuckAISuggestionsViewController`'s table.
struct UnifiedSuggestionsView: View {

    @ObservedObject var viewModel: SuggestionsListViewModel
    let isAddressBarAtBottom: Bool
    let header: AnyView?

    var body: some View {
        List {
            if let header {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        Button {
                            viewModel.selectRow(id: row.id)
                        } label: {
                            SuggestionRowView(
                                row: row,
                                isAddressBarAtBottom: isAddressBarAtBottom,
                                onTapAhead: { viewModel.tapAheadRow(id: row.id) },
                                onDelete: { viewModel.deleteRow(id: row.id) })
                        }
                        .listRowBackground(Color(designSystemColor: .surface))
                    }
                } header: {
                    sectionHeader(section.title)
                }
            }
        }
        .listStyle(.plain)
        .modifier(HideScrollContentBackgroundModifier())
        .background(Color(designSystemColor: .background))
        .scrollDismissesKeyboardIfAvailable()
    }

    @ViewBuilder
    private func sectionHeader(_ title: String?) -> some View {
        if let title, !title.isEmpty {
            Text(title)
                .daxTitle3()
                .foregroundColor(Color(designSystemColor: .textPrimary))
        } else {
            EmptyView()
        }
    }
}

private struct HideScrollContentBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16, *) { content.scrollContentBackground(.hidden) } else { content }
    }
}

private extension View {
    @ViewBuilder
    func scrollDismissesKeyboardIfAvailable() -> some View {
        if #available(iOS 16, *) { self.scrollDismissesKeyboard(.immediately) } else { self }
    }
}
```

> Implementer note: today's design suppresses the recents section header (`DuckAISuggestionsViewController.areSectionHeadersEnabled == false`). Producers pass `title: nil` for the chats section, so `sectionHeader` renders `EmptyView`. Preserve that — do not add a "Recent Chats" title in this task.

- [ ] **Step 2: Build**

`mcp__xcode__BuildProject`. Expected: success. If `daxTitle3()` or a list modifier is unavailable, STOP and report (these are used in `AutocompleteView.swift` / `DuckAISuggestionsViewController.swift`).

- [ ] **Step 3: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsView.swift iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Add UnifiedSuggestionsView list + header"
```

---

## Task 5: `UnifiedDuckAISuggestionsHost` (drop-in for the coordinator)

Hosts `UnifiedSuggestionsView` in a container view and exposes the exact surface `UnifiedInputContentContainerViewController` already calls. Builds its own pipeline/source/list-VM from the injected `AIChatSuggestionsViewModel` + `DuckAIURLSuggestionsLoader` + `AIChatHistoryManager` (same objects the container builds today).

**Files:**
- Create: `DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedDuckAISuggestionsHost.swift`

No standalone unit test (integration; the list/source/selection logic it composes is already tested). Verified on-device in Task 6.

- [ ] **Step 1: Create the host**

`XcodeWrite` → `DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedDuckAISuggestionsHost.swift`:

```swift
//
//  UnifiedDuckAISuggestionsHost.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Combine
import DDGSync
import Suggestions
import SwiftUI
import UIKit

/// Hosts the SwiftUI `UnifiedSuggestionsView` for the Duck.ai surface. Exposes the same
/// container-facing surface as `DuckAISuggestionsCoordinator`, so it is a drop-in replacement
/// for the UTI-flag-ON Duck.ai path. The Dax logo stays driven by `DaxLogoManager`.
@MainActor
final class UnifiedDuckAISuggestionsHost {

    weak var delegate: DuckAISuggestionsViewControllerDelegate?
    var onContentChanged: (() -> Void)?

    private let chatManager: AIChatHistoryManager
    private let urlLoader: DuckAIURLSuggestionsLoader
    private let chatViewModel: AIChatSuggestionsViewModel
    private let queryProvider: () -> String
    private let isAddressBarAtBottom: Bool

    private let source: DuckAISuggestionsSource
    private let listViewModel: SuggestionsListViewModel
    private var hostingController: UIHostingController<UnifiedSuggestionsView>?
    private var escapeHatchModel: EscapeHatchModel?
    private var cancellables = Set<AnyCancellable>()

    init(chatManager: AIChatHistoryManager,
         urlLoader: DuckAIURLSuggestionsLoader,
         chatViewModel: AIChatSuggestionsViewModel,
         queryProvider: @escaping () -> String,
         isAddressBarAtBottom: Bool) {
        self.chatManager = chatManager
        self.urlLoader = urlLoader
        self.chatViewModel = chatViewModel
        self.queryProvider = queryProvider
        self.isAddressBarAtBottom = isAddressBarAtBottom

        let pipeline = DuckAISuggestionsPipeline(
            chatsPublisher: chatViewModel.$filteredSuggestions.eraseToAnyPublisher(),
            urlsPublisher: urlLoader.$topURLs.eraseToAnyPublisher(),
            latestDispatchedQuery: queryProvider,
            lastCompletedURLQuery: { [weak urlLoader] in urlLoader?.lastCompletedFetchQuery ?? "" })
        self.source = DuckAISuggestionsSource(snapshotPublisher: pipeline.snapshotPublisher,
                                              query: queryProvider)
        self.listViewModel = SuggestionsListViewModel(source: source)
    }

    // MARK: - Container-facing surface (mirrors DuckAISuggestionsCoordinator)

    var hasContent: Bool {
        !chatViewModel.filteredSuggestions.isEmpty || !urlLoader.topURLs.isEmpty || !queryProvider().isEmpty
    }

    func hasSettled(forQuery query: String) -> Bool {
        urlLoader.lastCompletedFetchQuery == query && chatManager.lastCompletedQuery == query
    }

    func start<P: Publisher>(in containerView: UIView,
                             parentViewController: UIViewController,
                             textPublisher: P) where P.Output == String, P.Failure == Never {
        guard hostingController == nil else { return }

        chatManager.subscribeToTextChanges(textPublisher)
        urlLoader.subscribeToTextChanges(textPublisher)

        listViewModel.onSelect = { [weak self] id in self?.handleSelect(id) }
        listViewModel.onTapAhead = { [weak self] id in self?.handleSelect(id) }
        listViewModel.onDelete = { [weak self] id in self?.handleDelete(id) }

        chatViewModel.$filteredSuggestions
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onContentChanged?() }
            .store(in: &cancellables)
        urlLoader.$topURLs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onContentChanged?() }
            .store(in: &cancellables)

        let view = UnifiedSuggestionsView(
            viewModel: listViewModel,
            isAddressBarAtBottom: isAddressBarAtBottom,
            header: makeHeader())
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        parentViewController.addChild(hosting)
        containerView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hosting.view.bottomAnchor.constraint(lessThanOrEqualTo: containerView.safeAreaLayoutGuide.bottomAnchor)
        ])
        hosting.didMove(toParent: parentViewController)
        hostingController = hosting

        chatManager.refreshSuggestions(query: queryProvider())
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        escapeHatchModel = model
        rebuildRootView()
    }

    func setAdditionalTopInset(_ inset: CGFloat) {
        hostingController?.additionalSafeAreaInsets.top = inset
    }

    func tearDown() {
        cancellables.removeAll()
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
    }

    // MARK: - Private

    private func makeHeader() -> AnyView? {
        guard let escapeHatchModel else { return nil }
        return AnyView(EscapeHatchView(model: escapeHatchModel))
    }

    private func rebuildRootView() {
        guard let hosting = hostingController else { return }
        hosting.rootView = UnifiedSuggestionsView(
            viewModel: listViewModel,
            isAddressBarAtBottom: isAddressBarAtBottom,
            header: makeHeader())
    }

    private func handleSelect(_ id: String) {
        switch source.selection(forRowID: id) {
        case .chat(let chat): delegate?.duckAISuggestionsDidSelectChat(chat)
        case .url(let suggestion): delegate?.duckAISuggestionsDidSelectURL(suggestion)
        case .searchDuckDuckGo(let query): delegate?.duckAISuggestionsDidSelectSearchDuckDuckGo(query: query)
        case .none: break
        }
    }

    private func handleDelete(_ id: String) {
        // History deletion routes through the existing URL-suggestion delete path in Part 2b;
        // for now only SERP/history rows expose `.delete`, handled by the loader's own deletion.
        // No-op placeholder removed: route to delegate when the delete API lands in Part 2b.
        _ = id
    }
}
```

> Implementer note (IMPORTANT — verify before coding): this task references members that must exist on the injected types:
> - `DuckAIURLSuggestionsLoader.lastCompletedFetchQuery` (used in `hasSettled` and the pipeline). The spike found `lastCompletedFetchQuery` is set inside `fetch(query:)`; confirm it is accessible (not `private`). If it is `private`, expose it `private(set)` and note the change.
> - `AIChatHistoryManager.lastCompletedQuery` and `refreshSuggestions(query:)` and `subscribeToTextChanges(_:)`. Confirm exact names against `AIChatHistoryManager.swift`; the coordinator uses `chatManager.refreshSuggestions(...)` and `chatManager.subscribeToTextChanges(...)`. If `lastCompletedQuery` does not exist, derive "settled" from the existing `hasSettled` logic in `DuckAISuggestionsCoordinator` (port it). **If any of these are absent or differently named, STOP and report `NEEDS_CONTEXT` with the actual API — do not invent.**
> - `handleDelete` is intentionally inert for Part 2a (delete is a Part 2b concern once the search/history delete path is unified). Keep the row's `.delete` accessory rendering, but wiring deletion is out of scope here.

- [ ] **Step 2: Build + report any API mismatches**

`mcp__xcode__BuildProject`. If it fails on the members flagged above, report `NEEDS_CONTEXT` with the real signatures rather than guessing.

- [ ] **Step 3: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedDuckAISuggestionsHost.swift iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Add UnifiedDuckAISuggestionsHost (drop-in Duck.ai surface host)"
```

---

## Task 6: Flip `installDuckAISuggestions()` to the host + on-device verification

**Files:**
- Modify: `DuckDuckGo/UnifiedToggleInput/UnifiedInputContentContainerViewController.swift`

- [ ] **Step 1: Swap the install**

In `installDuckAISuggestions()` (around `UnifiedInputContentContainerViewController.swift:460-541`), replace the `DuckAISuggestionsCoordinator` construction + `swipeContainerManager.installDuckAISuggestions(using:textPublisher:)` with the host. Keep the surrounding fetcher construction (`chatViewModel`, `chatManager`, `urlLoader`) identical. Concretely:

```swift
let host = UnifiedDuckAISuggestionsHost(
    chatManager: chatManager,
    urlLoader: urlLoader,
    chatViewModel: chatViewModel,
    queryProvider: { [weak self] in self?.switchBarHandler.currentText ?? "" },
    isAddressBarAtBottom: switchBarHandler.isTopBarPosition == false)
host.delegate = self
host.onContentChanged = { [weak self] in
    self?.refreshVisibleContent(suggestionRefresh: .none, animateContentUpdates: true)
}
chatManager.onFetchCompleted = { [weak self] _, _ in
    self?.updateDaxVisibility()
}
host.start(in: swipeContainerManager.chatPageContainer,
           parentViewController: swipeContainerManager.containerViewController,
           textPublisher: switchBarHandler.currentTextPublisher)
host.setAdditionalTopInset(escapeHatchTopInset)
host.setEscapeHatch(switchBarHandler.isFireTab ? nil : escapeHatchModel)
duckAISuggestionsHost = host
updateDuckAISuggestionsActiveState()
```

Replace the stored `duckAISuggestionsCoordinator` property with `duckAISuggestionsHost: UnifiedDuckAISuggestionsHost?` and update every reference (`hasContent`, `hasSettled(forQuery:)`, `setEscapeHatch`, `setAdditionalTopInset`, `tearDown`, `viewDidDisappear`). These names are identical on the host, so the call sites change only in the type. Sync-promo: the host's header currently hosts only the escape hatch — **sync-promo placement is deferred to Part 2b** (see `.pr-followups.md`); if the existing code path passed `syncPromoManager`/`syncService` into the coordinator, leave those objects unused for now and add a `// Part 2b: sync promo` note at the call site.

> Implementer note: `swipeContainerManager.installDuckAISuggestions(using:textPublisher:)` becomes unused for this path but may still be referenced elsewhere — do NOT delete it in Part 2a. If the compiler flags the coordinator as entirely unused after the swap, leave the type in place (it's removed in Part 2b cleanup).

- [ ] **Step 2: Build**

`mcp__xcode__BuildProject`. Expected: success. Report any unresolved reference (esp. `chatPageContainer` / `containerViewController` visibility on `swipeContainerManager`) as `NEEDS_CONTEXT`.

- [ ] **Step 3: Run the full UTI + suggestions unit suites (regression)**

`RunSomeTests` (`UnitTests`) for: `SuggestionRowMapperTests`, `UnifiedSuggestionsContentResolverTests`, `DuckAISuggestionsPipelineTests`, `SuggestionsListViewModelTests`, `DuckAISuggestionsSelectionTests`, and `UnifiedToggleInputCoordinatorTests`. Expected: all pass.

- [ ] **Step 4: On-device verification (controller-driven; the user performs gestures)**

Build, install, launch, and stream logs via the multi-sim pipeline (`.sim-udid` = the worktree's claimed sim; tab `windowtab1`). Then ask the user to, with UTI ON, in Duck.ai mode:
  1. Focus the omnibar with no text → recents list shows (or Dax logo if no recents). Escape hatch present and positioned as before.
  2. Type a query → chats(filtered) + URL hits + "Search DuckDuckGo" row appear, in that order; tapping a row triggers the right action (open chat / open URL / search).
  3. Tap-ahead arrow on a phrase row inserts the suggestion without searching.
  4. Backspace to empty → returns to recents/logo without a flash.
  5. Switch to Search mode and back → no crash, content correct (Search side still uses the legacy path).
Compare side-by-side against a second simulator running the pre-swap build. Scan the streamed logs for constraint warnings (`Unable to simultaneously satisfy constraints`, `NSAutoresizingMaskLayoutConstraint`, layout-cycle) and report any.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputContentContainerViewController.swift iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Render Duck.ai suggestions via UnifiedSuggestionsView host"
```

---

## Part 2a completion

- [ ] Build green; all listed unit suites pass; on-device Duck.ai surface matches the legacy surface (parity confirmed by user); no new constraint warnings in logs.
- [ ] **Optional parity guard:** if `InlineSnapshotTesting`'s image strategy is available in `UnitTests`, add 2–3 inline snapshots of `SuggestionRowView` variants (website, bookmark-with-subtitle, phrase-with-tap-ahead). If only text-inline snapshots are available, skip — manual side-by-side stands.
- [ ] Hand off to **Part 2b** planning: search-typing (`AutocompleteView` reuse), favorites/NTP embed, wire the Part 1 `UnifiedSuggestionsContentResolver` aggregator at container level, move logo positioning into the unified layout (retire `toolbarCompensationOffset`), sync-promo placement, keyboard arrow-nav, history-row delete wiring, then retire `DuckAISuggestionsViewController` / `DuckAISuggestionsCoordinator` / dead `SwipeContainerManager` paths. Pull the open items from `.pr-followups.md`.
