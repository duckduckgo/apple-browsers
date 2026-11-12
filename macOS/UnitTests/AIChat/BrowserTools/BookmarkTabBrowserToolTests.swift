//
//  BookmarkTabBrowserToolTests.swift
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

import AIChat
import Bookmarks
import SharedTestUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarkTabBrowserToolTests: XCTestCase {

    private let pageURL = "https://example.com/page"
    private var tabs: [Tab] = []

    override func tearDown() {
        tabs = []
        super.tearDown()
    }

    func testWhenNoFolderIsGivenThenTheCurrentTabIsBookmarkedAtTheTopLevel() async {
        let (tool, context, manager, owner) = make()

        let result = await tool.execute(arguments: ["tabId": .null, "folder": .null], context: context)

        XCTAssertEqual(result, .success(response(tabID: owner, alreadyBookmarked: false, folderCreated: false)))
        let bookmark = manager.getBookmark(forUrl: pageURL)
        XCTAssertNotNil(bookmark)
        XCTAssertNil(bookmark?.parentFolderUUID)
    }

    func testWhenPartOfTheFolderPathIsMissingThenItIsCreatedUnderTheExistingFolder() async {
        let travel = BookmarkFolder(id: "travel", title: "Travel")
        let (tool, context, manager, owner) = make(bookmarks: [travel])

        let result = await tool.execute(arguments: ["folder": ["Travel", "Par/is"]], context: context)

        XCTAssertEqual(result, .success(response(tabID: owner, alreadyBookmarked: false, folderCreated: true)))
        let paris = manager.list?.topLevelEntities.first { $0.title == "Par/is" } as? BookmarkFolder
        XCTAssertEqual(paris?.parentFolderUUID, travel.id)
        XCTAssertEqual(manager.getBookmark(forUrl: pageURL)?.parentFolderUUID, paris?.id)
    }

    func testWhenThePageIsAlreadyInTheFolderThenNothingIsSaved() async {
        let saved = Bookmark(id: "saved", url: pageURL, title: "Page", isFavorite: false, parentFolderUUID: "travel")
        let travel = BookmarkFolder(id: "travel", title: "Travel", children: [saved])
        let (tool, context, _, owner, store) = makeWithStore(bookmarks: [travel])

        let result = await tool.execute(arguments: ["folder": ["Travel"]], context: context)

        XCTAssertEqual(result, .success(response(tabID: owner, alreadyBookmarked: true, folderCreated: false)))
        XCTAssertNil(store.saveEntitiesAtIndicesCalledWith)
        XCTAssertFalse(store.moveObjectUUIDCalled)
    }

    func testWhenThePageIsBookmarkedElsewhereThenItIsMovedIntoTheNamedFolder() async {
        let saved = Bookmark(id: "saved", url: pageURL, title: "Page", isFavorite: false)
        let travel = BookmarkFolder(id: "travel", title: "Travel")
        let (tool, context, _, owner, store) = makeWithStore(bookmarks: [saved, travel])

        let result = await tool.execute(arguments: ["folder": ["Travel"]], context: context)

        XCTAssertEqual(result, .success(response(tabID: owner, alreadyBookmarked: true, folderCreated: false)))
        XCTAssertEqual(store.capturedObjectUUIDs, ["saved"])
        XCTAssertEqual(store.capturedParentFolderType, .parent(uuid: "travel"))
    }

    func testWhenNoFolderIsGivenThenABookmarkInAFolderStaysThere() async {
        let saved = Bookmark(id: "saved", url: pageURL, title: "Page", isFavorite: false, parentFolderUUID: "travel")
        let travel = BookmarkFolder(id: "travel", title: "Travel", children: [saved])
        let (tool, context, _, owner, store) = makeWithStore(bookmarks: [travel])

        let result = await tool.execute(arguments: [:], context: context)

        XCTAssertEqual(result, .success(response(tabID: owner, alreadyBookmarked: true, folderCreated: false)))
        XCTAssertFalse(store.moveObjectUUIDCalled)
    }

    func testWhenAVariantOfThePageIsBookmarkedThenNoSecondBookmarkIsMade() async {
        let saved = Bookmark(id: "saved", url: "http://example.com/page/", title: "Page", isFavorite: false)
        let (tool, context, manager, owner, store) = makeWithStore(bookmarks: [saved])

        let result = await tool.execute(arguments: [:], context: context)

        XCTAssertEqual(result, .success(response(tabID: owner, alreadyBookmarked: true, folderCreated: false)))
        XCTAssertNil(manager.getBookmark(forUrl: pageURL))
        XCTAssertNil(store.saveEntitiesAtIndicesCalledWith)
    }

    func testWhenTwoCallsNameTheSameNewFolderThenItIsCreatedOnce() async throws {
        let container = CoreData.bookmarkContainer()
        let database = container.newBackgroundContext()
        database.performAndWait { BookmarkUtils.prepareFoldersStructure(in: database) }
        let manager = LocalBookmarkManager(bookmarkStore: BookmarkStoreMock(contextProvider: { database }),
                                           foldersStore: BookmarkFolderStoreMock(), appearancePreferences: .mock)
        manager.loadBookmarks()
        try await waitUntil { manager.list != nil }
        let otherURL = "https://example.com/other"
        let (tool, context, _) = makeTool(manager: manager, extraTabURLs: [otherURL])

        async let first = tool.execute(arguments: ["folder": ["Trips"]], context: context)
        async let second = tool.execute(arguments: ["tabId": JSONValue.string(tabs[1].uuid), "folder": ["Trips"]], context: context)
        _ = await (first, second)
        var trips: [BaseBookmarkEntity] { manager.list?.topLevelEntities.filter { $0.title == "Trips" } ?? [] }
        try await waitUntil {
            let parents = [pageURL, otherURL].map { manager.getBookmark(forUrl: $0)?.parentFolderUUID }
            return parents.allSatisfy { parent in trips.contains { $0.id == parent } }
        }

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(manager.getBookmark(forUrl: pageURL)?.parentFolderUUID, trips.first?.id)
        XCTAssertEqual(manager.getBookmark(forUrl: otherURL)?.parentFolderUUID, trips.first?.id)
    }

    func testWhenAQueuedCallIsCancelledThenItSavesNothing() async throws {
        let saved = Bookmark(id: "saved", url: pageURL, title: "Page", isFavorite: false)
        let travel = BookmarkFolder(id: "travel", title: "Travel")
        let otherURL = "https://example.com/other"
        let (tool, context, manager, _, store) = makeWithStore(bookmarks: [saved, travel], extraTabURLs: [otherURL])
        store.defersMoveCompletions = true

        let first = Task { await tool.execute(arguments: ["folder": ["Travel"]], context: context) }
        try await waitUntil { store.deferredMoveCompletionCount == 1 }
        let second = Task { await tool.execute(arguments: ["tabId": JSONValue.string(tabs[1].uuid)], context: context) }
        await Task.yield()
        second.cancel()
        store.completeNextMove()
        _ = await first.value

        let result = await second.value
        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertNil(manager.getBookmark(forUrl: otherURL))
    }

    func testWhenTheFolderIsMalformedThenArgumentsAreInvalid() async {
        let (tool, context, manager, _) = make()
        let tooDeep = JSONValue.array(Array(repeating: "a", count: BookmarkTabBrowserTool.maxFolderDepth + 1))
        let tooLong = JSONValue.string(String(repeating: "a", count: BookmarkTabBrowserTool.maxFolderNameLength + 1))

        for folder: JSONValue in [[], "Travel", [1], [""], tooDeep, .array([tooLong])] {
            let result = await tool.execute(arguments: ["folder": folder], context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(folder)")
        }
        XCTAssertNil(manager.getBookmark(forUrl: pageURL))
    }

    func testWhenTheTabIdIsUnknownThenItIsNotFound() async {
        let (tool, context, _, _) = make()

        let result = await tool.execute(arguments: ["tabId": "missing"], context: context)

        XCTAssertEqual(result, .failure(.notFound))
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let (tool, context, manager, owner) = make()
        let fireContext = BrowserToolCallContext(ownerTabID: owner, ownerWindowToken: context.ownerWindowToken, isBurner: true)

        let result = await tool.execute(arguments: nil, context: fireContext)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertNil(manager.getBookmark(forUrl: pageURL))
    }

    private func response(tabID: String, alreadyBookmarked: Bool, folderCreated: Bool) -> JSONValue {
        ["tabId": .string(tabID), "alreadyBookmarked": .bool(alreadyBookmarked), "folderCreated": .bool(folderCreated)]
    }

    private func make(bookmarks: [BaseBookmarkEntity] = []) -> (BookmarkTabBrowserTool, BrowserToolCallContext, LocalBookmarkManager, String) {
        let (tool, context, manager, owner, _) = makeWithStore(bookmarks: bookmarks)
        return (tool, context, manager, owner)
    }

    private func makeWithStore(bookmarks: [BaseBookmarkEntity],
                               extraTabURLs: [String] = []) -> (BookmarkTabBrowserTool, BrowserToolCallContext, LocalBookmarkManager, String, BookmarkStoreMock) {
        let store = BookmarkStoreMock(bookmarks: bookmarks)
        store.completesMoveCompletions = true
        let manager = LocalBookmarkManager(bookmarkStore: store, foldersStore: BookmarkFolderStoreMock(), appearancePreferences: .mock)
        manager.loadBookmarks()
        let (tool, context, owner) = makeTool(manager: manager, extraTabURLs: extraTabURLs)
        return (tool, context, manager, owner, store)
    }

    private func makeTool(manager: LocalBookmarkManager, extraTabURLs: [String] = []) -> (BookmarkTabBrowserTool, BrowserToolCallContext, String) {
        tabs = ([pageURL] + extraTabURLs).map { Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui)) }
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs), pinnedTabsManagerProvider: nil)
        let windows = WindowControllersManagerMock()
        windows.customAllTabCollectionViewModels = [collection]
        let owner = tabs[0].uuid
        let context = BrowserToolCallContext(ownerTabID: owner,
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: false)
        return (BookmarkTabBrowserTool(windowControllersManager: windows, bookmarkManager: manager), context, owner)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
