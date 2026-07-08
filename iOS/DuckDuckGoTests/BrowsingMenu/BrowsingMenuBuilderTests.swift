//
//  BrowsingMenuBuilderTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Bookmarks
import PersistenceTestingUtils
import UIKit
import XCTest
@testable import DuckDuckGo

final class BrowsingMenuBuilderTests: XCTestCase {

    func testNewTabPageMenuOmitsChatsWhenFallbackChatsEntryIsUnavailable() {
        let entryBuilder = MockBrowsingMenuEntryBuilder(chatsEntry: nil)
        let model = makeBuilder(entryBuilder: entryBuilder).buildMenu(
            context: .newTabPage,
            bookmarksInterface: MockMenuBookmarksInteractor(),
            mobileCustomization: makeMobileCustomization(),
            clearTabsAndData: {}
        )

        XCTAssertEqual(model?.sections.first?.items.map(\.name), [
            MockBrowsingMenuEntryBuilder.openBookmarksName,
            MockBrowsingMenuEntryBuilder.downloadsName
        ])
    }

    func testNewTabPageMenuPlacesFallbackChatsAfterBookmarksAndDownloads() {
        let entryBuilder = MockBrowsingMenuEntryBuilder(chatsEntry: .named(MockBrowsingMenuEntryBuilder.chatsName))
        let model = makeBuilder(entryBuilder: entryBuilder).buildMenu(
            context: .newTabPage,
            bookmarksInterface: MockMenuBookmarksInteractor(),
            mobileCustomization: makeMobileCustomization(),
            clearTabsAndData: {}
        )

        XCTAssertEqual(model?.sections.first?.items.map(\.name), [
            MockBrowsingMenuEntryBuilder.openBookmarksName,
            MockBrowsingMenuEntryBuilder.downloadsName,
            MockBrowsingMenuEntryBuilder.chatsName
        ])
    }

    func testWebsiteMenuPlacesFallbackChatsAfterBookmarksAndDownloads() {
        let entryBuilder = MockBrowsingMenuEntryBuilder(chatsEntry: .named(MockBrowsingMenuEntryBuilder.chatsName))
        let model = makeBuilder(entryBuilder: entryBuilder).buildMenu(
            context: .website,
            bookmarksInterface: MockMenuBookmarksInteractor(),
            mobileCustomization: makeMobileCustomization(),
            clearTabsAndData: {}
        )

        XCTAssertEqual(model?.sections.first?.items.map(\.name), [
            MockBrowsingMenuEntryBuilder.openBookmarksName,
            MockBrowsingMenuEntryBuilder.downloadsName,
            MockBrowsingMenuEntryBuilder.chatsName
        ])
    }

    private func makeBuilder(entryBuilder: BrowsingMenuEntryBuilding) -> BrowsingMenuBuilder {
        BrowsingMenuBuilder(entryBuilder: entryBuilder)
    }

    private func makeMobileCustomization() -> MobileCustomization {
        MobileCustomization(keyValueStore: MockKeyValueStore(), isPad: false)
    }
}

private final class MockBrowsingMenuEntryBuilder: BrowsingMenuEntryBuilding {

    static let chatsName = "Chats"
    static let downloadsName = "Downloads"
    static let openBookmarksName = "Bookmarks"

    private let chatsEntry: BrowsingMenuEntry?

    init(chatsEntry: BrowsingMenuEntry?) {
        self.chatsEntry = chatsEntry
    }

    func makeShortcutsMenu() -> [BrowsingMenuEntry] { [] }
    func makeAITabMenu() -> [BrowsingMenuEntry] { [] }
    func makeAITabMenuHeaderContent() -> [BrowsingMenuEntry] { [] }
    func makeBrowsingMenu(with bookmarksInterface: MenuBookmarksInteracting,
                          mobileCustomization: MobileCustomization,
                          clearTabsAndData: @escaping () -> Void) -> [BrowsingMenuEntry] { [] }
    func makeBrowsingMenuHeaderContent() -> [BrowsingMenuEntry] { [] }
    func makeNewTabEntry() -> BrowsingMenuEntry { .named("New Tab") }
    func makeChatEntry() -> BrowsingMenuEntry? { nil }
    func makeDuckAiChatsEntry() -> BrowsingMenuEntry? { chatsEntry }
    func makeDuckAIMenuItems() -> [BrowsingMenuEntry] { [] }
    func makeSettingsEntry() -> BrowsingMenuEntry { .named("Settings") }
    func makeShareEntry() -> BrowsingMenuEntry { .named("Share") }
    func makePrintEntry() -> BrowsingMenuEntry { .named("Print") }
    func makeDownloadsEntry() -> BrowsingMenuEntry { .named(Self.downloadsName) }
    func makeAutoFillEntry() -> BrowsingMenuEntry? { nil }
    func makeVPNEntry() -> BrowsingMenuEntry? { nil }
    func makeOpenBookmarksEntry() -> BrowsingMenuEntry { .named(Self.openBookmarksName) }
    func makeBookmarkEntries(with bookmarksInterface: MenuBookmarksInteracting) -> (bookmark: BrowsingMenuEntry, favorite: BrowsingMenuEntry)? { nil }
    func makeFindInPageEntry() -> BrowsingMenuEntry? { nil }
    func makeZoomEntry() -> BrowsingMenuEntry? { nil }
    func makeDesktopSiteEntry() -> BrowsingMenuEntry? { nil }
    func makeReloadEntry() -> BrowsingMenuEntry? { nil }
    func makeToggleProtectionEntry() -> BrowsingMenuEntry? { nil }
    func makeReportBrokenSiteEntry() -> BrowsingMenuEntry? { nil }
    func makeClearDataEntry(mobileCustomization: MobileCustomization, clearTabsAndData: @escaping () -> Void) -> BrowsingMenuEntry? { nil }
    func makeUseNewDuckAddressEntry() -> BrowsingMenuEntry? { nil }
    func makeKeepSignInEntry() -> BrowsingMenuEntry? { nil }
    func makeYouTubeAdBlockToggleEntry() -> BrowsingMenuEntry? { nil }
}

private final class MockMenuBookmarksInteractor: MenuBookmarksInteracting {

    var favoritesDisplayMode: FavoritesDisplayMode = .displayNative(.mobile)

    func createOrToggleFavorite(title: String, url: URL) {}
    func createBookmark(title: String, url: URL) {}
    func favorite(for url: URL) -> BookmarkEntity? { nil }
    func bookmark(for url: URL) -> BookmarkEntity? { nil }
}

private extension BrowsingMenuEntry {

    static func named(_ name: String) -> BrowsingMenuEntry {
        .regular(name: name, image: UIImage(), action: {})
    }
}
