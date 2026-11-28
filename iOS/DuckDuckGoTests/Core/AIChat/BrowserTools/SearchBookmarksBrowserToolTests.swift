//
//  SearchBookmarksBrowserToolTests.swift
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

import AIChat
import Bookmarks
import Core
import CoreData
import FeatureFlags_iOS
import Persistence
import SitePermissions
import XCTest
@testable import DuckDuckGo

@MainActor
final class SearchBookmarksBrowserToolTests: XCTestCase {
    private var database: CoreDataDatabase!

    override func setUpWithError() throws {
        try super.setUpWithError()
        database = MockBookmarksDatabase.make()
    }

    override func tearDownWithError() throws {
        defer { database = nil }
        try database.tearDown(deleteStores: true)
        try super.tearDownWithError()
    }

    func testFolderSearchReturnsNestedBookmarksInStoredOrderAndRedactsURLs() async throws {
        try saveBookmarks { context, root in
            let travel = BookmarkEntity.makeFolder(title: "Travel", parent: root, context: context)
            let japan = BookmarkEntity.makeFolder(title: "Japan", parent: travel, context: context)
            let kansai = BookmarkEntity.makeFolder(title: "Kansai", parent: japan, context: context)
            _ = BookmarkEntity.makeBookmark(title: "Osaka", url: "https://en.wikipedia.org/wiki/Osaka", parent: kansai, context: context)
            _ = BookmarkEntity.makeBookmark(title: "Kyoto", url: "https://en.wikipedia.org/wiki/Kyoto?test=manual#History",
                                            parent: japan, context: context)
            _ = BookmarkEntity.makeBookmark(title: "Japan exhibit in Paris", url: "https://example.com/japan", parent: travel, context: context)
        }
        let (tool, context) = makeTool()

        let result = await tool.execute(arguments: ["folder": ["Travel", "Japan"], "query": "jApAn"], context: context)

        XCTAssertEqual(result, .success(["results": [
            ["title": "Osaka", "url": "https://en.wikipedia.org/wiki/Osaka", "folder": ["Travel", "Japan", "Kansai"]],
            ["title": "Kyoto", "url": "https://en.wikipedia.org/wiki/Kyoto", "folder": ["Travel", "Japan"]]
        ]]))
    }

    func testRootSearchIncludesVisibleOrphanWithoutTitleAndSkipsSyncStubs() async throws {
        try saveBookmarks { context, root in
            _ = BookmarkEntity.makeBookmark(title: "Kyoto", url: "https://en.wikipedia.org/wiki/Kyoto", parent: root, context: context)
            let orphan = BookmarkEntity(context: context)
            orphan.isFolder = false
            orphan.url = "https://osaka.example/guide"
            let stub = BookmarkEntity(context: context)
            stub.isFolder = false
            stub.title = "Unfinished bookmark"
            stub.url = "https://stub.example"
            stub.isStub = true
        }
        let (tool, context) = makeTool()

        let result = await tool.execute(arguments: [:], context: context)

        XCTAssertEqual(result, .success(["results": [
            ["title": "Kyoto", "url": "https://en.wikipedia.org/wiki/Kyoto", "folder": []],
            ["title": "osaka.example", "url": "https://osaka.example/guide", "folder": []]
        ]]))
    }

    func testSearchExcludesHTTPHostlessAddressesAndDuckAIChats() async throws {
        try saveBookmarks { context, root in
            let bookmarks = [
                ("HTTP", "http://en.wikipedia.org/wiki/Kyoto"),
                ("Hostless", "https:/wiki/Kyoto"),
                ("Duck.ai", "https://duck.ai/?chatID=test"),
                ("Duck.ai on DuckDuckGo", "https://duckduckgo.com/?ia=chat"),
                ("Kyoto", "https://en.wikipedia.org/wiki/Kyoto")
            ]
            for (title, url) in bookmarks {
                _ = BookmarkEntity.makeBookmark(title: title, url: url, parent: root, context: context)
            }
        }
        let (tool, context) = makeTool()

        let result = await tool.execute(arguments: [:], context: context)

        XCTAssertEqual(result, .success(["results": [
            ["title": "Kyoto", "url": "https://en.wikipedia.org/wiki/Kyoto", "folder": []]
        ]]))
    }

    func testSearchDiscardsResultsWhenOwnerScopeChangesDuringRead() async throws {
        try saveBookmarks { context, root in
            _ = BookmarkEntity.makeBookmark(title: "Kyoto", url: "https://en.wikipedia.org/wiki/Kyoto", parent: root, context: context)
        }
        let owner = makeOwner()
        let originalScope = makeScope(for: owner)
        let replacementScope = makeScope(for: owner)
        let context = callContext(for: originalScope)
        XCTAssertTrue(originalScope.accepts(context))
        var currentScope = originalScope
        let tool = SearchBookmarksBrowserTool(bookmarksDatabase: database) { _ in
            defer { currentScope = replacementScope }
            return currentScope
        }

        let result = await tool.execute(arguments: [:], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testCatalogUsesIndependentSearchBookmarksFlag() throws {
        let flags = MockFeatureFlagger()
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AIChatBrowserToolsService(featureFlagger: flags, historyManager: MockHistoryManager(),
                                               bookmarksDatabase: database,
                                               sitePermissionsStore: SitePermissionsStore(storage: defaults.keyedStoring()))
        let states: [([FeatureFlag], [ClientToolCapability])] = [
            ([.aiChatBrowserTools, .aiChatBrowserToolSearchHistory], [.searchHistory]),
            ([.aiChatBrowserTools, .aiChatBrowserToolSearchBookmarks], [.searchBookmarks]),
            ([.aiChatBrowserToolSearchBookmarks], []),
            ([.aiChatBrowserTools], [])
        ]

        for (enabledFlags, capabilities) in states {
            flags.enabledFeatureFlags = enabledFlags
            XCTAssertEqual(service.clientToolsConfiguration?.capabilities ?? [], capabilities)
            XCTAssertEqual(service.catalog.tool(for: .searchBookmarks) != nil, capabilities.contains(.searchBookmarks))
        }
    }

    private func saveBookmarks(_ populate: (NSManagedObjectContext, BookmarkEntity) -> Void) throws {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = try XCTUnwrap(BookmarkUtils.fetchRootFolder(context))
        populate(context, root)
        try context.save()
    }

    private func makeTool() -> (SearchBookmarksBrowserTool, BrowserToolCallContext) {
        let scope = makeScope(for: makeOwner())
        let tool = SearchBookmarksBrowserTool(bookmarksDatabase: database) { _ in scope }
        return (tool, callContext(for: scope))
    }

    private func makeOwner() -> Tab {
        Tab(uid: "owner", link: Link(title: "Owner", url: URL(string: "https://owner.example")!), fireTab: false)
    }

    private func makeScope(for owner: Tab) -> BrowserToolScope {
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner] })
        return BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid })
    }

    private func callContext(for scope: BrowserToolScope) -> BrowserToolCallContext {
        BrowserToolCallContext(ownerTabID: scope.ownerTabID, ownerWindowToken: scope.token, isBurner: false)
    }
}
