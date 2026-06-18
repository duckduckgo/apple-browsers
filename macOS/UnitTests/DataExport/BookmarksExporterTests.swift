//
//  BookmarksExporterTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Foundation
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class BookmarksExporterTests: XCTestCase {

    struct TestData {
        static let exampleUrl = URL(string: "https://example.com")!
        static let exampleTitle = "Example"

        static let otherUrl = URL(string: "https://other.com")!
        static let otherTitle = "Other"

        static let titleWithUnescapedHTMLEntities = "< > &"
        static let titleWithEscapedHTMLEntities = "&lt; &gt; &amp;"

        static let folderName1 = "TestFolder1"
        static let folderName2 = "TestFolder2"
        static let folderName3 = "TestFolder3"
        static let folderName4 = "TestFolder4"
    }

    let tmpFile: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html", isDirectory: false)

    func test_WhenBookmarkIsNestedDeeply_ThenFileContainsFolderNestingAndBookmark() throws {
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            BookmarkFolder(id: UUID().uuidString, title: TestData.folderName1, children: [
                BookmarkFolder(id: UUID().uuidString, title: TestData.folderName2, children: [
                    BookmarkFolder(id: UUID().uuidString, title: TestData.folderName3, children: [
                        BookmarkFolder(id: UUID().uuidString, title: TestData.folderName4, children: [
                            Bookmark(id: UUID().uuidString, url: TestData.exampleUrl.absoluteString, title: TestData.exampleTitle, isFavorite: false)
                        ])
                    ])
                ])
            ])
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.openFolder(level: 1, named: TestData.folderName1),
                BookmarksExporter.Template.openFolder(level: 2, named: TestData.folderName2),
                    BookmarksExporter.Template.openFolder(level: 3, named: TestData.folderName3),
                        BookmarksExporter.Template.openFolder(level: 4, named: TestData.folderName4),
            BookmarksExporter.Template.bookmark(level: 5, title: TestData.exampleTitle, url: TestData.exampleUrl.absoluteString),
                        BookmarksExporter.Template.closeFolder(level: 4),
                    BookmarksExporter.Template.closeFolder(level: 3),
                BookmarksExporter.Template.closeFolder(level: 2),
            BookmarksExporter.Template.closeFolder(level: 1),
            BookmarksExporter.Template.footer
        ].joined())

    }

    func test_WhenFolderContainsAFolder_TheFileContainsTheNestedFolder() throws {
        let folder = BookmarkFolder(id: UUID().uuidString, title: TestData.folderName1, children: [
            Bookmark(id: UUID().uuidString, url: TestData.exampleUrl.absoluteString, title: TestData.exampleTitle, isFavorite: false),
            BookmarkFolder(id: UUID().uuidString, title: TestData.folderName2)
        ])

        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            folder
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.openFolder(level: 1, named: TestData.folderName1),
            BookmarksExporter.Template.bookmark(level: 2, title: TestData.exampleTitle, url: TestData.exampleUrl.absoluteString),
                BookmarksExporter.Template.openFolder(level: 2, named: TestData.folderName2),
                BookmarksExporter.Template.closeFolder(level: 2),
            BookmarksExporter.Template.closeFolder(level: 1),
            BookmarksExporter.Template.footer
        ].joined())

    }

    func test_WhenFolderContainsMultipleBookmarks_TheFileContainsThatFolderWithTheBookmarks() throws {
        let folder = BookmarkFolder(id: UUID().uuidString, title: TestData.folderName1, children: [
            Bookmark(id: UUID().uuidString, url: TestData.exampleUrl.absoluteString, title: TestData.exampleTitle, isFavorite: false),
            Bookmark(id: UUID().uuidString, url: TestData.otherUrl.absoluteString, title: TestData.otherTitle, isFavorite: true)
        ])

        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            folder
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.openFolder(level: 1, named: TestData.folderName1),
            BookmarksExporter.Template.bookmark(level: 2, title: TestData.exampleTitle, url: TestData.exampleUrl.absoluteString),
            BookmarksExporter.Template.bookmark(level: 2, title: TestData.otherTitle, url: TestData.otherUrl.absoluteString, isFavorite: true),
            BookmarksExporter.Template.closeFolder(level: 1),
            BookmarksExporter.Template.footer
        ].joined())

    }

    func test_WhenFolderContainsABookmark_TheFileContainsThatFolderWithTheBookmark() throws {
        let folder = BookmarkFolder(id: UUID().uuidString, title: TestData.folderName1, children: [
            Bookmark(id: UUID().uuidString, url: TestData.exampleUrl.absoluteString, title: TestData.exampleTitle, isFavorite: false)
        ])

        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            folder
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.openFolder(level: 1, named: TestData.folderName1),
            BookmarksExporter.Template.bookmark(level: 2, title: TestData.exampleTitle, url: TestData.exampleUrl.absoluteString),
            BookmarksExporter.Template.closeFolder(level: 1),
            BookmarksExporter.Template.footer
        ].joined())

    }

    func test_WhenMultipleFoldersAtTopLevel_ThenFileContainsFolders() throws {
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            BookmarkFolder(id: UUID().uuidString, title: TestData.folderName1),
            BookmarkFolder(id: UUID().uuidString, title: TestData.folderName2)
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.openFolder(level: 1, named: TestData.folderName1),
            BookmarksExporter.Template.closeFolder(level: 1),
            BookmarksExporter.Template.openFolder(level: 1, named: TestData.folderName2),
            BookmarksExporter.Template.closeFolder(level: 1),
            BookmarksExporter.Template.footer
        ].joined())
    }

    func test_WhenFolderAtTopLevel_ThenFileContainsFolder() throws {
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            BookmarkFolder(id: UUID().uuidString, title: TestData.folderName1)
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.openFolder(level: 1, named: TestData.folderName1),
            BookmarksExporter.Template.closeFolder(level: 1),
            BookmarksExporter.Template.footer
        ].joined())
    }

    func test_WhenBookmarkAtTopLevelIsFavorite_ThenFileContainsBookmarkAtTopLevelWithFavoriteAttribute() throws {
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            Bookmark(id: UUID().uuidString, url: TestData.exampleUrl.absoluteString, title: TestData.exampleTitle, isFavorite: true)
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.bookmark(level: 1, title: TestData.exampleTitle, url: TestData.exampleUrl.absoluteString, isFavorite: true),
            BookmarksExporter.Template.footer
        ].joined())
    }

    func test_WhenTemplateInvokedWithFavorite_ThenFavoriteAttributeAdded() throws {
        let snippet = BookmarksExporter.Template.bookmark(level: 1, title: TestData.exampleTitle, url: TestData.exampleUrl.absoluteString, isFavorite: true)
        XCTAssertTrue(snippet.contains(" duckduckgo:favorite=\"true\""))
    }

    func test_WhenMultipleBookmarksAtTopLevel_ThenFileContainsAllBookmarksAtTopLevel() throws {
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            Bookmark(id: UUID().uuidString, url: TestData.exampleUrl.absoluteString, title: TestData.exampleTitle, isFavorite: false),
            Bookmark(id: UUID().uuidString, url: TestData.otherUrl.absoluteString, title: TestData.otherTitle, isFavorite: false)
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.bookmark(level: 1, title: TestData.exampleTitle, url: TestData.exampleUrl.absoluteString),
            BookmarksExporter.Template.bookmark(level: 1, title: TestData.otherTitle, url: TestData.otherUrl.absoluteString),
            BookmarksExporter.Template.footer
        ].joined())
    }

    func test_WhenBookmarkTitleHasHTMLEntities_ThenTheExportedTitleIsEscaped() throws {
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            Bookmark(id: UUID().uuidString, url: TestData.exampleUrl.absoluteString, title: TestData.titleWithUnescapedHTMLEntities, isFavorite: false)
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.bookmark(level: 1, title: TestData.titleWithEscapedHTMLEntities, url: TestData.exampleUrl.absoluteString),
            BookmarksExporter.Template.footer
        ].joined())
    }

    func test_WhenBookmarkAtTopLevel_ThenFileContainsBookmarkAtTopLevel() throws {
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            Bookmark(id: UUID().uuidString, url: TestData.exampleUrl.absoluteString, title: TestData.exampleTitle, isFavorite: false)
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.bookmark(level: 1, title: TestData.exampleTitle, url: TestData.exampleUrl.absoluteString),
            BookmarksExporter.Template.footer
        ].joined())
    }

    func test_WhenNoBookmarks_ThenFileContainsOnlyHeaderAndFooter() throws {
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: []))
        try exporter.exportBookmarksTo(url: tmpFile)
        assertExportedFileEquals([
            BookmarksExporter.Template.header,
            BookmarksExporter.Template.footer
        ].joined())
    }

    // #3 — Folder names are written into the exported HTML raw, while bookmark titles are escaped.
    // A folder named with HTML metacharacters (e.g. "News & Politics", or one containing `<`/`>`)
    // produces malformed HTML, so that folder's subtree is mis-parsed / lost on re-import.
    func test_WhenFolderNameHasHTMLEntities_ThenTheExportedFolderNameIsEscaped() throws {
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            BookmarkFolder(id: UUID().uuidString, title: TestData.titleWithUnescapedHTMLEntities)
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)

        let actual = try XCTUnwrap(try? String(contentsOf: tmpFile))
        XCTAssertTrue(actual.contains("<DT><H3 FOLDED>\(TestData.titleWithEscapedHTMLEntities)</H3>"),
                      "Folder name was not HTML-escaped on export; re-import will mis-parse the folder. Exported:\n\(actual)")
        XCTAssertFalse(actual.contains("<DT><H3 FOLDED>\(TestData.titleWithUnescapedHTMLEntities)</H3>"),
                       "Folder name was written with raw HTML metacharacters")
    }

    // Cross-importer round-trip: parse the exported HTML with Foundation's generic tidy-HTML parser
    // (the same loose-HTML reading other browsers use to import the Netscape bookmark format) and
    // confirm the folder name survives. The `<feed>` is the data-loss case: `<` followed by a letter
    // is read as a tag and silently dropped unless escaped, so without the fix the name comes back as
    // "News & Politics " — proving the escaping prevents real, user-visible data loss on import.
    func test_ExportedFolderNameIsRecoverableByAGenericHTMLParser() throws {
        let folderName = "News & Politics <feed>"
        let exporter = BookmarksExporter(list: BookmarkList(entities: [], topLevelEntities: [
            BookmarkFolder(id: UUID().uuidString, title: folderName, children: [
                Bookmark(id: UUID().uuidString, url: TestData.exampleUrl.absoluteString, title: TestData.exampleTitle, isFavorite: false)
            ])
        ]))

        try exporter.exportBookmarksTo(url: tmpFile)

        let document = try XMLDocument(contentsOf: tmpFile, options: [.documentTidyHTML])
        let folderNames = try document.nodes(forXPath: "//h3")
            .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertTrue(folderNames.contains(folderName),
                      "A generic HTML parser did not recover the folder name. Got: \(folderNames)")
    }

    private func assertExportedFileEquals(_ expected: String, _ file: StaticString = #file, _ line: UInt = #line) {
        let actual = try? String(contentsOf: tmpFile)
        XCTAssertEqual(expected, actual, file: file, line: line)
    }

}
