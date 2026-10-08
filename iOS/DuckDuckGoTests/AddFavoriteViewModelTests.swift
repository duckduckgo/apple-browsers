//
//  AddFavoriteViewModelTests.swift
//  DuckDuckGoTests
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
import XCTest
@testable import DuckDuckGo

@MainActor
final class AddFavoriteViewModelTests: XCTestCase {
    func testSchemeLessURLIsPreservedAndBlankNameUsesAddress() {
        let bookmarks = AddFavoriteBookmarksMock()
        let model = AddFavoriteViewModel(bookmarks: bookmarks)
        model.urlText = "  example.com  "
        model.name = "  "

        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.save())
        XCTAssertEqual(bookmarks.creations.count, 1)
        XCTAssertEqual(bookmarks.creations.first?.urlString, "example.com")
        XCTAssertEqual(bookmarks.creations.first?.title, "example.com")
    }

    func testExplicitSchemePathAndNameArePreserved() {
        let bookmarks = AddFavoriteBookmarksMock()
        let model = AddFavoriteViewModel(bookmarks: bookmarks)
        model.urlText = "http://example.com/page?q=one"
        model.name = "  My favorite  "

        XCTAssertTrue(model.save())
        XCTAssertEqual(bookmarks.creations.first?.urlString, "http://example.com/page?q=one")
        XCTAssertEqual(bookmarks.creations.first?.title, "My favorite")
    }

    func testInvalidOrBlankURLCannotSaveOrReportSuccess() {
        for input in ["", "   ", "http://[", "https://exa[mple.com"] {
            let bookmarks = AddFavoriteBookmarksMock()
            let model = AddFavoriteViewModel(bookmarks: bookmarks)
            model.urlText = input
            model.onSave = { XCTFail("Must not report an invalid favorite as saved") }

            XCTAssertFalse(model.canSave, input)
            XCTAssertFalse(model.save(), input)
            XCTAssertTrue(bookmarks.creations.isEmpty, input)
        }
    }

    func testRelativeURLsAndCustomSchemesMatchBookmarkEditor() {
        for input in ["-11", "hello", "ftp://example.com", "myapp://open/page"] {
            let bookmarks = AddFavoriteBookmarksMock()
            let model = AddFavoriteViewModel(bookmarks: bookmarks)
            model.urlText = input

            XCTAssertTrue(model.canSave, input)
            XCTAssertTrue(model.save(), input)
            XCTAssertEqual(bookmarks.creations.first?.urlString, input)
        }
    }

    func testBookmarkletIsSavedAsEntered() {
        for input in ["javascript:alert('Hello world')", "javascript:alert('Hello%20world')"] {
            let bookmarks = AddFavoriteBookmarksMock()
            let model = AddFavoriteViewModel(bookmarks: bookmarks)
            model.urlText = "  \(input)  \n"

            XCTAssertTrue(model.canSave)
            XCTAssertTrue(model.save())
            XCTAssertEqual(bookmarks.creations.first?.urlString, input)
        }
    }

    func testURLValidationUpdatesAfterEditingAndClearingTheAddress() {
        let bookmarks = AddFavoriteBookmarksMock()
        let model = AddFavoriteViewModel(bookmarks: bookmarks)

        model.urlText = "example.com"
        XCTAssertTrue(model.canSave)
        model.name = "Work"
        XCTAssertTrue(model.canSave)
        model.urlText = "http://["
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.save())
        model.urlText = "https://duckduckgo.com"
        XCTAssertTrue(model.canSave)
        model.urlText = ""
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.save())
        XCTAssertTrue(bookmarks.creations.isEmpty)
    }

    func testAddressWithPortIsSavedAsEntered() {
        let bookmarks = AddFavoriteBookmarksMock()
        let model = AddFavoriteViewModel(bookmarks: bookmarks)
        model.urlText = "example.com:8443/page"

        XCTAssertTrue(model.save())
        XCTAssertEqual(bookmarks.creations.first?.urlString, "example.com:8443/page")
    }

    func testInternationalDomainIsSavedAsEntered() {
        let bookmarks = AddFavoriteBookmarksMock()
        let model = AddFavoriteViewModel(bookmarks: bookmarks)
        model.urlText = "https://例子.测试/page"

        XCTAssertTrue(model.save())
        XCTAssertEqual(bookmarks.creations.first?.urlString, "https://例子.测试/page")
    }

    func testSaveCallbackRunsAfterEachSuccessfulSave() {
        let bookmarks = AddFavoriteBookmarksMock()
        let model = AddFavoriteViewModel(bookmarks: bookmarks)
        model.urlText = "example.com"
        var events: [String] = []
        bookmarks.onCreate = { events.append("create") }
        model.onSave = { events.append("saved") }

        XCTAssertTrue(model.save())
        XCTAssertEqual(events, ["create", "saved"])
        XCTAssertTrue(model.save())
        XCTAssertEqual(events, ["create", "saved", "create", "saved"])
    }

    func testFailedCreationDoesNotReportSuccess() {
        let bookmarks = AddFavoriteBookmarksMock()
        bookmarks.shouldCreate = false
        let model = AddFavoriteViewModel(bookmarks: bookmarks)
        model.urlText = "example.com"
        model.onSave = { XCTFail("Must not report a failed creation as saved") }

        XCTAssertFalse(model.save())
        XCTAssertEqual(bookmarks.creations.count, 1)
    }
}

private final class AddFavoriteBookmarksMock: MenuBookmarksInteracting {
    var favoritesDisplayMode: FavoritesDisplayMode = .displayNative(.mobile)
    var shouldCreate = true
    var creations: [(title: String, urlString: String)] = []
    var onCreate: (() -> Void)?

    func createOrToggleFavorite(title: String, url: URL) {
        XCTFail("Must save without toggling a favorite")
    }

    func saveFavorite(title: String?, urlString: String) -> Bool {
        creations.append((title ?? BookmarkUtils.url(from: urlString)?.host ?? urlString, urlString))
        onCreate?()
        return shouldCreate
    }

    func createBookmark(title: String, url: URL) {
        XCTFail("Must create a favorite rather than a plain bookmark")
    }

    func favorite(for url: URL) -> BookmarkEntity? { nil }

    func bookmark(for url: URL) -> BookmarkEntity? { nil }
}
