//
//  SearchBookmarksBrowserToolTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class SearchBookmarksBrowserToolTests: XCTestCase {

    private let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: false)

    private func tree() -> [BaseBookmarkEntity] {
        let grand = bookmark("grand", "Grand Hotel", "https://guest:hunter2@grand.example/rooms?promo=secret#top", parent: "hotels")
        let hotels = BookmarkFolder(id: "hotels", title: "Hotels", parentFolderUUID: "disney", children: [grand])
        let parks = bookmark("parks", "Parks", "https://disney.example/@parks", parent: "disney")
        let disney = BookmarkFolder(id: "disney", title: "Disney", parentFolderUUID: "travel", children: [parks, hotels])
        let paris = bookmark("paris", "Louvre", "https://louvre.example", parent: "travel")
        let travel = BookmarkFolder(id: "travel", title: "Travel", children: [disney, paris])
        return [bookmark("news", "News", "https://news.example"), travel,
                bookmark("script", "Bookmarklet", "javascript:alert(1)")]
    }

    func testWhenNothingIsGivenThenWebBookmarksAreReturnedInTreeOrderWithTheirFolderAndNoQuery() async {
        let tool = make(tree())

        let result = await tool.execute(arguments: ["query": .null, "folder": .null, "limit": .null], context: context)

        XCTAssertEqual(result, .success(["results": [
            entry("News", "https://news.example", []),
            entry("Parks", "https://disney.example/@parks", ["Travel", "Disney"]),
            entry("Grand Hotel", "https://grand.example/rooms", ["Travel", "Disney", "Hotels"]),
            entry("Louvre", "https://louvre.example", ["Travel"])
        ]]))
    }

    func testWhenAFolderIsGivenThenOnlyItAndItsSubfoldersAreSearched() async {
        let tool = make(tree())

        let result = await tool.execute(arguments: ["folder": ["Travel", "Disney"], "limit": 50], context: context)

        XCTAssertEqual(result.titles, ["Parks", "Grand Hotel"])
    }

    func testWhenTheQueryMatchesAFolderNameThenItsBookmarksAreReturned() async {
        let tool = make(tree())

        let byFolder = await tool.execute(arguments: ["query": "disney"], context: context)
        let byQueryString = await tool.execute(arguments: ["query": "secret"], context: context)
        let byPassword = await tool.execute(arguments: ["query": "hunter2"], context: context)

        XCTAssertEqual(byFolder.titles, ["Parks", "Grand Hotel"])
        XCTAssertEqual(byQueryString.titles, [])
        XCTAssertEqual(byPassword.titles, [])
    }

    func testWhenTheFolderDoesNotExistThenThereAreNoResults() async {
        let tool = make(tree())

        let result = await tool.execute(arguments: ["folder": ["Travel", "Rome"]], context: context)

        XCTAssertEqual(result, .success(["results": []]))
    }

    func testWhenABookmarkIsDeeperThanTenFoldersThenItIsLeftOut() async {
        var entities: [BaseBookmarkEntity] = [bookmark("deep", "Deep", "https://deep.example", parent: "f11")]
        for level in (1...11).reversed() {
            entities = [BookmarkFolder(id: "f\(level)", title: "F\(level)", parentFolderUUID: level > 1 ? "f\(level - 1)" : nil, children: entities)]
        }
        entities.insert(bookmark("shallow", "Shallow", "https://shallow.example"), at: 0)
        let tool = make(entities)

        let result = await tool.execute(arguments: [:], context: context)

        XCTAssertEqual(result.titles, ["Shallow"])
    }

    func testWhenNoLimitIsGivenThenTenResultsAreReturned() async {
        let tool = make((0..<60).map { bookmark("b\($0)", "B\($0)", "https://b\($0).example") })

        let defaulted = await tool.execute(arguments: [:], context: context)
        let limited = await tool.execute(arguments: ["limit": 50], context: context)

        XCTAssertEqual(defaulted.titles?.count, 10)
        XCTAssertEqual(limited.titles?.count, 50)
    }

    func testWhenArgumentsAreMalformedThenTheyAreInvalid() async {
        let tool = make([])
        let tooLong = JSONValue.string(String(repeating: "a", count: BrowserToolOutputLimits.query + 1))

        for arguments: JSONValue in [["query": 1], ["query": tooLong], ["folder": []], ["folder": "Travel"], ["folder": [""]],
                                     ["limit": 0], ["limit": 51], ["limit": "5"]] {
            let result = await tool.execute(arguments: arguments, context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(arguments)")
        }
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let result = await make(tree()).execute(arguments: [:], context: BrowserToolCallContext(ownerTabID: "owner", isBurner: true))

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenDescribedThenItAsksForPermission() {
        let tool = make([])

        XCTAssertEqual(tool.name, "searchBookmarks")
        XCTAssertEqual(tool.permissionMode, .ask)
    }

    private func make(_ bookmarks: [BaseBookmarkEntity]) -> SearchBookmarksBrowserTool {
        let manager = LocalBookmarkManager(bookmarkStore: BookmarkStoreMock(bookmarks: bookmarks), foldersStore: BookmarkFolderStoreMock(), appearancePreferences: .mock)
        manager.loadBookmarks()
        return SearchBookmarksBrowserTool(bookmarkManager: manager)
    }

    private func bookmark(_ id: String, _ title: String, _ url: String, parent: String? = nil) -> Bookmark {
        Bookmark(id: id, url: url, title: title, isFavorite: false, parentFolderUUID: parent)
    }

    private func entry(_ title: String, _ url: String, _ folder: [String]) -> JSONValue {
        ["title": .string(title), "url": .string(url), "folder": .array(folder.map(JSONValue.string))]
    }
}

private extension BrowserToolResult {
    var titles: [String]? {
        guard case .success(let value) = self else { return nil }
        return value["results"]?.arrayValue?.compactMap { $0["title"]?.stringValue }
    }
}
